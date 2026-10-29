import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/failure_details.dart';
import 'charging_pile_http_client.dart';
import 'charging_pile_models.dart';

abstract interface class ChargingPileApi {
  Future<List<ChargingPileSlot>> queryDevice(
    String id,
    ChargingPileCancellation cancellation,
  );

  /// Releases the transport held by this implementation.
  void close();
}

/// Reads the source project's public query proxy instead of the upstream
/// platform.
///
/// On 2026-10-27 the source moved the shared credential into its Cloudflare
/// Worker: `/api/cred` now returns metadata only, and the Worker attaches
/// `Authorization` itself when it calls the platform. This client therefore
/// never holds, stores or decrypts a token; it only posts device ids to
/// `/api/pile` and reads the port states back.
class ChargingPileApiClient implements ChargingPileApi {
  ChargingPileApiClient({ChargingPileHttpClient? httpClient})
    : _http = httpClient ?? ChargingPileHttpClient();

  static final _proxy = Uri.parse('https://chd-charge.pages.dev/api/pile');

  /// The Worker rejects any other origin with
  /// `403 {"ok":false,"error":"bad_origin"}`, so the app presents the same
  /// origin the web client does. That check is a coarse anti-abuse gate rather
  /// than authentication, and a native client is not subject to CORS, so the
  /// header can be set directly. If the source tightens this gate, the proxy
  /// contract has to be renegotiated instead of spoofing more headers.
  static const _origin = 'https://chd-charge.pages.dev';

  /// The proxy is built around 12-device batches with at most two lanes and a
  /// per-minute upstream budget. One request per device exhausts that budget
  /// within a single catalog scan and trips its limiter, so callers are
  /// coalesced into batches here rather than at the repository layer.
  static const _batchSize = 12;
  static const _batchWindow = Duration(milliseconds: 25);

  final ChargingPileHttpClient _http;
  final _pending = <String, Completer<List<ChargingPileSlot>>>{};
  final _lifecycle = ChargingPileCancellation();
  Timer? _window;
  Future<void> _queue = Future<void>.value();
  bool _closed = false;

  @override
  Future<List<ChargingPileSlot>> queryDevice(
    String id,
    ChargingPileCancellation cancellation,
  ) async {
    cancellation.check();
    if (_closed) {
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
    final existing = _pending[id];
    if (existing != null) {
      final slots = await existing.future;
      cancellation.check();
      return slots;
    }
    final completer = Completer<List<ChargingPileSlot>>();
    _pending[id] = completer;
    _window ??= Timer(_batchWindow, _dispatch);
    final slots = await completer.future;
    cancellation.check();
    return slots;
  }

  void _dispatch() {
    _window = null;
    if (_closed || _pending.isEmpty) return;
    final ids = _pending.keys.take(_batchSize).toList(growable: false);
    final batch = <String, Completer<List<ChargingPileSlot>>>{
      for (final id in ids) id: _pending.remove(id)!,
    };
    if (_pending.isNotEmpty) _window = Timer(_batchWindow, _dispatch);
    _queue = _queue
        .then((_) => _send(ids, batch))
        .catchError((Object _) {});
  }

  Future<void> _send(
    List<String> ids,
    Map<String, Completer<List<ChargingPileSlot>>> batch,
  ) async {
    if (_closed) {
      _fail(
        batch,
        const ChargingPileException(ChargingPileFailure.cancelled),
      );
      return;
    }
    try {
      final response = await _http.postJson(
        _proxy,
        followRedirects: false,
        abortTrigger: _lifecycle.whenCancelled,
        body: {'ids': ids},
        headers: {'Origin': _origin, 'Referer': '$_origin/'},
        timeout: const Duration(seconds: 12),
      );
      final parsed = _parse(ids, response);
      for (final id in ids) {
        final completer = batch[id]!;
        if (completer.isCompleted) continue;
        final result = parsed[id];
        if (result is List<ChargingPileSlot>) {
          completer.complete(result);
        } else {
          completer.completeError(result as ChargingPileException);
        }
      }
    } catch (error) {
      _fail(batch, _failureOf(error));
    }
  }

  void _fail(
    Map<String, Completer<List<ChargingPileSlot>>> batch,
    ChargingPileException failure,
  ) {
    for (final completer in batch.values) {
      if (!completer.isCompleted) completer.completeError(failure);
    }
  }

  ChargingPileException _failureOf(Object error) {
    if (error is ChargingPileException) return error;
    if (error is PublicHttpException) {
      return ChargingPileException(
        error.failureReason == FailureReason.cancelled
            ? ChargingPileFailure.cancelled
            : ChargingPileFailure.network,
      );
    }
    return const ChargingPileException(ChargingPileFailure.malformed);
  }

  Map<String, Object> _parse(List<String> ids, http.Response response) {
    if (response.statusCode == 429) {
      throw const ChargingPileException(ChargingPileFailure.rateLimited);
    }
    if (response.statusCode >= 500 || response.statusCode == 408) {
      throw const ChargingPileException(ChargingPileFailure.network);
    }
    // `bad_origin` is the Worker refusing this client outright. Treat it as a
    // source-level outage so the repository pauses instead of firing the whole
    // catalog at a gate that will reject every request, and so the user sees a
    // source message rather than a per-device "device unavailable".
    if (response.statusCode == 403) {
      throw const ChargingPileException(
        ChargingPileFailure.credentialUnavailable,
      );
    }
    // Any other non-200 means the proxy contract broke (for example a moved
    // endpoint), not that this device is offline.
    if (response.statusCode != 200) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    final body = ChargingPileHttpClient.decodeJsonMap(
      utf8.decode(response.bodyBytes),
    );
    if (body['ok'] != true) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    final results = body['results'];
    if (results is! Map) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    final throttled = body['throttled'] == true;
    final authFailures = body['authFail'];
    final out = <String, Object>{};
    for (final id in ids) {
      final record = results[id];
      if (record is! Map) {
        // The proxy omits ids it refused to fetch. `throttled` is a documented
        // degradation (keep the previous snapshot), not a device failure, so it
        // must not pause the repository the way a real 429 does.
        if (throttled) {
          out[id] = const ChargingPileException(
            ChargingPileFailure.throttled,
          );
        } else if (authFailures is num && authFailures > 0) {
          out[id] = const ChargingPileException(
            ChargingPileFailure.credentialUnavailable,
          );
        } else {
          out[id] = const ChargingPileException(ChargingPileFailure.platform);
        }
        continue;
      }
      try {
        out[id] = _slotsOf(record, throttled: throttled);
      } on ChargingPileException catch (error) {
        out[id] = error;
      } catch (_) {
        out[id] = const ChargingPileException(ChargingPileFailure.malformed);
      }
    }
    return out;
  }

  List<ChargingPileSlot> _slotsOf(Map record, {required bool throttled}) {
    final auth = record['auth'];
    if (auth == true || (auth is String && auth.isNotEmpty)) {
      throw const ChargingPileException(
        ChargingPileFailure.credentialUnavailable,
      );
    }
    final error = record['error'];
    if (error is String && error.isNotEmpty) {
      if (RegExp(
        r'频繁|限流|too many|rate.limit',
        caseSensitive: false,
      ).hasMatch(error)) {
        throw const ChargingPileException(ChargingPileFailure.rateLimited);
      }
      throw const ChargingPileException(ChargingPileFailure.platform);
    }
    final ports = record['ports'];
    // An empty port list means "state unknown" upstream. Failing here keeps the
    // previous snapshot instead of rendering an unknown pile as fully free.
    if (ports is! List || ports.isEmpty || ports.length > 20) {
      throw ChargingPileException(
        throttled || record['throttled'] == true
            ? ChargingPileFailure.throttled
            : ChargingPileFailure.malformed,
      );
    }
    final slots = <ChargingPileSlot>[];
    final seen = <int>{};
    for (final item in ports) {
      if (item is! Map) throw const FormatException();
      final slotId = int.tryParse(item['num'].toString());
      final status = int.tryParse(item['state'].toString());
      if (slotId == null ||
          slotId < 1 ||
          slotId > 20 ||
          !seen.add(slotId) ||
          status == null ||
          status < 0 ||
          status > 9) {
        throw const FormatException();
      }
      slots.add(ChargingPileSlot(slotId: slotId, status: status));
    }
    return slots..sort((a, b) => a.slotId.compareTo(b.slotId));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _window?.cancel();
    _window = null;
    _lifecycle.cancel();
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ChargingPileException(ChargingPileFailure.cancelled),
        );
      }
    }
    _http.close();
  }
}
