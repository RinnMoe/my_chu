import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/account.dart';
import 'campus_session_store.dart';
import 'scoped_cookie_jar.dart';
import 'service_endpoints.dart';

/// A long-lived HTTP session for one MyCHU account.
///
/// Apps share this session instead of creating a new [HttpClient] for each
/// request. Cookies remain isolated by account, domain and path while response
/// cookies are available to the next request immediately.
class AccountNetworkSessionService {
  static final Map<String, AccountNetworkSession> _sessions = {};

  static AccountNetworkSession forAccount(Account account) {
    final existing = _sessions[account.accountKey];
    if (existing != null) return existing;
    final session = AccountNetworkSession(account.accountKey);
    _sessions[account.accountKey] = session;
    return session;
  }

  /// Removes the persisted/session scope for one declared service without
  /// disturbing unrelated services in the same account session.
  static void clearServiceSession(String accountId, CampusServiceId serviceId) {
    final session = _sessions[accountId];
    if (session == null) return;
    if (serviceId == CampusServices.unifiedIdentity) {
      session.clearAt(CampusServiceEndpoints.idsAuthUri, '/');
      session.clearAt(CampusServiceEndpoints.identityRealmUri, '/');
      return;
    }
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (definition == null ||
        !definition.sessionMaterializer.containsCookieMaterializer) {
      return;
    }
    session.clearAt(definition.seedUri, definition.cookiePath);
  }

  /// Clears one path-scoped portal sub-application session.
  static void clearScoped(String accountId, Uri uri, String path) {
    _sessions[accountId]?.clearAt(uri, path);
  }

  static void discard(String accountId) {
    _sessions.remove(accountId)?.close();
  }

  static void discardAll() {
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
  }
}

class AccountNetworkSession {
  AccountNetworkSession(this.accountId)
    : _client = HttpClient()..connectionTimeout = _connectionTimeout;

  static const _connectionTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 12);

  final String accountId;
  final HttpClient _client;
  final ScopedCookieJar _cookies = ScopedCookieJar();
  final Map<String, Future<void>> _serialTails = {};
  Future<void>? _persistentLoad;
  var _closed = false;

  void seed(Uri uri, String cookieHeader) {
    if (cookieHeader.isNotEmpty) _cookies.seed(uri, cookieHeader);
  }

  /// Seeds cookies under an explicit path prefix (see [ScopedCookieJar.seedAt]).
  void seedScoped(Uri uri, String path, String cookieHeader) {
    if (cookieHeader.isNotEmpty) {
      _cookies.seedAt(uri.host, path, cookieHeader);
    }
  }

  void clearAt(Uri uri, String path) {
    _cookies.clearAt(uri.host, path);
  }

  Future<AccountNetworkResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
    ContentType? contentType,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    String? cookieHeader,
    String? serializationKey,
  }) => _send(
    method,
    uri,
    headers: headers,
    body: body,
    bodyBytes: bodyBytes,
    contentType: contentType,
    requestTimeout: requestTimeout,
    responseTimeout: responseTimeout,
    followRedirects: followRedirects,
    cookieHeader: cookieHeader,
    serializationKey: serializationKey,
  );

  /// Sends a request and streams the response into [destination].
  ///
  /// The destination is opened in write mode for every attempt, so a retry
  /// cannot append a second copy of a partial response. The response body is
  /// still consumed by this session, preserving the normal cookie and
  /// connection lifecycle.
  Future<AccountNetworkResponse> sendToFile(
    String method,
    Uri uri, {
    required File destination,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
    ContentType? contentType,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    String? cookieHeader,
    String? serializationKey,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) => _send(
    method,
    uri,
    headers: headers,
    body: body,
    bodyBytes: bodyBytes,
    contentType: contentType,
    requestTimeout: requestTimeout,
    responseTimeout: responseTimeout,
    followRedirects: followRedirects,
    cookieHeader: cookieHeader,
    serializationKey: serializationKey,
    destination: destination,
    onProgress: onProgress,
  );

  Future<AccountNetworkResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
    ContentType? contentType,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = false,
    String? cookieHeader,
    String? serializationKey,
    File? destination,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) {
    Future<AccountNetworkResponse> perform() async {
      if (_closed) {
        throw StateError('账号网络会话已经关闭');
      }
      await _loadPersistentSession();
      if (body != null && bodyBytes != null) {
        throw ArgumentError('body 与 bodyBytes 不能同时设置');
      }
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        seed(uri, cookieHeader);
      }

      final timeout = requestTimeout ?? _requestTimeout;
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = followRedirects;
      headers.forEach((name, value) {
        if (name.toLowerCase() != HttpHeaders.cookieHeader) {
          request.headers.set(name, value);
        }
      });
      final cookies = _cookies.headerFor(uri);
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      if (contentType != null) request.headers.contentType = contentType;
      if (body != null) {
        request.write(body);
      } else if (bodyBytes != null) {
        request.add(bodyBytes);
      }

      final response = await request.close().timeout(timeout);
      _cookies.collect(uri, response);
      final bytes = <int>[];
      final previewBytes = destination == null ? bytes : <int>[];
      IOSink? sink;
      var receivedBytes = 0;
      final totalBytes =
          response.contentLength >= 0 ? response.contentLength : null;
      try {
        if (destination != null) {
          sink = destination.openWrite(mode: FileMode.write);
          onProgress?.call(0, totalBytes);
        }
        await for (final chunk in response.timeout(
          responseTimeout ?? _requestTimeout,
        )) {
          if (sink == null) {
            bytes.addAll(chunk);
          } else {
            sink.add(chunk);
            if (previewBytes.length < _responsePreviewBytes) {
              final remaining = _responsePreviewBytes - previewBytes.length;
              previewBytes.addAll(
                chunk.length <= remaining ? chunk : chunk.take(remaining),
              );
            }
          }
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }
        if (sink != null) {
          await sink.flush();
          await sink.close();
          sink = null;
        }
      } catch (_) {
        await sink?.close();
        rethrow;
      }
      return AccountNetworkResponse(
        response.statusCode,
        destination == null ? bytes : previewBytes,
        contentLength: totalBytes,
        location: response.headers.value(HttpHeaders.locationHeader),
        setCookieHeaders: List<String>.unmodifiable(
          response.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
        ),
      );
    }

    if (serializationKey == null || serializationKey.isEmpty) {
      return perform();
    }
    return _runSerial(serializationKey, perform);
  }

  /// Restores the durable Session Store into this account-scoped transport
  /// just before its first request. This keeps cold-start requests usable;
  /// [CampusSession] remains the request policy and credential boundary.
  Future<void> _loadPersistentSession() {
    final pending = _persistentLoad;
    if (pending != null) return pending;
    final future = _loadPersistentSessionImpl();
    _persistentLoad = future;
    future.whenComplete(() {
      if (identical(_persistentLoad, future)) _persistentLoad = null;
    });
    return future;
  }

  Future<void> _loadPersistentSessionImpl() async {
    try {
      final store = await CampusSessionStore.open(accountKey: accountId);
      final identityHosts = <Uri>[
        CampusServiceEndpoints.idsAuthUri,
        CampusServiceEndpoints.identityRealmUri,
      ];
      for (final uri in identityHosts) {
        final header = await store.rootCookieHeader(uri: uri);
        if (header.isNotEmpty) seed(uri, header);
      }

      for (final definition in CampusServiceEndpoints.definitions) {
        if (definition.sessionMaterializer.containsWebViewSessionMaterializer) {
          continue;
        }
        final scope = definition.scopeFor(definition.seedUri);
        final header = await store
            .cookieJar(definition.id, scope: scope)
            .headerFor(definition.seedUri);
        if (header.isNotEmpty) seed(definition.seedUri, header);
      }

      // Portal sub-applications have exact path scopes. The known production
      // route is restored here; an exact route exchange can populate any
      // other path lazily through the persistent CampusSessionStore.
      const portalSubPath = '/qljfwapp/';
      final portalUri = Uri.parse(
        '${CampusServiceEndpoints.portalBase}$portalSubPath',
      );
      final portalSubHeader = await store
          .cookieJar(
            CampusServices.informationPortal,
            scope: const PathPrefixSessionScope(portalSubPath),
          )
          .headerFor(portalUri);
      if (portalSubHeader.isNotEmpty) {
        seedScoped(portalUri, portalSubPath, portalSubHeader);
      }
    } catch (_) {
      // Pure Dart callers (and tests) may run without a Flutter secure-storage
      // plugin. Response cookies are still retained in memory; the host Store
      // remains the durable source whenever it is available.
    }
  }

  /// Runs requests which mutate a server-side session one at a time, without
  /// blocking unrelated services in the same account session.
  Future<T> _runSerial<T>(String key, Future<T> Function() operation) async {
    final previous = _serialTails[key];
    final release = Completer<void>();
    _serialTails[key] = release.future;
    if (previous != null) await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_serialTails[key], release.future)) {
        _serialTails.remove(key);
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _serialTails.clear();
    _client.close(force: true);
  }
}

class AccountNetworkResponse {
  final int statusCode;
  final List<int> bytes;
  final int? contentLength;
  final String? location;
  final List<String> setCookieHeaders;

  const AccountNetworkResponse(
    this.statusCode,
    this.bytes, {
    this.contentLength,
    this.location,
    this.setCookieHeaders = const [],
  });

  String get body => utf8.decode(bytes, allowMalformed: true);
}

const _responsePreviewBytes = 64 * 1024;
