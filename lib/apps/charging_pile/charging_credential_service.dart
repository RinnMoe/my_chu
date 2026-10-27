import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import 'charging_pile_models.dart';
import 'charging_sync_config.dart';
import '../../services/privacy_agreement_service.dart';
import 'charging_pile_http_client.dart';

/// Decodes the source project's WebCrypto envelope. Runs off the UI isolate.
/// This is encryption compatibility, not JWT signature verification.
String decryptChargingMailbox(Map<String, String> input) {
  try {
    final pack = jsonDecode(input['data']!);
    if (pack is! Map || pack['kdf'] != 'PBKDF2-SHA256-200000') {
      throw const FormatException();
    }
    final salt = base64Decode(pack['salt'] as String);
    final packed = base64Decode(pack['cipher'] as String);
    if (salt.length != 16 || packed.length < 29 || packed.length > 16384) {
      throw const FormatException();
    }
    final derive = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 200000, 32));
    final key = derive.process(Uint8List.fromList(utf8.encode(input['key']!)));
    final cipher = GCMBlockCipher(AESEngine())..init(
      false,
      AEADParameters(
        KeyParameter(key),
        128,
        Uint8List.sublistView(packed, 0, 12),
        Uint8List(0),
      ),
    );
    return utf8.decode(cipher.process(Uint8List.sublistView(packed, 12)));
  } catch (_) {
    throw const ChargingPileException(ChargingPileFailure.credentialSync);
  }
}

/// Credentials owned by this feature's data layer, separate from campus CAS.
///
/// ChargingPileHttpClient supplies the feature-local HTTP transport. Only this service
/// may attach the credential, to the fixed scan-code endpoint, with redirects
/// disabled by the transport's authenticated request helper. UI and repository
/// never receive a token. There is no upload or mailbox write endpoint here.
class ChargingCredentialService {
  ChargingCredentialService({
    ChargingPileHttpClient? httpClient,
    FlutterSecureStorage? storage,
    Future<bool> Function()? consent,
    DateTime Function()? now,
    Future<String> Function(Map<String, String>)? decrypt,
  }) : _http = httpClient ?? ChargingPileHttpClient(),
       _storage = storage ?? const FlutterSecureStorage(),
       _consent = consent ?? PrivacyAgreementService.isAccepted,
       _now = now ?? DateTime.now,
       _decrypt =
           decrypt ?? ((input) => compute(decryptChargingMailbox, input));

  // Preserve the existing key. Legacy raw JWT values are read in place and
  // upgraded to a versioned record on the next successful sync/rejection.
  static const storageKey = 'charging_pile.token.v1';
  static final _mailbox = Uri.parse('https://chd-charge.pages.dev/api/cred');
  static final _scan = Uri.parse(
    'https://union.zhumanggroup.com/api/rent/scan-code',
  );
  final ChargingPileHttpClient _http;
  final FlutterSecureStorage _storage;
  final Future<bool> Function() _consent;
  final DateTime Function() _now;
  final Future<String> Function(Map<String, String>) _decrypt;
  String? _token;
  String? _recoveredToken;
  int _updatedAt = 0;
  bool _rejected = false;
  bool _restored = false;
  bool _closed = false;
  int _epoch = 0;
  ChargingPileCancellation _lifecycle = ChargingPileCancellation();
  DateTime? _lastSync;
  Future<void>? _syncing;
  Future<void>? _recovering;
  Future<void> _writes = Future.value();

  Future<void> _guard(int epoch, ChargingPileCancellation? cancellation) async {
    cancellation?.check();
    if (_closed || epoch != _epoch) {
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
    bool accepted;
    try {
      accepted = await _consent();
    } catch (_) {
      throw const ChargingPileException(ChargingPileFailure.storage);
    }
    if (!accepted) {
      throw const ChargingPileException(ChargingPileFailure.consentRequired);
    }
    cancellation?.check();
    if (_closed || epoch != _epoch) {
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
  }

  static DateTime? expiresAt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num || !exp.isFinite || exp <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  bool get _usable =>
      !_rejected &&
      _token != null &&
      (expiresAt(_token!)?.isAfter(_now().add(const Duration(seconds: 30))) ??
          false);

  Future<void> _restore(int epoch) async {
    if (_restored) return;
    String? raw;
    try {
      raw = await _storage.read(key: storageKey);
    } catch (_) {
      throw const ChargingPileException(ChargingPileFailure.storage);
    }
    await _guard(epoch, null);
    if (_restored) return;
    _restored = true;
    if (raw == null) return;
    try {
      if (raw.startsWith('{')) {
        final record = jsonDecode(raw);
        if (record is! Map ||
            record['version'] != 2 ||
            record['token'] is! String ||
            record['updatedAt'] is! int ||
            (record['updatedAt'] as int) < 0)
          return;
        _token = record['token'];
        _updatedAt = record['updatedAt'];
        _rejected = record['rejected'] == true;
      } else if (expiresAt(raw) != null) {
        _token = raw;
      }
    } catch (_) {
      /* A damaged local record is replaced by a valid mailbox. */
    }
  }

  Future<void> _persist(int epoch) {
    final value = jsonEncode({
      'version': 2,
      'token': _token,
      'updatedAt': _updatedAt,
      'rejected': _rejected,
    });
    final write = _writes.then((_) async {
      await _guard(epoch, null);
      try {
        await _storage.write(key: storageKey, value: value);
      } catch (_) {
        throw const ChargingPileException(ChargingPileFailure.storage);
      }
      await _guard(epoch, null);
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  /// Coalesced process-wide mailbox sync; a failed sync may use a valid local
  /// credential. [force] bypasses the 60-second mailbox throttle so that an
  /// explicit user retry always reaches the source instead of silently
  /// replaying the previous failure.
  Future<void> syncCredential({bool force = false}) async {
    final epoch = _epoch;
    await _guard(epoch, null);
    await _restore(epoch);
    await _sync(bypassThrottle: force);
    await _guard(epoch, null);
    if (!_usable) {
      throw const ChargingPileException(
        ChargingPileFailure.credentialUnavailable,
      );
    }
  }

  Future<void> _sync({bool bypassThrottle = false}) async {
    if (_syncing case final flight?) return flight;
    if (!bypassThrottle &&
        _lastSync != null &&
        _now().difference(_lastSync!) < const Duration(seconds: 60))
      return;
    final flight = _syncOnce(_epoch);
    _syncing = flight;
    try {
      await flight;
    } finally {
      if (identical(_syncing, flight)) _syncing = null;
    }
  }

  Future<void> _syncOnce(int epoch) async {
    _lastSync = _now();
    try {
      await _guard(epoch, null);
      final response = await _http.get(
        _mailbox,
        headers: {'Accept': 'application/json', 'Cache-Control': 'no-cache'},
        timeout: const Duration(seconds: 4),
        abortTrigger: _lifecycle.whenCancelled,
      );
      await _guard(epoch, null);
      if (response.statusCode != 200) {
        throw const ChargingPileException(ChargingPileFailure.credentialSync);
      }
      final box = ChargingPileHttpClient.decodeJsonMap(
        utf8.decode(response.bodyBytes),
      );
      if (box['ok'] != true || box['exists'] != true) {
        throw const ChargingPileException(
          ChargingPileFailure.credentialUnavailable,
        );
      }
      final stamp = box['updatedAt'];
      final data = box['data'];
      if (stamp is! int ||
          stamp <= 0 ||
          data is! String ||
          data.length > 32768) {
        throw const ChargingPileException(ChargingPileFailure.credentialSync);
      }
      if (stamp <= _updatedAt) return;
      final token = await _decrypt({
        'data': data,
        'key': chargingMailboxSyncKey,
      });
      await _guard(epoch, null);
      if (expiresAt(token) == null) {
        throw const ChargingPileException(ChargingPileFailure.credentialSync);
      }
      // A new envelope containing the same rejected token cannot revive it.
      final sameRejected = _rejected && token == _token;
      _token = token;
      _updatedAt = stamp;
      _rejected = sameRejected;
      await _persist(epoch);
    } on ChargingPileException catch (error) {
      if (error.failure == ChargingPileFailure.cancelled ||
          error.failure == ChargingPileFailure.consentRequired ||
          error.failure == ChargingPileFailure.storage ||
          !_usable)
        rethrow;
    } catch (_) {
      if (!_usable) {
        throw const ChargingPileException(ChargingPileFailure.credentialSync);
      }
    }
  }

  Future<void> _recover(String rejected, int epoch) async {
    if (_token != rejected) return;
    if (_recovering case final flight?) return flight;
    if (_recoveredToken == rejected) {
      throw const ChargingPileException(
        ChargingPileFailure.credentialUnavailable,
      );
    }
    final flight = () async {
      _recoveredToken = rejected;
      _rejected = true;
      await _persist(epoch);
      await _sync(bypassThrottle: true);
      if (!_usable || _token == rejected) {
        throw const ChargingPileException(
          ChargingPileFailure.credentialUnavailable,
        );
      }
    }();
    _recovering = flight;
    try {
      await flight;
    } finally {
      if (identical(_recovering, flight)) _recovering = null;
    }
  }

  static bool _authFailure(http.Response response) {
    // Auth HTTP status takes precedence over empty/HTML error bodies.
    if (response.statusCode == 401 || response.statusCode == 403) return true;
    if (response.statusCode != 200) return false;
    try {
      final body = ChargingPileHttpClient.decodeJsonMap(
        utf8.decode(response.bodyBytes),
      );
      return body['code'].toString() == '401' ||
          body['code'].toString() == '403';
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> queryDevice(
    String deviceId,
    ChargingPileCancellation cancellation,
  ) async {
    final epoch = _epoch;
    await _guard(epoch, cancellation);
    await syncCredential();
    for (var attempt = 0; attempt < 2; attempt++) {
      await _guard(epoch, cancellation);
      if (!_usable) {
        throw const ChargingPileException(
          ChargingPileFailure.credentialUnavailable,
        );
      }
      final used = _token!;
      final response = await _http.postJson(
        _scan,
        followRedirects: false,
        abortTrigger: Future.any([
          cancellation.whenCancelled,
          _lifecycle.whenCancelled,
        ]),
        body: {'out_number': deviceId},
        headers: {
          'Authorization': 'Bearer $used',
          'sd-version': '127',
          'sd-env': 'production',
          'app-source': 'jd',
          'zm-origin': '1',
        },
        timeout: const Duration(seconds: 8),
      );
      await _guard(epoch, cancellation);
      if (!_authFailure(response)) return response;
      if (attempt == 1) {
        if (_token == used) {
          _rejected = true;
          await _persist(epoch);
        }
        throw const ChargingPileException(
          ChargingPileFailure.credentialUnavailable,
        );
      }
      await _recover(used, epoch);
    }
    throw const ChargingPileException(
      ChargingPileFailure.credentialUnavailable,
    );
  }

  /// Invalidate late callbacks without deleting unrelated secure storage.
  void cancelPending() {
    _epoch++;
    _lifecycle.cancel();
    _lifecycle = ChargingPileCancellation();
    if (_syncing != null) _lastSync = null;
    _syncing = null;
    _recovering = null;
  }

  void close() {
    _closed = true;
    cancelPending();
    _http.close();
  }
}
