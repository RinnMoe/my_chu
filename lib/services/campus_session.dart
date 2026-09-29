import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'account_network_session_service.dart';
import 'auth_service.dart';
import 'campus_session_store.dart';
import 'campus_service_session_service.dart';
import 'logger_service.dart';
import 'service_endpoints.dart';
import 'session_runtime_fence.dart';

/// Raised when an async request completed after its account/session fence was
/// replaced. The response is deliberately not returned to feature code.
class StaleSessionResultException implements Exception {
  const StaleSessionResultException(this.serviceId);

  final CampusServiceId serviceId;

  @override
  String toString() =>
      'StaleSessionResultException(service: ${serviceId.value})';
}

/// Request-facing session facade and the only authenticated campus request
/// entry point. It owns the account/session fence, service credential
/// preparation, transport policy, retry and response-cookie coordination.
class CampusSession {
  CampusSession._(this._store);

  static final Map<String, Future<AccountNetworkResponse>> _inFlight = {};

  /// Creates a session bound to the current account.
  static Future<CampusSession> open({
    String? accountKey,
    FlutterSecureStorage? storage,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) throw StateError('请先登录后再创建校园会话');
    if (accountKey != null && account.accountKey != accountKey) {
      throw StateError('校园会话账号已切换');
    }
    final store = await CampusSessionStore.open(
      accountKey: account.accountKey,
      storage: storage,
    );
    return CampusSession._(store);
  }

  /// Test/core seam for a store that has already been opened by the host.
  factory CampusSession.fromStore(CampusSessionStore store) =>
      CampusSession._(store);

  final CampusSessionStore _store;

  String get accountKey => _store.accountKey;
  String get identityEpoch => _store.identityEpoch;

  /// Canonical stateless entry point used by feature code. The account-bound
  /// store is opened on the first request, so creating a client is cheap and
  /// does not start network work.
  static CampusSessionClient client(CampusServiceId serviceId) {
    _requireDefinition(serviceId);
    return CampusSessionClient._(serviceId);
  }

  SessionRuntimeFence captureFence(CampusServiceId serviceId, Uri uri) {
    final definition = _requireDefinition(serviceId);
    _validateUri(definition, uri);
    return _store.captureFence(
      serviceId: serviceId,
      scopeKey: definition.scopeFor(uri).keyFor(uri),
      sessionRevision: AuthService.sessionRevision,
    );
  }

  Future<AccountNetworkResponse> request(
    CampusServiceId serviceId,
    String method,
    String url, {
    Object? body,
    Map<String, String>? extraHeaders,
    ContentType? contentType,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    bool throwOnHttpError = true,
    bool autoExchangeService = true,
  }) => _request(
    serviceId,
    method,
    url,
    body: body,
    extraHeaders: extraHeaders,
    contentType: contentType,
    requestTimeout: requestTimeout,
    responseTimeout: responseTimeout,
    followRedirects: followRedirects,
    throwOnHttpError: throwOnHttpError,
    autoExchangeService: autoExchangeService,
  );

  /// Streams a campus response into [destination] through the same request
  /// pipeline used by ordinary requests.
  Future<AccountNetworkResponse> downloadToFile(
    CampusServiceId serviceId,
    String url, {
    required File destination,
    Map<String, String>? extraHeaders,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    bool autoExchangeService = true,
    void Function(int receivedBytes, int? totalBytes, int attempt)? onProgress,
  }) => _request(
    serviceId,
    'GET',
    url,
    extraHeaders: extraHeaders,
    requestTimeout: requestTimeout,
    responseTimeout: responseTimeout,
    followRedirects: followRedirects,
    throwOnHttpError: false,
    autoExchangeService: autoExchangeService,
    responseFile: destination,
    onDownloadProgress: onProgress,
  );

  Future<AccountNetworkResponse> _request(
    CampusServiceId serviceId,
    String method,
    String url, {
    Object? body,
    Map<String, String>? extraHeaders,
    ContentType? contentType,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    bool throwOnHttpError = true,
    bool autoExchangeService = true,
    File? responseFile,
    void Function(int receivedBytes, int? totalBytes, int attempt)?
    onDownloadProgress,
  }) async {
    final definition = _requireDefinition(serviceId);
    final uri = Uri.parse(url);
    _validateUri(definition, uri);
    var fence = captureFence(serviceId, uri);
    CampusServiceSession? serviceSession;
    try {
      serviceSession = await CampusSessionService.get(serviceId);
    } catch (error) {
      AppLogger.warn(
        '网络请求准备失败 ${_serviceLabel(serviceId)} (${error.runtimeType})',
      );
      rethrow;
    }
    final account = await AuthService.getCurrentAccount();
    if (account == null) throw StateError('请先登录后再调用应用接口');

    Future<AccountNetworkResponse> perform() async {
      final stopwatch = Stopwatch()..start();
      var attempt = 1;
      try {
        final postExchangeSettle =
            definition.transportPolicy.postExchangeSettle;
        if (postExchangeSettle > Duration.zero) {
          final exchangedAt = CampusSessionService.lastSuccessfulExchangeAt(
            account.accountKey,
            serviceId,
          );
          if (exchangedAt != null) {
            final remaining =
                postExchangeSettle - DateTime.now().difference(exchangedAt);
            if (remaining > Duration.zero) {
              AppLogger.info('教务换票后等待 ${remaining.inMilliseconds}ms 再发数据请求');
              await Future<void>.delayed(remaining);
            }
          }
        }

        final transport = AccountNetworkSessionService.forAccount(account);
        final effectiveHeaders = <String, String>{};
        void rebuildHeaders() {
          effectiveHeaders
            ..clear()
            ..addAll(extraHeaders ?? const {});
          final serviceHeaders = serviceSession?.headers;
          if (serviceHeaders != null) {
            for (final entry in serviceHeaders.entries) {
              effectiveHeaders[entry.key] = entry.value;
            }
          }
          for (final entry in definition.transportPolicy.headers.entries) {
            effectiveHeaders.putIfAbsent(entry.key, () => entry.value);
          }
          if (definition.transportPolicy.closeConnection) {
            effectiveHeaders.putIfAbsent('Connection', () => 'close');
          }
        }

        void seedServiceSession() {
          final cookieHeader = serviceSession?.cookieHeader;
          if (cookieHeader == null || cookieHeader.isEmpty) return;
          final scope = definition.scopeFor(uri);
          if (scope is PathPrefixSessionScope) {
            transport.seedScoped(uri, scope.prefix, cookieHeader);
          } else {
            transport.seed(definition.seedUri, cookieHeader);
          }
        }

        rebuildHeaders();
        final isJsonBody =
            body != null && body is! String && body is! List<int>;

        Future<AccountNetworkResponse> send() async {
          seedServiceSession();
          final progress =
              responseFile == null
                  ? null
                  : (int receivedBytes, int? totalBytes) {
                    onDownloadProgress?.call(
                      receivedBytes,
                      totalBytes,
                      attempt,
                    );
                  };
          final response =
              responseFile == null
                  ? await transport.send(
                    method,
                    uri,
                    headers: effectiveHeaders,
                    body:
                        body is String
                            ? body
                            : isJsonBody
                            ? jsonEncode(body)
                            : null,
                    bodyBytes: body is List<int> ? body : null,
                    contentType:
                        contentType ?? (isJsonBody ? ContentType.json : null),
                    requestTimeout: requestTimeout,
                    responseTimeout: responseTimeout,
                    followRedirects: followRedirects,
                    serializationKey:
                        definition.transportPolicy.serializationKey,
                  )
                  : await transport.sendToFile(
                    method,
                    uri,
                    destination: responseFile,
                    headers: effectiveHeaders,
                    body:
                        body is String
                            ? body
                            : isJsonBody
                            ? jsonEncode(body)
                            : null,
                    bodyBytes: body is List<int> ? body : null,
                    contentType:
                        contentType ?? (isJsonBody ? ContentType.json : null),
                    requestTimeout: requestTimeout,
                    responseTimeout: responseTimeout,
                    followRedirects: followRedirects,
                    serializationKey:
                        definition.transportPolicy.serializationKey,
                    onProgress: progress,
                  );
          await _commitResponseCookies(fence, definition, uri, response);
          return response;
        }

        Future<AccountNetworkResponse> sendWithTransientRetry() async {
          try {
            var response = await send();
            if (_canRetryTransientFailure(method, response.statusCode)) {
              attempt++;
              AppLogger.warn(
                '网络请求暂时失败 ${_serviceLabel(serviceId)} '
                '→ ${response.statusCode}，准备重试',
              );
              await Future<void>.delayed(const Duration(milliseconds: 250));
              response = await send();
            }
            return response;
          } on SocketException {
            if (!_canRetryTransientFailure(method, null)) rethrow;
            attempt++;
            AppLogger.warn('网络请求连接异常 ${_serviceLabel(serviceId)}，准备重试');
            await Future<void>.delayed(const Duration(milliseconds: 250));
            return send();
          } on TimeoutException {
            if (!_canRetryTransientFailure(method, null)) rethrow;
            attempt++;
            AppLogger.warn('网络请求连接超时 ${_serviceLabel(serviceId)}，准备重试');
            await Future<void>.delayed(const Duration(milliseconds: 250));
            return send();
          } on HttpException {
            if (!_canRetryTransientFailure(method, null)) rethrow;
            attempt++;
            AppLogger.warn('网络请求响应中断 ${_serviceLabel(serviceId)}，准备重试');
            await Future<void>.delayed(const Duration(milliseconds: 250));
            return send();
          }
        }

        var response = await sendWithTransientRetry();
        if (autoExchangeService &&
            _canReplayAfterAuthFailure(method, uri, definition) &&
            _isChdService(uri) &&
            _requiresSessionRefresh(response, serviceId, uri)) {
          attempt++;
          if (!_runtimeFenceIsCurrent(fence)) {
            throw StaleSessionResultException(serviceId);
          }
          final credential = await _recoverServiceSession(
            uri,
            serviceId: serviceId,
          );
          if (credential != null) {
            serviceSession = credential;
            rebuildHeaders();
            fence = captureFence(serviceId, uri);
            response = await sendWithTransientRetry();
          }
        }
        AppLogger.info(
          '网络请求 ${_serviceLabel(serviceId)} '
          '→ ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms, 尝试 $attempt 次)',
        );
        if (throwOnHttpError && response.statusCode != HttpStatus.ok) {
          AppLogger.warn(
            '$method ${_serviceLabel(serviceId)} 失败: ${response.statusCode}',
          );
          throw HttpException(
            'Request failed: ${response.statusCode}',
            uri: uri,
          );
        }
        return response;
      } catch (error) {
        AppLogger.warn(
          '网络请求失败 ${_serviceLabel(serviceId)} '
          '(${stopwatch.elapsedMilliseconds}ms, 尝试 $attempt 次, ${error.runtimeType})',
        );
        rethrow;
      }
    }

    if (responseFile == null && _canSingleFlight(method)) {
      final key = _inFlightKey(
        account.accountKey,
        method,
        uri,
        extraHeaders,
        followRedirects,
        autoExchangeService,
        throwOnHttpError,
        requestTimeout,
        responseTimeout,
        fence.fingerprint,
      );
      final pending = _inFlight[key];
      if (pending != null) {
        AppLogger.info('网络请求单飞复用 ${_serviceLabel(serviceId)}');
        final response = await pending;
        await _assertCurrent(fence);
        return response;
      }
      final future = perform();
      _inFlight[key] = future;
      try {
        final response = await future;
        await _assertCurrent(fence);
        return response;
      } finally {
        if (identical(_inFlight[key], future)) _inFlight.remove(key);
      }
    }
    final response = await perform();
    await _assertCurrent(fence);
    return response;
  }

  Future<Map<String, dynamic>> get(
    CampusServiceId serviceId,
    String url, {
    Map<String, String>? extraHeaders,
  }) async {
    final response = await request(
      serviceId,
      'GET',
      url,
      extraHeaders: extraHeaders,
    );
    return _decodeJsonMap(response);
  }

  Future<Map<String, dynamic>> post(
    CampusServiceId serviceId,
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final response = await request(
      serviceId,
      'POST',
      url,
      body: body,
      extraHeaders: extraHeaders,
    );
    return _decodeJsonMap(response);
  }

  Future<void> invalidateService(CampusServiceId serviceId, {Uri? uri}) async {
    final definition = _requireDefinition(serviceId);
    if (uri != null) _validateUri(definition, uri);
    await CampusSessionService.invalidate(
      serviceId,
      accountKey: accountKey,
      serviceUri: uri,
      reason: SessionInvalidationReason.explicitRefresh,
    );
  }

  static bool _canSingleFlight(String method) => method.toUpperCase() == 'GET';

  static String _inFlightKey(
    String accountKey,
    String method,
    Uri uri,
    Map<String, String>? extraHeaders,
    bool followRedirects,
    bool autoExchangeService,
    bool throwOnHttpError,
    Duration? requestTimeout,
    Duration? responseTimeout,
    String requestScopeKey,
  ) {
    final headerEntries =
        (extraHeaders ?? const {}).entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final headerFingerprint = headerEntries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    return [
      accountKey,
      method,
      uri.toString(),
      headerFingerprint,
      followRedirects,
      autoExchangeService,
      throwOnHttpError,
      requestTimeout,
      responseTimeout,
      requestScopeKey,
    ].join('|');
  }

  static Future<CampusServiceSession?> _recoverServiceSession(
    Uri uri, {
    required CampusServiceId serviceId,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) return null;
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (!(definition?.rootIdentity ?? false)) {
      await CampusSessionService.invalidate(
        serviceId,
        accountKey: account.accountKey,
        serviceUri: uri,
        reason: SessionInvalidationReason.authFailure,
      );
    }
    if (definition?.usesExactExchangeFor(uri) ?? false) {
      final serviceSession = await CampusSessionService.exchangeServiceSession(
        uri,
        label: _serviceLabel(serviceId),
      );
      if (serviceSession != null) return serviceSession;
    }
    return CampusSessionService.get(serviceId, forceRefresh: true);
  }

  static bool _canRetryTransientFailure(String method, int? statusCode) {
    if (!_canReplayAfterAuthFailure(method)) return false;
    return statusCode == null || statusCode >= HttpStatus.internalServerError;
  }

  static bool _canReplayAfterAuthFailure(
    String method, [
    Uri? uri,
    CampusServiceDefinition? definition,
  ]) {
    final normalized = method.toUpperCase();
    if (normalized == 'GET' || normalized == 'HEAD') return true;
    if (normalized != 'POST' || uri == null || definition == null) {
      return false;
    }
    return definition.transportPolicy.replaySafePostPaths.contains(uri.path);
  }

  static bool _requiresSessionRefresh(
    AccountNetworkResponse response,
    CampusServiceId serviceId,
    Uri requestUri,
  ) {
    final location = response.location;
    final resolvedLocation =
        location == null || location.isEmpty
            ? null
            : requestUri.resolve(location);
    return AuthFailureClassifier.matches(
      policy: CampusServiceEndpoints.authFailurePolicyFor(serviceId),
      statusCode: response.statusCode,
      location: resolvedLocation,
      body: response.body,
    );
  }

  static bool _isChdService(Uri uri) =>
      CampusServiceEndpoints.isChdHost(uri.host);

  static String _serviceLabel(CampusServiceId serviceId) =>
      CampusServiceEndpoints.labelFor(serviceId);

  Future<void> _assertCurrent(SessionRuntimeFence fence) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) throw StaleSessionResultException(fence.serviceId);
    if (!fence.isCurrent(
      currentAccountKey: account.accountKey,
      currentSessionRevision: AuthService.sessionRevision,
    )) {
      throw StaleSessionResultException(fence.serviceId);
    }
  }

  Future<void> _commitResponseCookies(
    SessionRuntimeFence fence,
    CampusServiceDefinition definition,
    Uri uri,
    AccountNetworkResponse response,
  ) async {
    final values = response.setCookieHeaders;
    if (values.isEmpty ||
        definition.sessionMaterializer.containsWebViewSessionMaterializer) {
      return;
    }

    final jar =
        definition.rootIdentity
            ? _store.rootCookieJar
            : _store.cookieJar(definition.id, scope: definition.scopeFor(uri));
    final committed = await jar.collectSetCookieHeadersIfCurrent(
      uri,
      values,
      isCurrent: () => _runtimeFenceIsCurrent(fence),
      verifyIdentityEpoch: true,
    );
    if (!committed) throw StaleSessionResultException(fence.serviceId);
  }

  bool _runtimeFenceIsCurrent(SessionRuntimeFence fence) => fence.isCurrent(
    currentAccountKey: accountKey,
    currentSessionRevision: AuthService.sessionRevision,
  );

  static CampusServiceDefinition _requireDefinition(CampusServiceId id) {
    final definition = CampusServiceEndpoints.definitionForId(id);
    if (definition == null) {
      throw ArgumentError.value(id, 'serviceId', '未注册校园服务');
    }
    return definition;
  }

  static void _validateUri(CampusServiceDefinition definition, Uri uri) {
    if (!definition.allowsUri(uri)) {
      throw ArgumentError.value(
        uri,
        'url',
        '不属于 ${definition.id.value} 声明的 host/path',
      );
    }
    final scopeKey = definition.sessionScope.keyFor(uri);
    if (scopeKey.startsWith('path-mismatch:') ||
        scopeKey.startsWith('uri-mismatch:')) {
      throw ArgumentError.value(uri, 'url', '不属于声明的 SessionScope');
    }
  }

  static Map<String, dynamic> _decodeJsonMap(AccountNetworkResponse response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('接口未返回 JSON 对象');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

/// Typed client bound to one declared service. It never exposes cookies,
/// tokens, or the legacy credential model to callers.
class CampusSessionClient {
  CampusSessionClient._(this.serviceId);

  final CampusServiceId serviceId;

  Future<AccountNetworkResponse> request(
    String method,
    String url, {
    Object? body,
    Map<String, String>? extraHeaders,
    ContentType? contentType,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    bool throwOnHttpError = true,
    bool autoExchangeService = true,
  }) async {
    final session = await CampusSession.open();
    return session.request(
      serviceId,
      method,
      url,
      body: body,
      extraHeaders: extraHeaders,
      contentType: contentType,
      requestTimeout: requestTimeout,
      responseTimeout: responseTimeout,
      followRedirects: followRedirects,
      throwOnHttpError: throwOnHttpError,
      autoExchangeService: autoExchangeService,
    );
  }

  /// Rebuilds this declared service session without exposing its projection.
  Future<bool> refresh() async =>
      await CampusSessionService.get(serviceId, forceRefresh: true) != null;

  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? extraHeaders,
  }) async {
    final response = await request('GET', url, extraHeaders: extraHeaders);
    return CampusSession._decodeJsonMap(response);
  }

  Future<Map<String, dynamic>> post(
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final response = await request(
      'POST',
      url,
      body: body,
      extraHeaders: extraHeaders,
    );
    return CampusSession._decodeJsonMap(response);
  }

  Future<AccountNetworkResponse> downloadToFile(
    String url, {
    required File destination,
    Map<String, String>? extraHeaders,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    bool autoExchangeService = true,
    void Function(int receivedBytes, int? totalBytes, int attempt)? onProgress,
  }) async {
    final session = await CampusSession.open();
    return session.downloadToFile(
      serviceId,
      url,
      destination: destination,
      extraHeaders: extraHeaders,
      requestTimeout: requestTimeout,
      responseTimeout: responseTimeout,
      followRedirects: followRedirects,
      autoExchangeService: autoExchangeService,
      onProgress: onProgress,
    );
  }
}
