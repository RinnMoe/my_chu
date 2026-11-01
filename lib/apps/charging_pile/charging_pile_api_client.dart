import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../services/failure_details.dart';
import 'charging_pile_http_client.dart';
import 'charging_pile_models.dart';

abstract interface class ChargingPileApi {
  Future<List<ChargingPileSlot>> queryDevice(
    ChargingPileDevice device,
    ChargingPileCancellation cancellation, {
    bool fresh = false,
  });

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
///
/// The request shape mirrors the source's own client (`PILE_PROXY_CHUNK` /
/// `PILE_LANES` / `PILE_PROXY_TIMEOUT_MS`):
/// - one batch carries **one** `src`; mixing sources makes the Worker call the
///   wrong platform and the other half 404s;
/// - `fresh` is only sent for an explicit user refresh, and even then the
///   Worker reuses its edge cache while that cache is younger than its own
///   freshness threshold, so `fresh` never guarantees an origin fetch;
/// - port states are normalised the way the source normalises them:
///   `0` free, `1` occupied, anything else (`-1` abnormal, offline, …) → `2`.
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
  static const _lanes = 2;
  static const _batchWindow = Duration(milliseconds: 25);

  /// 与站点 `PILE_PROXY_TIMEOUT_MS` 一致：一批最长 25 秒。
  static const _requestTimeout = Duration(seconds: 25);

  final ChargingPileHttpClient _http;
  final _pending = <String, _PendingQuery>{};
  final _laneQueues = <List<_Batch>>[<_Batch>[], <_Batch>[]];
  final _laneBusy = <bool>[false, false];
  final _lifecycle = ChargingPileCancellation();
  Timer? _window;
  bool _closed = false;

  @override
  Future<List<ChargingPileSlot>> queryDevice(
    ChargingPileDevice device,
    ChargingPileCancellation cancellation, {
    bool fresh = false,
  }) async {
    cancellation.check();
    if (_closed) {
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
    final existing = _pending[device.id];
    if (existing != null) {
      existing.fresh |= fresh;
      final slots = await existing.completer.future;
      cancellation.check();
      return slots;
    }
    final pending = _PendingQuery(device: device, fresh: fresh);
    _pending[device.id] = pending;
    _window ??= Timer(_batchWindow, _dispatch);
    final slots = await pending.completer.future;
    cancellation.check();
    return slots;
  }

  void _dispatch() {
    _window = null;
    if (_closed || _pending.isEmpty) return;
    final bySource = <ChargingPileSource, List<String>>{};
    for (final entry in _pending.entries) {
      bySource.putIfAbsent(entry.value.device.source, () => <String>[]).add(
        entry.key,
      );
    }
    final batches = <_Batch>[];
    for (final entry in bySource.entries) {
      final ids = entry.value;
      for (var i = 0; i < ids.length; i += _batchSize) {
        final slice = ids.sublist(i, math.min(i + _batchSize, ids.length));
        final entries = <String, _PendingQuery>{};
        var fresh = false;
        for (final id in slice) {
          final pending = _pending.remove(id);
          if (pending == null) continue;
          entries[id] = pending;
          fresh |= pending.fresh;
        }
        if (entries.isEmpty) continue;
        batches.add(
          _Batch(source: entry.key, fresh: fresh, entries: entries),
        );
      }
    }
    if (batches.isEmpty) return;
    for (var i = 0; i < batches.length; i++) {
      _laneQueues[i % _lanes].add(batches[i]);
    }
    _pump();
  }

  void _pump() {
    for (var lane = 0; lane < _lanes; lane++) {
      if (_laneBusy[lane]) continue;
      final queue = _laneQueues[lane];
      if (queue.isEmpty) continue;
      final batch = queue.removeAt(0);
      _laneBusy[lane] = true;
      _send(batch).whenComplete(() {
        _laneBusy[lane] = false;
        if (_closed) return;
        _pump();
      });
    }
  }

  Future<void> _send(_Batch batch) async {
    final ids = batch.entries.keys.toList(growable: false);
    if (_closed) {
      _fail(batch, const ChargingPileException(ChargingPileFailure.cancelled));
      return;
    }
    final body = <String, Object>{'ids': ids};
    if (batch.fresh) body['fresh'] = true;
    // 住芒是缺省源，不写 `src`；只有驴充充的批次显式带。
    if (batch.source != ChargingPileSource.zhumang) {
      body['src'] = batch.source.wireValue;
    }
    try {
      final response = await _http.postJson(
        _proxy,
        followRedirects: false,
        abortTrigger: _lifecycle.whenCancelled,
        body: body,
        headers: {'Origin': _origin, 'Referer': '$_origin/'},
        timeout: _requestTimeout,
      );
      final parsed = _parse(ids, response);
      for (final id in ids) {
        final pending = batch.entries[id]!;
        if (pending.completer.isCompleted) continue;
        final result = parsed[id];
        if (result is List<ChargingPileSlot>) {
          pending.completer.complete(result);
        } else {
          pending.completer.completeError(result as ChargingPileException);
        }
      }
    } catch (error) {
      _fail(batch, _failureOf(error));
    }
  }

  void _fail(_Batch batch, ChargingPileException failure) {
    for (final pending in batch.entries.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(failure);
      }
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
    // `locked` is the Worker's global origin-fetch lock: this round was
    // degraded to "use what you already have", exactly like `throttled`.
    if (record['locked'] == true) {
      throw const ChargingPileException(ChargingPileFailure.throttled);
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
    // device unknown instead of rendering it as fully free.
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
      final rawState = int.tryParse(item['state'].toString());
      if (slotId == null || slotId < 1 || slotId > 20 || !seen.add(slotId)) {
        throw const FormatException();
      }
      if (rawState == null) throw const FormatException();
      // 站点口径：0 空闲 / 1 占用 / 其余（含 -1 异常、离线）一律 2。
      final status = rawState == 0 ? 0 : (rawState == 1 ? 1 : 2);
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
    for (final entry in pending) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(
          const ChargingPileException(ChargingPileFailure.cancelled),
        );
      }
    }
    _http.close();
  }
}

class _PendingQuery {
  _PendingQuery({required this.device, required this.fresh});

  final ChargingPileDevice device;
  bool fresh;
  final completer = Completer<List<ChargingPileSlot>>();
}

class _Batch {
  _Batch({required this.source, required this.fresh, required this.entries});

  final ChargingPileSource source;
  final bool fresh;
  final Map<String, _PendingQuery> entries;
}
