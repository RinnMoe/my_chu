import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/session_materialization.dart';

/// The platform-independent cookie shape used at the WebView boundary.
/// Credential values may cross this boundary, but never leave the host-side
/// capability layer or enter feature state.
class WebViewCookieValue {
  const WebViewCookieValue({
    required this.name,
    required this.value,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.expires,
    required this.secure,
    required this.httpOnly,
    required this.sameSite,
  });

  final String name;
  final String value;
  final String domain;
  final bool hostOnly;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;
  final String? sameSite;
}

/// Signals that neither the native CookieManager adapter nor the Flutter
/// CookieManager implementation could read the requested cookie header.
/// An unavailable reader is not equivalent to a valid empty Cookie header.
class WebViewCookieReadException extends StateError {
  WebViewCookieReadException(this.url, {this.cause})
    : super('无法读取 WebView Cookie (${url.host})');

  final Uri url;
  final Object? cause;
}

/// Raw operations exposed only while a coordinator transaction is active.
/// Calling the public coordinator methods from inside [transaction] would
/// wait on the current queue entry and deadlock, so callers use this context.
class WebViewCookieTransactionContext {
  const WebViewCookieTransactionContext._();

  Future<WebViewCookieValue?> readCookie(Uri url, String name) async {
    final override = WebViewCookieCoordinator.readCookieOverride;
    if (override != null) return override(url, name);
    final cookie = await CookieManager.instance().getCookie(
      url: WebUri(url.toString()),
      name: name,
    );
    if (cookie == null || cookie.value == null) return null;
    return _fromPlatformCookie(cookie, url);
  }

  Future<List<WebViewCookieValue>> readCookies(Uri url) async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(url.toString()),
    );
    return [for (final cookie in cookies) _fromPlatformCookie(cookie, url)];
  }

  Future<String?> readCookieHeader(Uri url) async {
    return WebViewCookieCoordinator._readCookieHeader(url);
  }

  Future<bool> setCookie(Uri url, WebViewCookieValue cookie) {
    final override = WebViewCookieCoordinator.setCookieOverride;
    if (override != null) return override(url, cookie);
    return CookieManager.instance().setCookie(
      url: WebUri(url.toString()),
      name: cookie.name,
      value: cookie.value,
      domain: cookie.hostOnly ? null : cookie.domain,
      path: cookie.path,
      expiresDate: cookie.expires?.millisecondsSinceEpoch,
      isHttpOnly: cookie.httpOnly,
      isSecure: cookie.secure,
    );
  }

  Future<bool> deleteCookie(Uri url, WebViewCookieValue cookie) {
    final override = WebViewCookieCoordinator.deleteCookieOverride;
    if (override != null) return override(url, cookie);
    return CookieManager.instance().deleteCookie(
      url: WebUri(url.toString()),
      name: cookie.name,
      domain: cookie.hostOnly ? null : cookie.domain,
      path: cookie.path,
    );
  }

  Future<void> deleteAllCookies() =>
      CookieManager.instance().deleteAllCookies();

  static WebViewCookieValue _fromPlatformCookie(Cookie cookie, Uri url) =>
      WebViewCookieValue(
        name: cookie.name,
        value: cookie.value.toString(),
        domain: cookie.domain ?? url.host,
        hostOnly: cookie.domain == null,
        path: cookie.path ?? '/',
        expires:
            cookie.expiresDate == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                  cookie.expiresDate!,
                  isUtc: true,
                ),
        secure: cookie.isSecure ?? false,
        httpOnly: cookie.isHttpOnly ?? false,
        sameSite: cookie.sameSite?.toString(),
      );
}

/// Coordinates every application-controlled CookieManager operation in the
/// current WebView Dart isolate. It deliberately does not claim to be a
/// native mutex shared by multiple Flutter engines or isolates.
class WebViewCookieCoordinator {
  WebViewCookieCoordinator._();

  static const _nativeChannelName = 'mychu/cookie';
  static Future<void> _tail = Future<void>.value();
  static Future<void>? _resetFuture;
  static Future<void>? _finalResetFuture;

  @visibleForTesting
  static Future<WebViewCookieValue?> Function(Uri url, String name)?
  readCookieOverride;

  @visibleForTesting
  static Future<bool> Function(Uri url, WebViewCookieValue cookie)?
  setCookieOverride;

  @visibleForTesting
  static Future<bool> Function(Uri url, WebViewCookieValue cookie)?
  deleteCookieOverride;

  @visibleForTesting
  static Future<void> Function()? deleteAllCookiesOverride;

  @visibleForTesting
  static Future<String?> Function(Uri url)? nativeCookieHeaderOverride;

  @visibleForTesting
  static Future<String?> Function(Uri url)? cookieHeaderFallbackOverride;

  static Future<T> transaction<T>(
    Future<T> Function(WebViewCookieTransactionContext context) action,
  ) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return (() async {
      await previous;
      try {
        return await action(const WebViewCookieTransactionContext._());
      } finally {
        release.complete();
      }
    })();
  }

  static Future<WebViewCookieValue?> getCookie(Uri url, String name) =>
      transaction((context) => context.readCookie(url, name));

  static Future<String?> getCookieHeader(Uri url) =>
      transaction((context) => context.readCookieHeader(url));

  static Future<bool> setCookie(Uri url, WebViewCookieValue cookie) =>
      transaction((context) => context.setCookie(url, cookie));

  static Future<bool> deleteCookie(Uri url, WebViewCookieValue cookie) =>
      transaction((context) => context.deleteCookie(url, cookie));

  /// Marks the platform epoch stale before entering the queue. The queued
  /// delete therefore forms a reset barrier after all older transactions.
  /// Multiple callers during one reset share exactly one Future.
  ///
  /// [finalBarrier] waits for an already-running reset and then performs a
  /// fresh reset. This is used after account persistence cleanup so a reset
  /// that started earlier cannot be mistaken for the final logout barrier.
  static Future<void> resetCookies({bool finalBarrier = false}) {
    if (finalBarrier) {
      final pendingFinal = _finalResetFuture;
      if (pendingFinal != null) return pendingFinal;
      final pending = _resetFuture;
      late final Future<void> future;
      future = _runFinalReset(pending);
      _finalResetFuture = future;
      return future;
    }

    final pending = _resetFuture;
    if (pending != null) return pending;
    return _startReset();
  }

  static Future<void> _startReset() {
    final handle = SessionMaterializationRegistry.beginCookieManagerReset();
    late final Future<void> future;
    future = _runReset(handle);
    _resetFuture = future;
    return future;
  }

  static Future<void> _runFinalReset(Future<void>? pending) async {
    try {
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // A failed first reset must not prevent a fresh final barrier.
        }
      }
      await _startReset();
    } finally {
      _finalResetFuture = null;
    }
  }

  static Future<void> _runReset(CookieManagerResetHandle handle) async {
    try {
      await handle.previous;
      await transaction((context) async {
        final override = deleteAllCookiesOverride;
        if (override != null) {
          await override();
        } else {
          await context.deleteAllCookies();
        }
      });
    } finally {
      await handle.end();
      _resetFuture = null;
    }
  }

  static Future<String?> _readCookieHeader(Uri url) async {
    Object? nativeError;
    try {
      final override = nativeCookieHeaderOverride;
      final value =
          override != null
              ? await override(url)
              : await const MethodChannel(
                _nativeChannelName,
              ).invokeMethod<String>('getCookies', {'url': url.toString()});
      if (value != null) return value;
    } catch (error) {
      nativeError = error;
    }

    try {
      final override = cookieHeaderFallbackOverride;
      if (override != null) return await override(url);
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(url.toString()),
      );
      return cookies
          .where((cookie) => cookie.name.isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value ?? ''}')
          .join('; ');
    } catch (error) {
      throw WebViewCookieReadException(url, cause: nativeError ?? error);
    }
  }

  @visibleForTesting
  static void debugReset() {
    if (_resetFuture != null || _finalResetFuture != null) {
      throw StateError('cannot reset coordinator while a reset is active');
    }
    _tail = Future<void>.value();
    readCookieOverride = null;
    setCookieOverride = null;
    deleteCookieOverride = null;
    deleteAllCookiesOverride = null;
    nativeCookieHeaderOverride = null;
    cookieHeaderFallbackOverride = null;
  }
}
