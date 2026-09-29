import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/logger_service.dart';
import 'campus_webview_cookie_bridge.dart';
import 'web_view_cookie_coordinator.dart';
import 'web_view_session_binding.dart';

typedef ShuweiBindingRefresher =
    Future<WebViewSessionBinding> Function(WebViewSessionBinding staleBinding);

enum ShuweiRequestProxyFailureStage { cookieCommit }

typedef ShuweiRequestProxyFailureHandler =
    void Function(ShuweiRequestProxyFailureStage stage);

/// 树维（教务）请求代理：与 WakeUp APK 的兼容逻辑一致。
///
/// 仅接管树维域名的**主框架 GET 导航**，改用 Dio 发起并把响应交给 WebView，
/// 同时把 WebView Cookie 作为请求 Cookie、把响应 Set-Cookie 写回 WebView，
/// 实现 Cookie 双向同步。静态资源（css/js/图片）与 AJAX、POST 等请求全部
/// 交给原生 WebView，避免脚本化并发请求触发“不要过快点击”风控。
/// 主框架导航之间加入最小间隔节流；首次请求失败或响应命中服务端限流文案
/// 时等待后重试一次，效果等价于用户手动刷新。
class ShuweiRequestProxy {
  ShuweiRequestProxy({
    Dio? dio,
    ShuweiBindingRefresher? refreshBinding,
    ShuweiRequestProxyFailureHandler? onFailure,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               responseType: ResponseType.bytes,
               followRedirects: true,
               maxRedirects: 10,
               validateStatus: (_) => true,
             ),
           ),
       _refreshBinding = refreshBinding,
       _onFailure = onFailure;

  final Dio _dio;
  final ShuweiBindingRefresher? _refreshBinding;
  final ShuweiRequestProxyFailureHandler? _onFailure;
  WebViewSessionBinding? _binding;
  Future<WebViewSessionBinding?>? _bindingRefresh;
  static const _minNavigationInterval = Duration(milliseconds: 600);
  DateTime? _lastNavigationAt;

  void bindSession(WebViewSessionBinding binding) => _binding = binding;

  bool _isShuweiHost(String host) {
    final value = host.toLowerCase();
    return value == 'bkjw.chd.edu.cn' || value.endsWith('.chd.edu.cn');
  }

  Future<WebResourceResponse?> intercept(WebResourceRequest request) async {
    final url = request.url;
    final uri = Uri.tryParse(url.toString());
    if (uri == null) return null;

    // 与 WakeUp 的做法一致：只处理教务系统。
    if (!_isShuweiHost(uri.host)) return null;

    // shouldInterceptRequest 无法取得 POST 请求体，因此只代理 GET。
    if ((request.method ?? 'GET').toUpperCase() != 'GET') return null;

    // 只代理主框架导航：静态资源与 AJAX 由原生 WebView 加载，既降低并发
    // 洪峰（避免风控），也保证页面脚本（如 jQuery）能正常加载。
    if (request.isForMainFrame != true) return null;

    // A proxy request must be bound to the same fenced session that seeded the
    // WebView. If seeding failed, let the native WebView handle the navigation
    // instead of creating an unbound CookieManager writer.
    final binding = _binding;
    if (binding == null) return null;

    // 主框架导航之间节流，避免页面连续跳转时触发“不要过快点击”风控。
    final now = DateTime.now();
    final last = _lastNavigationAt;
    if (last != null) {
      final wait = _minNavigationInterval - now.difference(last);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastNavigationAt = DateTime.now();

    final headers = <String, dynamic>{...?request.headers};

    // 这些请求头由 Dio 自己生成，不能直接复制 WebView 的值。
    headers.removeWhere((name, _) {
      final key = name.toLowerCase();
      return key == 'host' ||
          key == 'connection' ||
          key == 'content-length' ||
          key == 'accept-encoding';
    });

    // 与共享网络层一致：EAMS 服务端会中止 keep-alive 响应，必须请求端
    // 关闭连接，否则首次请求总是以“连接被中断”失败并落入原生兜底加载。
    headers.putIfAbsent('Connection', () => 'close');

    try {
      var result = await _fetchWithBindingRecovery(
        uri,
        request,
        headers,
        binding,
      );
      if (result.stale) return result.response;
      if (result.response == null) {
        // 首次请求偶发中断：稍候重试一次，仍失败才交给原生 WebView。
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        result = await _fetchWithBindingRecovery(
          uri,
          request,
          headers,
          _binding ?? binding,
        );
        if (result.stale) return result.response;
        if (result.response == null) return null;
      }
      if (result.riskGuard) {
        // 服务端限流页（“不要频繁点击”等）：等待限流窗口过后重试一次，
        // 效果等价于用户手动刷新，避免首屏直接展示风控提示。
        await Future<void>.delayed(const Duration(seconds: 2));
        result = await _fetchWithBindingRecovery(
          uri,
          request,
          headers,
          _binding ?? binding,
        );
        if (result.stale) return result.response;
      }
      return result.response;
    } on WebViewCookieReadException {
      // Cookie 读取失败时不发送一个未认证的 Dio 请求；返回 null 让原生
      // WebView 接管，避免把“读取失败”误判成合法的空 Cookie。
      return null;
    }
  }

  Future<({WebResourceResponse? response, bool riskGuard, bool stale})>
  _fetchWithBindingRecovery(
    Uri uri,
    WebResourceRequest request,
    Map<String, dynamic> headers,
    WebViewSessionBinding initialBinding,
  ) async {
    var binding = initialBinding;
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await _fetchMainFrame(uri, request, headers, binding);
      if (!result.stale || attempt == 1) return result;
      final refreshed = await _refreshStaleBinding(binding);
      if (refreshed == null) return result;
      binding = refreshed;
      headers.removeWhere((name, _) => name.toLowerCase() == 'cookie');
    }
    return (response: _staleResponse(), riskGuard: false, stale: true);
  }

  Future<WebViewSessionBinding?> _refreshStaleBinding(
    WebViewSessionBinding staleBinding,
  ) async {
    final current = _binding;
    if (current != null && !identical(current, staleBinding)) return current;
    final refresher = _refreshBinding;
    if (refresher == null) return null;
    final pending = _bindingRefresh;
    if (pending != null) return pending;
    late final Future<WebViewSessionBinding?> future;
    future =
        (() async {
          try {
            final refreshed = await refresher(staleBinding);
            if (identical(_binding, staleBinding)) _binding = refreshed;
            return _binding;
          } catch (error) {
            AppLogger.warn('教务 WebView 会话刷新失败 (${error.runtimeType})');
            return null;
          } finally {
            if (identical(_bindingRefresh, future)) _bindingRefresh = null;
          }
        })();
    _bindingRefresh = future;
    return future;
  }

  Future<({WebResourceResponse? response, bool riskGuard, bool stale})>
  _fetchMainFrame(
    Uri uri,
    WebResourceRequest request,
    Map<String, dynamic> headers,
    WebViewSessionBinding? binding,
  ) async {
    String cookieHeader;
    try {
      cookieHeader = await _readCookieHeader(request.url, binding);
    } on _ShuweiSessionStaleException {
      return (response: _staleResponse(), riskGuard: false, stale: true);
    }
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    } else {
      headers.removeWhere((name, _) => name.toLowerCase() == 'cookie');
    }
    try {
      final response = await _dio.get<List<int>>(
        uri.toString(),
        options: Options(headers: headers),
      );

      try {
        await _writeResponseCookies(request.url, response.headers, binding);
      } on _ShuweiSessionStaleException {
        return (response: _staleResponse(), riskGuard: false, stale: true);
      } on _ShuweiCookieCommitException {
        _onFailure?.call(ShuweiRequestProxyFailureStage.cookieCommit);
        if (_onFailure != null) {
          return (
            response: _cookieCommitFailureResponse(),
            riskGuard: false,
            stale: false,
          );
        }
        rethrow;
      }
      if (binding != null &&
          !await CampusWebViewCookieBridge.isBindingCurrent(binding)) {
        return (response: _staleResponse(), riskGuard: false, stale: true);
      }

      final contentType = _readContentType(
        response.headers.value(Headers.contentTypeHeader),
        uri.path,
      );
      final riskGuard = _isRiskGuardPage(response.data, contentType.mimeType);

      final responseHeaders = <String, String>{};
      response.headers.map.forEach((name, values) {
        final key = name.toLowerCase();

        // Dio 已经处理了解压和传输编码。
        if (key == 'content-encoding' ||
            key == 'content-length' ||
            key == 'transfer-encoding' ||
            key == 'set-cookie') {
          return;
        }

        responseHeaders[name] = values.join(', ');
      });

      final statusCode = response.statusCode ?? 200;

      return (
        response: WebResourceResponse(
          data: Uint8List.fromList(response.data ?? const []),
          contentType: contentType.mimeType,
          contentEncoding: contentType.charset,
          statusCode: statusCode,
          reasonPhrase:
              (response.statusMessage?.isNotEmpty ?? false)
                  ? response.statusMessage!
                  : _reasonPhrase(statusCode),
          headers: responseHeaders,
        ),
        riskGuard: riskGuard,
        stale: false,
      );
    } catch (error) {
      AppLogger.warn('教务 WebView 主文档代理失败 (${error.runtimeType})');
      return (response: null, riskGuard: false, stale: false);
    }
  }

  bool _isRiskGuardPage(List<int>? data, String? mimeType) {
    if (data == null || data.isEmpty) return false;
    if (mimeType != null &&
        !mimeType.contains('text/html') &&
        !mimeType.contains('text/plain')) {
      return false;
    }
    final text = utf8.decode(data.take(4096).toList(), allowMalformed: true);
    final markers =
        const ['过快', '频繁', '操作过于', '访问过于'].where(text.contains).toList();
    if (markers.isEmpty) return false;
    return true;
  }

  Future<String> _readCookieHeader(
    WebUri url,
    WebViewSessionBinding? binding,
  ) async {
    return WebViewCookieCoordinator.transaction((context) async {
      if (binding != null &&
          !await CampusWebViewCookieBridge.isBindingCurrent(binding)) {
        throw const _ShuweiSessionStaleException();
      }
      final value = await context.readCookieHeader(Uri.parse(url.toString()));
      if (binding != null &&
          !await CampusWebViewCookieBridge.isBindingCurrent(binding)) {
        throw const _ShuweiSessionStaleException();
      }
      return value ?? '';
    });
  }

  Future<void> _writeResponseCookies(
    WebUri requestUrl,
    Headers headers,
    WebViewSessionBinding? binding,
  ) async {
    final setCookies = headers['set-cookie'];
    if (setCookies == null) return;
    await WebViewCookieCoordinator.transaction((context) async {
      final url = Uri.parse(requestUrl.toString());
      final written = <_ShuweiCookieMutation>[];
      try {
        if (binding != null &&
            !await CampusWebViewCookieBridge.isBindingCurrent(binding)) {
          throw const _ShuweiSessionStaleException();
        }
        for (final rawCookie in setCookies) {
          final directive = _parseSetCookie(url, rawCookie);
          if (directive == null) continue;
          await _removeLegacyRootSession(
            context,
            url,
            directive.cookie,
            written,
          );
          final previous = await context.readCookie(
            _cookieLookupUri(url, directive.cookie.path),
            directive.cookie.name,
          );
          if (directive.remove) {
            final committed = await context.deleteCookie(url, directive.cookie);
            if (committed && previous != null) {
              written.add(
                _ShuweiCookieMutation(
                  url: url,
                  cookie: directive.cookie,
                  previous: previous,
                ),
              );
            }
            continue;
          }
          await _setCookieWithReadbackRetry(context, url, directive.cookie);
          written.add(
            _ShuweiCookieMutation(
              url: url,
              cookie: directive.cookie,
              previous: previous,
            ),
          );
        }
        if (binding != null &&
            !await CampusWebViewCookieBridge.isBindingCurrent(binding)) {
          throw const _ShuweiSessionStaleException();
        }
      } catch (_) {
        for (final mutation in written.reversed) {
          try {
            if (mutation.previous == null) {
              await context.deleteCookie(mutation.url, mutation.cookie);
            } else {
              await context.setCookie(mutation.url, mutation.previous!);
            }
          } catch (_) {}
        }
        rethrow;
      }
    });
  }

  Future<void> _setCookieWithReadbackRetry(
    WebViewCookieTransactionContext context,
    Uri url,
    WebViewCookieValue cookie,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final committed = await context.setCookie(url, cookie);
        if (committed) return;
        final confirmed = await context.readCookie(
          _cookieLookupUri(url, cookie.path),
          cookie.name,
        );
        if (confirmed?.value == cookie.value) return;
      } on StateError catch (error) {
        if (attempt == 1) {
          _debugStage(
            'webview.proxy.cookie_commit_failed',
            '教务 WebView Cookie 提交失败',
            error: error,
            level: 'WARN',
          );
          throw const _ShuweiCookieCommitException();
        }
        _debugStage(
          'webview.proxy.cookie_commit_retry',
          '教务 WebView Cookie 提交重试',
          error: error,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (attempt == 0) {
        _debugStage(
          'webview.proxy.cookie_commit_retry',
          '教务 WebView Cookie 提交重试',
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      _debugStage(
        'webview.proxy.cookie_commit_failed',
        '教务 WebView Cookie 提交失败',
        level: 'WARN',
      );
      throw const _ShuweiCookieCommitException();
    }
    throw const _ShuweiCookieCommitException();
  }

  void _debugStage(
    String code,
    String message, {
    Object? error,
    String level = 'INFO',
  }) {
    if (!kDebugMode) return;
    AppLogger.event(
      level: level,
      code: code,
      message: message,
      domain: 'academic',
      exceptionType: error?.runtimeType.toString(),
    );
  }

  Future<void> _removeLegacyRootSession(
    WebViewCookieTransactionContext context,
    Uri requestUri,
    WebViewCookieValue cookie,
    List<_ShuweiCookieMutation> written,
  ) async {
    if (requestUri.host.toLowerCase() != 'bkjw.chd.edu.cn' ||
        cookie.name.toUpperCase() != 'JSESSIONID' ||
        cookie.path == '/') {
      return;
    }
    final rootUri = requestUri.replace(path: '/', query: null);
    final previous = await context.readCookie(rootUri, cookie.name);
    if (previous == null || previous.path != '/') return;
    final removed = await context.deleteCookie(rootUri, previous);
    if (!removed) return;
    written.add(
      _ShuweiCookieMutation(url: rootUri, cookie: previous, previous: previous),
    );
  }

  _ShuweiCookieDirective? _parseSetCookie(Uri requestUri, String raw) {
    final parts = raw.split(';');
    if (parts.isEmpty) return null;
    final pair = parts.first.trim();
    final separator = pair.indexOf('=');
    if (separator <= 0) return null;
    final name = pair.substring(0, separator).trim();
    final value = pair.substring(separator + 1).trim();
    if (name.isEmpty) return null;

    var domain = requestUri.host.toLowerCase();
    var hostOnly = true;
    var path = _defaultCookiePath(requestUri);
    DateTime? expires;
    int? maxAge;
    var secure = false;
    var httpOnly = false;
    String? sameSite;
    var invalidDomain = false;
    for (final rawAttribute in parts.skip(1)) {
      final attribute = rawAttribute.trim();
      if (attribute.isEmpty) continue;
      final attributeSeparator = attribute.indexOf('=');
      final key =
          (attributeSeparator < 0
                  ? attribute
                  : attribute.substring(0, attributeSeparator))
              .trim()
              .toLowerCase();
      final attributeValue =
          attributeSeparator < 0
              ? ''
              : attribute.substring(attributeSeparator + 1).trim();
      switch (key) {
        case 'domain':
          if (attributeValue.isEmpty) {
            invalidDomain = true;
            continue;
          }
          domain =
              attributeValue.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
          hostOnly = false;
          if (!_domainMatches(requestUri.host, domain)) invalidDomain = true;
        case 'path':
          if (attributeValue.startsWith('/')) path = attributeValue;
        case 'expires':
          try {
            expires = HttpDate.parse(attributeValue).toUtc();
          } catch (_) {
            expires = DateTime.tryParse(attributeValue)?.toUtc();
          }
        case 'max-age':
          maxAge = int.tryParse(attributeValue);
        case 'secure':
          secure = true;
        case 'httponly':
          httpOnly = true;
        case 'samesite':
          sameSite = attributeValue.toLowerCase();
      }
    }
    if (invalidDomain) return null;
    final now = DateTime.now().toUtc();
    if (maxAge != null && maxAge > 0) {
      expires = now.add(Duration(seconds: maxAge));
    }
    final remove =
        maxAge != null && maxAge <= 0 ||
        maxAge == null && expires != null && !expires.isAfter(now);
    return _ShuweiCookieDirective(
      cookie: WebViewCookieValue(
        name: name,
        value: value,
        domain: domain,
        hostOnly: hostOnly,
        path: path,
        expires: expires,
        secure: secure,
        httpOnly: httpOnly,
        sameSite: sameSite,
      ),
      remove: remove,
    );
  }

  bool _domainMatches(String host, String domain) {
    final normalizedHost = host.toLowerCase();
    final normalizedDomain = domain.toLowerCase();
    return normalizedHost == normalizedDomain ||
        normalizedHost.endsWith('.$normalizedDomain');
  }

  String _defaultCookiePath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || path == '/' || !path.contains('/')) return '/';
    final lastSlash = path.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : path.substring(0, lastSlash);
  }

  Uri _cookieLookupUri(Uri requestUri, String path) => requestUri.replace(
    path: path.endsWith('/') ? path : '$path/',
    query: null,
  );

  _ContentTypeInfo _readContentType(String? header, String path) {
    if (header != null && header.isNotEmpty) {
      final parts = header.split(';');
      final mimeType = parts.first.trim();
      var charset = 'UTF-8';

      for (final part in parts.skip(1)) {
        final item = part.trim();
        if (item.toLowerCase().startsWith('charset=')) {
          charset = item.substring('charset='.length).trim();
        }
      }

      return _ContentTypeInfo(mimeType: mimeType, charset: charset);
    }

    return _ContentTypeInfo(mimeType: _guessMimeType(path), charset: 'UTF-8');
  }

  String _guessMimeType(String path) {
    final value = path.toLowerCase();

    if (value.endsWith('.css')) return 'text/css';
    if (value.endsWith('.js')) return 'application/javascript';
    if (value.endsWith('.json')) return 'application/json';
    if (value.endsWith('.png')) return 'image/png';
    if (value.endsWith('.jpg') || value.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (value.endsWith('.gif')) return 'image/gif';
    if (value.endsWith('.svg')) return 'image/svg+xml';
    if (value.endsWith('.woff')) return 'font/woff';
    if (value.endsWith('.woff2')) return 'font/woff2';

    // 树维的 .action 响应主要是 HTML。
    return 'text/html';
  }

  String _reasonPhrase(int code) {
    switch (code) {
      case 200:
        return 'OK';
      case 204:
        return 'No Content';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 409:
        return 'Session Stale';
      case 500:
        return 'Internal Server Error';
      default:
        return 'Response';
    }
  }

  void dispose() {
    _dio.close(force: true);
  }

  WebResourceResponse _staleResponse() => WebResourceResponse(
    data: Uint8List(0),
    contentType: 'text/plain',
    contentEncoding: 'UTF-8',
    statusCode: 409,
    reasonPhrase: 'Session Stale',
    headers: const {'Cache-Control': 'no-store'},
  );

  WebResourceResponse _cookieCommitFailureResponse() => WebResourceResponse(
    data: Uint8List(0),
    contentType: 'text/plain',
    contentEncoding: 'UTF-8',
    statusCode: 503,
    reasonPhrase: 'Cookie Commit Failure',
    headers: const {'Cache-Control': 'no-store'},
  );
}

class _ShuweiSessionStaleException implements Exception {
  const _ShuweiSessionStaleException();
}

class _ShuweiCookieCommitException implements Exception {
  const _ShuweiCookieCommitException();
}

class _ShuweiCookieMutation {
  const _ShuweiCookieMutation({
    required this.url,
    required this.cookie,
    required this.previous,
  });

  final Uri url;
  final WebViewCookieValue cookie;
  final WebViewCookieValue? previous;
}

class _ShuweiCookieDirective {
  const _ShuweiCookieDirective({required this.cookie, required this.remove});

  final WebViewCookieValue cookie;
  final bool remove;
}

class _ContentTypeInfo {
  const _ContentTypeInfo({required this.mimeType, required this.charset});

  final String mimeType;
  final String charset;
}
