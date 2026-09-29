import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Authentication status for the external channel-resources service.
enum ChannelResourcesSessionStatus {
  signedOut,
  restoring,
  authenticated,
  unavailable,
}

/// Host-owned error categories. The UI can map these to user-safe copy without
/// receiving a token, cookie, password, or raw response body.
enum ChannelResourcesSessionErrorType {
  notAuthenticated,
  invalidCredentials,
  expired,
  network,
  server,
  malformed,
  retryRequired,
  stale,
}

class ChannelResourcesSessionException implements Exception {
  final ChannelResourcesSessionErrorType type;
  final int? statusCode;

  const ChannelResourcesSessionException(this.type, {this.statusCode});

  String get userMessage {
    switch (type) {
      case ChannelResourcesSessionErrorType.notAuthenticated:
        return '请先登录频道账号。';
      case ChannelResourcesSessionErrorType.invalidCredentials:
        return '账号或密码不正确。';
      case ChannelResourcesSessionErrorType.expired:
        return '账号登录已过期，请重新登录。';
      case ChannelResourcesSessionErrorType.network:
        return '账号服务暂时无法连接，请稍后重试。';
      case ChannelResourcesSessionErrorType.server:
        return '账号服务暂时不可用，请稍后重试。';
      case ChannelResourcesSessionErrorType.malformed:
        return '资料站返回了无法识别的数据。';
      case ChannelResourcesSessionErrorType.retryRequired:
        return '登录状态已恢复，请重新操作。';
      case ChannelResourcesSessionErrorType.stale:
        return '账号状态已变化，请重试。';
    }
  }

  @override
  String toString() =>
      'ChannelResourcesSessionException(${type.name}, $statusCode)';
}

/// Non-secret profile data returned by the channel service.
class ChannelResourcesUser {
  final String id;
  final String nickname;
  final int? points;
  final String loginType;
  final String identityType;
  final bool isDefaultPassword;
  final String? username;

  const ChannelResourcesUser({
    required this.id,
    required this.nickname,
    this.points,
    required this.loginType,
    required this.identityType,
    required this.isDefaultPassword,
    this.username,
  });
}

class ChannelResourcesAuthState {
  final ChannelResourcesSessionStatus status;
  final ChannelResourcesUser? user;
  final ChannelResourcesSessionErrorType? errorType;

  const ChannelResourcesAuthState(this.status, {this.user, this.errorType});

  bool get isAuthenticated =>
      status == ChannelResourcesSessionStatus.authenticated && user != null;
}

/// A deliberately small response object for the host-owned transport.
/// Response headers are reduced to fields needed for redirects, refresh-cookie
/// rotation, and safe file classification; request credentials never leave the
/// session service.
class ChannelResourcesHttpResponse {
  final int statusCode;
  final List<int> bytes;
  final String? contentType;
  final List<String> setCookieHeaders;

  const ChannelResourcesHttpResponse(
    this.statusCode,
    this.bytes, {
    this.contentType,
    this.setCookieHeaders = const <String>[],
  });

  String get body => utf8.decode(bytes, allowMalformed: true);
}

typedef ChannelResourcesTransport =
    Future<ChannelResourcesHttpResponse> Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      List<int>? body,
    });

/// Dedicated host-side session for `qbot.evian.asia`.
///
/// This is intentionally not a [CampusServiceId] and never participates in
/// CAS. Access tokens live only in memory. The rotated refresh cookie is
/// persisted for session restoration in the channel identity namespace. The
/// channel session has its own generation fence and never derives state from
/// the campus account or its authentication revision.
class ChannelResourcesSession {
  static final Uri productionBaseUri = Uri.parse(
    'https://qbot.evian.asia/api/',
  );

  static const _connectionTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 15);
  static const _refreshStorageKey = 'mychu.channel_resources.refresh';

  final FlutterSecureStorage _storage;
  final ChannelResourcesTransport _transport;
  final Uri _baseUri;
  final ValueNotifier<ChannelResourcesAuthState> _stateNotifier = ValueNotifier<
    ChannelResourcesAuthState
  >(const ChannelResourcesAuthState(ChannelResourcesSessionStatus.signedOut));

  String? _accessToken;
  String? _refreshCookie;
  ChannelResourcesUser? _user;
  bool _rememberSession = true;
  ChannelResourcesSessionStatus _status =
      ChannelResourcesSessionStatus.signedOut;
  ChannelResourcesSessionErrorType? _errorType;
  Future<ChannelResourcesAuthState>? _restoreFlight;
  Future<bool>? _refreshFlight;
  Future<ChannelResourcesAuthState>? _loginFlight;
  int _generation = 0;

  ChannelResourcesSession({
    FlutterSecureStorage? storage,
    ChannelResourcesTransport? transport,
    Uri? baseUri,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _transport = transport ?? _defaultTransport,
       _baseUri = _normalizeBaseUri(baseUri ?? productionBaseUri);

  ChannelResourcesSessionStatus get status => _status;
  ChannelResourcesUser? get user => _user;
  ChannelResourcesAuthState get authState => _stateNotifier.value;
  ValueListenable<ChannelResourcesAuthState> get authStateListenable =>
      _stateNotifier;

  /// Restores the persisted channel refresh session. A transient refresh
  /// failure keeps the refresh credential available for an explicit retry;
  /// passwords are never used for recovery.
  Future<ChannelResourcesAuthState> restore() {
    if (_accessToken != null &&
        _user != null &&
        _status == ChannelResourcesSessionStatus.authenticated) {
      return Future.value(authState);
    }
    final running = _restoreFlight;
    if (running != null) return running;
    final generation = _generation;
    _status = ChannelResourcesSessionStatus.restoring;
    _emitState();
    final future = _restoreImpl(generation);
    _restoreFlight = future;
    future.whenComplete(() {
      if (identical(_restoreFlight, future)) _restoreFlight = null;
    });
    return future;
  }

  Future<ChannelResourcesAuthState> _restoreImpl(int generation) async {
    try {
      _refreshCookie = await _storage.read(key: _refreshStorageKey);
      _checkFence(generation);
      if (_refreshCookie == null || _refreshCookie!.isEmpty) {
        _setSignedOut(generation);
        return authState;
      }
      final refreshed = await _refresh(generation);
      if (!refreshed) return authState;
      return authState;
    } on ChannelResourcesSessionException catch (error) {
      if (error.type == ChannelResourcesSessionErrorType.stale) rethrow;
      if (_isGenerationCurrent(generation)) {
        _status = ChannelResourcesSessionStatus.unavailable;
        _errorType = error.type;
        _emitState();
      }
      return authState;
    } on Object {
      if (_isGenerationCurrent(generation)) {
        _status = ChannelResourcesSessionStatus.unavailable;
        _errorType = ChannelResourcesSessionErrorType.network;
        _emitState();
      }
      return authState;
    }
  }

  /// Logs in and optionally persists the refresh credential after success.
  /// The password is used only for this explicit request and is never stored.
  Future<ChannelResourcesAuthState> login({
    required String username,
    required String password,
    bool rememberSession = false,
  }) {
    final running = _loginFlight;
    if (running != null) return running;
    final generation = ++_generation;
    _accessToken = null;
    _refreshCookie = null;
    _user = null;
    _errorType = null;
    _status = ChannelResourcesSessionStatus.signedOut;
    _emitState();
    _rememberSession = rememberSession;
    final future = _loginImpl(
      username.trim(),
      password,
      generation,
      rememberSession,
    );
    _loginFlight = future;
    future.whenComplete(() {
      if (identical(_loginFlight, future)) _loginFlight = null;
    });
    return future;
  }

  Future<ChannelResourcesAuthState> _loginImpl(
    String username,
    String password,
    int generation,
    bool rememberSession,
  ) async {
    if (username.isEmpty || password.isEmpty) {
      _setLoginFailure(
        generation,
        ChannelResourcesSessionErrorType.invalidCredentials,
      );
      return authState;
    }
    try {
      // An explicit login starts a new channel-account boundary. Remove the
      // previous account's persisted refresh credential before sending the new
      // password so a missing Set-Cookie can never inherit it.
      await _deletePersistedRefreshCookie(generation);
      _checkFence(generation);
      final response = await _sendRaw(
        'POST',
        _pathUri('auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: utf8.encode(
          jsonEncode({
            'username': username,
            'password': password,
            'permission_mode': 'member',
          }),
        ),
      );
      _checkFence(generation);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        _setLoginFailure(
          generation,
          ChannelResourcesSessionErrorType.invalidCredentials,
        );
        return authState;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setLoginFailure(generation, ChannelResourcesSessionErrorType.server);
        return authState;
      }
      final payload = _jsonMap(response);
      final accessToken = _string(payload['access_token']);
      final user = _parseUser(payload['user']);
      if (accessToken == null || user == null) {
        throw const ChannelResourcesSessionException(
          ChannelResourcesSessionErrorType.malformed,
        );
      }
      final rotatedCookie = _refreshCookieFrom(response.setCookieHeaders);
      if (rememberSession && (rotatedCookie == null || rotatedCookie.isEmpty)) {
        throw const ChannelResourcesSessionException(
          ChannelResourcesSessionErrorType.malformed,
        );
      }
      _checkFence(generation);
      _accessToken = accessToken;
      _refreshCookie = rotatedCookie;
      if (rememberSession) {
        await _persistRefreshCookie(generation);
      } else {
        await _deletePersistedRefreshCookie(generation);
      }
      _checkFence(generation);
      _user = user;
      _status = ChannelResourcesSessionStatus.authenticated;
      _errorType = null;
      _emitState();
      return authState;
    } on ChannelResourcesSessionException catch (error) {
      if (error.type == ChannelResourcesSessionErrorType.stale) rethrow;
      _setLoginFailure(generation, error.type);
      return authState;
    } on Object {
      _setLoginFailure(generation, ChannelResourcesSessionErrorType.network);
      return authState;
    }
  }

  /// Sends a request for the current account.
  ///
  /// A 401 always attempts to refresh the channel session first. Safe reads
  /// are replayed once after a successful refresh. Writes are never replayed
  /// because the server may already have applied them.
  Future<ChannelResourcesHttpResponse> request(
    String method,
    String path, {
    Map<String, String> queryParameters = const {},
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    var generation = _generation;
    generation = await _ensureAuthenticated(generation);
    final uri = _pathUri(path, queryParameters: queryParameters);
    final effectiveHeaders = <String, String>{
      'Accept': 'application/json',
      ...headers,
    };
    final bytes = _encodeBody(body, effectiveHeaders);
    var response = await _sendAuthorizedRaw(
      method,
      uri,
      generation: generation,
      headers: effectiveHeaders,
      body: bytes,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      final recovered = await _refresh(generation);
      if (recovered) {
        generation = _generation;
        if (_isSafeRead(method)) {
          response = await _sendAuthorizedRaw(
            method,
            uri,
            generation: generation,
            headers: effectiveHeaders,
            body: bytes,
          );
        } else {
          throw const ChannelResourcesSessionException(
            ChannelResourcesSessionErrorType.retryRequired,
            statusCode: HttpStatus.unauthorized,
          );
        }
      }
    }
    _checkFence(generation);
    if (response.statusCode == HttpStatus.unauthorized) {
      final errorType = _errorType;
      if (errorType == null ||
          _status == ChannelResourcesSessionStatus.signedOut) {
        await _expireIfCurrent(generation);
      }
      throw ChannelResourcesSessionException(
        errorType ?? ChannelResourcesSessionErrorType.expired,
        statusCode: HttpStatus.unauthorized,
      );
    }
    return response;
  }

  Future<void> changePassword({
    String? oldPassword,
    required String newPassword,
    String? newUsername,
  }) async {
    final body = <String, String>{'new_password': newPassword};
    if (oldPassword != null && oldPassword.isNotEmpty) {
      body['old_password'] = oldPassword;
    }
    if (newUsername != null && newUsername.trim().isNotEmpty) {
      body['new_username'] = newUsername.trim();
    }
    final response = await request('POST', 'auth/change-password', body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _statusException(response.statusCode);
    }
    await clear();
  }

  /// Revokes the current access session when possible, then always clears the
  /// local refresh cookie and in-memory token.
  Future<void> logout() async {
    final generation = _generation;
    if (_accessToken != null && _isGenerationCurrent(generation)) {
      try {
        await _sendAuthorizedRaw(
          'POST',
          _pathUri('auth/logout'),
          generation: generation,
        );
      } on Object {
        // Local sign-out must not be blocked by a network failure.
      }
    }
    await clear();
  }

  Future<void> clear() async {
    ++_generation;
    _accessToken = null;
    _refreshCookie = null;
    _user = null;
    _rememberSession = true;
    _status = ChannelResourcesSessionStatus.signedOut;
    _errorType = null;
    _emitState();
    try {
      await _storage.delete(key: _refreshStorageKey);
    } on Object {
      // A failed secure-storage cleanup is not exposed as credential data.
    }
  }

  Future<int> _ensureAuthenticated(int generation) async {
    _checkFence(generation);
    if (_accessToken != null &&
        _user != null &&
        _status == ChannelResourcesSessionStatus.authenticated) {
      return generation;
    }
    final state = await restore();
    generation = _generation;
    _checkFence(generation);
    if (!state.isAuthenticated) {
      throw ChannelResourcesSessionException(
        state.errorType ?? ChannelResourcesSessionErrorType.notAuthenticated,
      );
    }
    return generation;
  }

  Future<bool> _refresh(int generation) {
    final running = _refreshFlight;
    if (running != null) return running;
    final future = _refreshImpl(generation);
    _refreshFlight = future;
    future.whenComplete(() {
      if (identical(_refreshFlight, future)) _refreshFlight = null;
    });
    return future;
  }

  Future<bool> _refreshImpl(int generation) async {
    try {
      _checkFence(generation);
      _refreshCookie ??= await _storage.read(key: _refreshStorageKey);
      _checkFence(generation);
      final cookie = _refreshCookie;
      if (cookie == null || cookie.isEmpty) {
        _setSignedOut(generation);
        return false;
      }
      final response = await _sendRaw(
        'POST',
        _pathUri('auth/refresh'),
        headers: {'Cookie': 'refresh_token=$cookie'},
      );
      _checkFence(generation);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        await _expireIfCurrent(generation);
        return false;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _statusException(response.statusCode);
      }
      final payload = _jsonMap(response);
      final accessToken = _string(payload['access_token']);
      if (accessToken == null) {
        throw const ChannelResourcesSessionException(
          ChannelResourcesSessionErrorType.malformed,
        );
      }
      _accessToken = accessToken;
      _refreshCookie = _refreshCookieFrom(response.setCookieHeaders) ?? cookie;
      if (_rememberSession) {
        await _persistRefreshCookie(generation);
      }
      _checkFence(generation);
      final me = await _sendAuthorizedRaw(
        'GET',
        _pathUri('auth/me'),
        generation: generation,
      );
      if (me.statusCode == HttpStatus.unauthorized ||
          me.statusCode == HttpStatus.forbidden) {
        await _expireIfCurrent(generation);
        return false;
      }
      if (me.statusCode < 200 || me.statusCode >= 300) {
        throw _statusException(me.statusCode);
      }
      final user = _parseUser(
        _jsonMap(me),
        fallbackId: _user?.id ?? _tokenSubject(_accessToken),
      );
      if (user == null) {
        throw const ChannelResourcesSessionException(
          ChannelResourcesSessionErrorType.malformed,
        );
      }
      _checkFence(generation);
      _user = user;
      _status = ChannelResourcesSessionStatus.authenticated;
      _errorType = null;
      _emitState();
      return true;
    } on ChannelResourcesSessionException catch (error) {
      if (error.type == ChannelResourcesSessionErrorType.stale) rethrow;
      if (_isGenerationCurrent(generation)) {
        _status = ChannelResourcesSessionStatus.unavailable;
        _errorType = error.type;
        _emitState();
      }
      return false;
    } on Object {
      if (_isGenerationCurrent(generation)) {
        _status = ChannelResourcesSessionStatus.unavailable;
        _errorType = ChannelResourcesSessionErrorType.network;
        _emitState();
      }
      return false;
    }
  }

  Future<ChannelResourcesHttpResponse> _sendAuthorizedRaw(
    String method,
    Uri uri, {
    required int generation,
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    _checkFence(generation);
    final effectiveHeaders = <String, String>{
      'Accept': 'application/json',
      ...headers,
    };
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.notAuthenticated,
      );
    }
    effectiveHeaders['Authorization'] = 'Bearer $token';
    final response = await _sendRaw(
      method,
      uri,
      headers: effectiveHeaders,
      body: body,
    );
    _checkFence(generation);
    return response;
  }

  Future<ChannelResourcesHttpResponse> _sendRaw(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    try {
      return await _transport(
        method: method,
        uri: uri,
        headers: Map<String, String>.unmodifiable(headers),
        body: body,
      );
    } on ChannelResourcesSessionException {
      rethrow;
    } on Object {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.network,
      );
    }
  }

  void _checkFence(int generation) {
    if (!_isGenerationCurrent(generation)) {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.stale,
      );
    }
  }

  bool _isGenerationCurrent(int generation) => generation == _generation;

  void _setSignedOut(int generation) {
    _checkFence(generation);
    _accessToken = null;
    _user = null;
    _status = ChannelResourcesSessionStatus.signedOut;
    _errorType = null;
    _emitState();
  }

  void _setLoginFailure(int generation, ChannelResourcesSessionErrorType type) {
    if (!_isGenerationCurrent(generation)) return;
    _accessToken = null;
    _user = null;
    _status = ChannelResourcesSessionStatus.signedOut;
    _errorType = type;
    _emitState();
  }

  Future<void> _expireIfCurrent(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    _accessToken = null;
    _user = null;
    _refreshCookie = null;
    _status = ChannelResourcesSessionStatus.signedOut;
    _errorType = ChannelResourcesSessionErrorType.expired;
    _emitState();
    try {
      await _storage.delete(key: _refreshStorageKey);
    } on Object {
      // Do not expose storage details to the feature layer.
    }
  }

  Future<void> _persistRefreshCookie(int generation) async {
    _checkFence(generation);
    final cookie = _refreshCookie;
    if (cookie == null || cookie.isEmpty) {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.malformed,
      );
    }
    try {
      await _storage.write(key: _refreshStorageKey, value: cookie);
    } on Object {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.network,
      );
    }
  }

  Future<void> _deletePersistedRefreshCookie(int generation) async {
    _checkFence(generation);
    try {
      await _storage.delete(key: _refreshStorageKey);
    } on Object {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.network,
      );
    }
  }

  void _emitState() {
    _stateNotifier.value = ChannelResourcesAuthState(
      _status,
      user: _user,
      errorType: _errorType,
    );
  }

  Uri _pathUri(String path, {Map<String, String> queryParameters = const {}}) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    if (normalized.isEmpty ||
        normalized.contains('://') ||
        normalized.split('/').any((segment) => segment == '..')) {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.malformed,
      );
    }
    final uri = _baseUri.resolve(normalized);
    if (uri.host != _baseUri.host || uri.scheme != _baseUri.scheme) {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.malformed,
      );
    }
    if (queryParameters.isEmpty) return uri;
    return uri.replace(queryParameters: queryParameters);
  }

  static Uri _normalizeBaseUri(Uri value) {
    final path = value.path.endsWith('/') ? value.path : '${value.path}/';
    return value.replace(path: path, query: null, fragment: null);
  }

  static bool _isSafeRead(String method) {
    final normalized = method.toUpperCase();
    return normalized == 'GET' || normalized == 'HEAD';
  }

  static List<int>? _encodeBody(Object? body, Map<String, String> headers) {
    if (body == null) return null;
    if (body is List<int>) return body;
    if (body is String) return utf8.encode(body);
    headers['Content-Type'] = 'application/json';
    return utf8.encode(jsonEncode(body));
  }

  static Future<ChannelResourcesHttpResponse> _defaultTransport({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(_requestTimeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.add(body);
      final response = await request.close().timeout(_requestTimeout);
      final bytes = await response
          .fold<List<int>>(<int>[], (previous, chunk) {
            previous.addAll(chunk);
            return previous;
          })
          .timeout(_requestTimeout);
      return ChannelResourcesHttpResponse(
        response.statusCode,
        bytes,
        contentType: response.headers.contentType?.mimeType,
        setCookieHeaders: List<String>.unmodifiable(
          response.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _jsonMap(ChannelResourcesHttpResponse response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const ChannelResourcesSessionException(
        ChannelResourcesSessionErrorType.malformed,
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  static ChannelResourcesSessionException _statusException(int statusCode) {
    return ChannelResourcesSessionException(
      statusCode >= 500
          ? ChannelResourcesSessionErrorType.server
          : ChannelResourcesSessionErrorType.malformed,
      statusCode: statusCode,
    );
  }

  static String? _refreshCookieFrom(Iterable<String> headers) {
    for (final header in headers) {
      final match = RegExp(
        r'(?:^|;\s*)refresh_token=([^;]*)',
        caseSensitive: false,
      ).firstMatch(header);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static ChannelResourcesUser? _parseUser(
    Object? raw, {
    String? fallbackId,
    int? fallbackPoints,
  }) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = _string(map['id']) ?? fallbackId;
    if (id == null || id.isEmpty) return null;
    return ChannelResourcesUser(
      id: id,
      nickname: _string(map['nickname']) ?? id,
      points: _numberOrNull(map['points']) ?? fallbackPoints,
      loginType: _string(map['login_type']) ?? '',
      identityType: _string(map['identity_type']) ?? '',
      isDefaultPassword: _bool(map['is_default_password']),
      username: _string(map['username']),
    );
  }

  static String? _tokenSubject(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final subject = _string(payload['sub']);
      return subject == null || subject.isEmpty ? null : subject;
    } on Object {
      return null;
    }
  }

  static String? _string(Object? value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
  }

  static bool _bool(Object? value) =>
      value is bool
          ? value
          : value is String
          ? value.toLowerCase() == 'true' || value == '1'
          : value is num && value != 0;

  static int? _numberOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = _string(value);
    return text == null ? null : int.tryParse(text);
  }
}

/// Registry that keeps the channel session separate from the campus session.
class ChannelResourcesSessionService {
  static final ChannelResourcesSession _current = ChannelResourcesSession();

  static ChannelResourcesSession get current => _current;
}
