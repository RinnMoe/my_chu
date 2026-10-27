import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../services/public_http_client.dart';
import 'charging_pile_models.dart';

/// The user's token is invalid or expired.
class ChargingPileAuthException implements Exception {
  final String message;
  const ChargingPileAuthException(this.message);

  @override
  String toString() => message;
}

/// Read-only client for the Zhumang/Jiedian charging-pile status API.
///
/// This service intentionally supports only the `scan-code` query endpoint.
/// It never logs in, rents a slot, ends an order, or performs a payment.
class ChargingPileService {
  static final _apiUri = Uri.parse('https://union.zhumanggroup.com/api/rent/scan-code');

  static const _storageKey = 'charging_pile.token.v1';
  static const _concurrency = 6;
  static const _requestTimeout = Duration(seconds: 8);
  static const _retryDelay = Duration(milliseconds: 800);

  /// Local freshness window. Manual refreshes must also respect this value to
  /// avoid sending 109 requests per interaction to the private API.
  final Duration refreshInterval;

  final PublicHttpClient _httpClient;
  final FlutterSecureStorage _storage;
  final Future<String?> Function(String key)? _secureRead;
  final Future<void> Function(String key, String value)? _secureWrite;
  final Future<void> Function(String key)? _secureDelete;
  final DateTime Function() _now;

  DateTime? _lastRefreshAt;

  ChargingPileService({
    PublicHttpClient? httpClient,
    FlutterSecureStorage? storage,
    Future<String?> Function(String key)? secureRead,
    Future<void> Function(String key, String value)? secureWrite,
    Future<void> Function(String key)? secureDelete,
    DateTime Function()? now,
    this.refreshInterval = const Duration(seconds: 60),
  }) : _httpClient = httpClient ?? PublicHttpClient(defaultTimeout: _requestTimeout),
       _storage = storage ?? const FlutterSecureStorage(),
       _secureRead = secureRead,
       _secureWrite = secureWrite,
       _secureDelete = secureDelete,
       _now = now ?? DateTime.now;

  DateTime? get lastRefreshAt => _lastRefreshAt;

  Duration get timeUntilNextRefresh {
    final last = _lastRefreshAt;
    if (last == null) return Duration.zero;
    final elapsed = _now().difference(last);
    if (elapsed >= refreshInterval) return Duration.zero;
    return refreshInterval - elapsed;
  }

  bool shouldRefresh() => timeUntilNextRefresh == Duration.zero;

  Future<String?> readToken() async {
    final token = await _readSecure(_storageKey);
    return token?.trim().isEmpty == true ? null : token?.trim();
  }

  Future<void> saveToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    await _writeSecure(_storageKey, trimmed);
  }

  Future<void> clearToken() => _deleteSecure(_storageKey);

  /// Extracts a JWT from a raw token, Authorization header, cURL command,
  /// JSON body, or a URL containing `t=`.
  static String? extractToken(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    final hashMatch = RegExp(r'[#?]t=([^&\s]+)').firstMatch(text);
    if (hashMatch != null) {
      try {
        text = Uri.decodeComponent(hashMatch.group(1)!);
      } on ArgumentError {
        text = hashMatch.group(1)!;
      }
    }

    const jwtSource = r'eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}';
    final named = RegExp(
      '(?:authorization|token)["\']?\\s*[:=]\\s*["\']?\\s*(?:Bearer\\s+)?($jwtSource)',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) return named.group(1);

    final any = RegExp(jwtSource).firstMatch(text);
    if (any != null) return any.group(0);

    final withoutBearer = text.replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    ).trim();
    final normalized = withoutBearer.replaceAll(RegExp(r'\s+'), '');
    return normalized.isEmpty ? null : normalized;
  }

  /// Validates pasted input and returns either an error or the extracted token.
  static ({String? token, String? error}) normalizeToken(String raw) {
    final token = extractToken(raw);
    if (token == null) {
      return (token: null, error: '没有读到凭证，请粘贴整串 Authorization 或 token。');
    }
    if (token.split('.').length != 3) {
      return (token: null, error: '这不是完整的 JWT（应为三段点分隔的长串）。');
    }
    return (token: token, error: null);
  }

  /// Interprets the JWT payload without returning or logging the token.
  static ChargingPileTokenInfo tokenInfo(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return ChargingPileTokenInfo.none;
    }
    final parts = trimmed.split('.');
    if (parts.length != 3) {
      return const ChargingPileTokenInfo(
        state: ChargingPileTokenState.invalid,
      );
    }
    final payload = _decodeJwtPayload(parts[1]);
    if (payload == null) {
      return const ChargingPileTokenInfo(state: ChargingPileTokenState.opaque);
    }
    final exp = payload['exp'];
    if (exp is! num || exp <= 0) {
      return const ChargingPileTokenInfo(state: ChargingPileTokenState.opaque);
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return ChargingPileTokenInfo(
        state: ChargingPileTokenState.expired,
        expiresAt: expiresAt,
      );
    }
    final state =
        remaining.inHours < 36
            ? ChargingPileTokenState.expiringSoon
            : ChargingPileTokenState.valid;
    return ChargingPileTokenInfo(
      state: state,
      expiresAt: expiresAt,
    );
  }

  static Map<String, dynamic>? _decodeJwtPayload(String encoded) {
    try {
      var normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
      normalized += '=' * ((4 - normalized.length % 4) % 4);
      final bytes = base64Decode(normalized);
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  /// Queries all devices with bounded concurrency and progressive callbacks.
  ///
  /// [onDeviceResult] is invoked once per completed device so the UI can update
  /// without waiting for all 109 requests.
  Future<ChargingPileRefreshResult> refresh({
    required List<ChargingPileDevice> devices,
    required String token,
    void Function(
      ChargingPileDeviceStatus? status,
      ChargingPileDeviceFailure? failure,
    )?
    onDeviceResult,
  }) async {
    final startedAt = _now();
    final statuses = <ChargingPileDeviceStatus>[];
    final failures = <ChargingPileDeviceFailure>[];
    var authFailed = false;
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final current = index++;
        if (current >= devices.length) return;
        if (authFailed) {
          final failure = ChargingPileDeviceFailure(
            device: devices[current],
            message: '凭证已失效，请更新后重新查询。',
            authFailure: true,
            fetchedAt: startedAt,
          );
          failures.add(failure);
          onDeviceResult?.call(null, failure);
          continue;
        }

        final device = devices[current];
        try {
          final slots = await _queryDevice(device.id, token);
          final status = ChargingPileDeviceStatus(
            device: device,
            slots: slots,
            fetchedAt: startedAt,
          );
          statuses.add(status);
          onDeviceResult?.call(status, null);
        } on ChargingPileAuthException catch (error) {
          authFailed = true;
          final failure = ChargingPileDeviceFailure(
            device: device,
            message: error.message,
            authFailure: true,
            fetchedAt: startedAt,
          );
          failures.add(failure);
          onDeviceResult?.call(null, failure);
        } on Object catch (error) {
          final failure = ChargingPileDeviceFailure(
            device: device,
            message: error.toString(),
            fetchedAt: startedAt,
          );
          failures.add(failure);
          onDeviceResult?.call(null, failure);
        }
      }
    }

    final workers = List.generate(
      _concurrency,
      (_) => worker(),
      growable: false,
    );
    await Future.wait(workers);

    _lastRefreshAt = _now();
    return ChargingPileRefreshResult(
      fetchedAt: startedAt,
      statuses: statuses,
      failures: failures,
      authFailed: authFailed,
    );
  }

  Future<List<ChargingPileSlot>> _queryDevice(
    String deviceId,
    String token,
  ) async {
    try {
      return await _fetchSlotsOnce(deviceId, token);
    } on ChargingPileAuthException {
      rethrow;
    } on Object {
      await Future<void>.delayed(_retryDelay);
      try {
        return await _fetchSlotsOnce(deviceId, token);
      } on ChargingPileAuthException {
        rethrow;
      } on Object {
        throw const ChargingPileDeviceQueryException('设备状态未知，请稍后重新查询。');
      }
    }
  }

  Future<List<ChargingPileSlot>> _fetchSlotsOnce(
    String deviceId,
    String token,
  ) async {
    final response = await _httpClient.postJson(
      _apiUri,
      body: {'out_number': deviceId},
      headers: {
        'Authorization': 'Bearer $token',
        'sd-version': '127',
        'sd-env': 'production',
        'app-source': 'jd',
        'zm-origin': '1',
      },
      timeout: _requestTimeout,
    );

    Map<String, dynamic> body;
    try {
      body = PublicHttpClient.decodeJsonMap(response.body);
    } on Object {
      throw ChargingPileDeviceQueryException(
        '平台返回格式异常（HTTP ${response.statusCode}）。',
      );
    }

    final code = body['code'];
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        code == 401 ||
        code == 403) {
      throw ChargingPileAuthException(
        (body['message']?.toString() ?? '').trim().isEmpty
            ? '凭证已失效，请重新抓取 Authorization。'
            : body['message'].toString(),
      );
    }
    if (code != 200) {
      throw ChargingPileDeviceQueryException(
        (body['message']?.toString() ?? '').trim().isEmpty
            ? '平台返回异常状态（${code ?? response.statusCode}）。'
            : body['message'].toString(),
      );
    }

    final data = body['data'];
    final slotsData =
        data is Map<String, dynamic> ? data['slotsData'] : data['slotsData'];
    if (slotsData is! List || slotsData.isEmpty) {
      throw const ChargingPileDeviceQueryException('平台没有返回插座数据。');
    }

    final slots = <ChargingPileSlot>[];
    for (final item in slotsData) {
      if (item is! Map) continue;
      final slotId = int.tryParse(item['slotId'].toString());
      if (slotId == null) continue;
      final status = int.tryParse(item['status'].toString());
      slots.add(ChargingPileSlot(slotId: slotId, free: status == 0));
    }
    slots.sort((a, b) => a.slotId.compareTo(b.slotId));
    if (slots.isEmpty) {
      throw const ChargingPileDeviceQueryException('插座编号无法识别。');
    }
    return slots;
  }

  /// Releases the HTTP connection pool when this service owns it.
  void close() => _httpClient.close();

  Future<String?> _readSecure(String key) {
    final hook = _secureRead;
    if (hook != null) return hook(key);
    return _storage.read(key: key);
  }

  Future<void> _writeSecure(String key, String value) {
    final hook = _secureWrite;
    if (hook != null) return hook(key, value);
    return _storage.write(key: key, value: value);
  }

  Future<void> _deleteSecure(String key) {
    final hook = _secureDelete;
    if (hook != null) return hook(key);
    return _storage.delete(key: key);
  }
}

/// A non-auth failure for one device after its single retry.
class ChargingPileDeviceQueryException implements Exception {
  final String message;
  const ChargingPileDeviceQueryException(this.message);

  @override
  String toString() => message;
}
