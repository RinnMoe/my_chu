import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'web_view_cookie_coordinator.dart';
import 'web_view_session_binding.dart';
import '../services/auth_service.dart';
import '../services/campus_service_session_service.dart';
import '../services/campus_session_store.dart';
import '../services/federated_session.dart';
import '../services/logger_service.dart';
import '../services/persistent_campus_cookie_jar.dart';
import '../services/service_endpoints.dart';
import '../services/session_materialization.dart';
import '../services/session_runtime_fence.dart';

class CampusWebViewCookieSeed {
  final String name;
  final String value;
  final String domain;
  final bool hostOnly;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;
  final String? sameSite;

  const CampusWebViewCookieSeed({
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
}

class CampusWebViewSessionBootstrap {
  final String accountKey;
  final CampusServiceId serviceId;
  final Uri entryUri;
  final List<CampusWebViewCookieSeed> cookies;
  final Map<String, String> initialHeaders;
  final Uri? sessionUri;
  final SessionRuntimeFence fence;
  final WebViewMaterializationFence materializationFence;
  final String identityEpoch;
  final int sessionRevision;

  const CampusWebViewSessionBootstrap({
    required this.accountKey,
    required this.serviceId,
    required this.entryUri,
    required this.cookies,
    required this.initialHeaders,
    required this.sessionUri,
    required this.fence,
    required this.materializationFence,
    required this.identityEpoch,
    required this.sessionRevision,
  });
}

/// Signals that a bootstrap was invalidated while it was being materialized.
/// Only this failure is safe for the shared host bridge to retry once.
class CampusWebViewSessionFenceExpiredException extends StateError {
  final CampusServiceId serviceId;

  CampusWebViewSessionFenceExpiredException(this.serviceId)
    : super('认证 WebView 会话的运行时 fence 已过期 (${serviceId.value})');
}

/// A platform CookieManager reset invalidates the whole WebView materialization
/// lineage. Unlike a service-generation drift, an operation that started
/// before this reset must fail closed instead of acquiring a new lease.
class CampusWebViewCookieManagerResetException extends StateError {
  final CampusServiceId serviceId;

  CampusWebViewCookieManagerResetException(this.serviceId)
    : super('认证 WebView CookieManager 已重置 (${serviceId.value})');
}

/// The only bridge allowed to copy account-scoped HTTP cookies into a WebView.
/// It exports only the target definition's hosts/paths and imports only after
/// an explicit host-side call.
class CampusWebViewCookieBridge {
  const CampusWebViewCookieBridge._();

  static final _browserRelayCleanupFences = <String>{};

  /// Test seams for the platform CookieManager boundary. Production callers
  /// leave these unset; tests can model a real CookieManager transaction
  /// without depending on a platform WebView implementation.
  @visibleForTesting
  static Future<CampusWebViewCookieSeed?> Function(Uri url, String name)?
  readCookieOverride;

  @visibleForTesting
  static Future<bool> Function(Uri url, CampusWebViewCookieSeed cookie)?
  setCookieOverride;

  @visibleForTesting
  static Future<bool> Function(Uri url, CampusWebViewCookieSeed cookie)?
  deleteCookieOverride;

  static Future<CampusWebViewSessionBootstrap> exportSession({
    required CampusSessionStore store,
    required CampusServiceDefinition definition,
    required Uri entryUri,
    Map<String, String> initialHeaders = const {},
    Uri? sessionUri,
    Iterable<CampusWebViewCookieSeed> transientCookies = const [],
    SessionRuntimeFence? fence,
    WebViewMaterializationFence? materializationFence,
  }) async {
    _validateEntry(definition, entryUri);
    final scope = definition.scopeFor(entryUri);
    final targetScopeKey = scope.keyFor(entryUri);
    final capturedFence =
        fence ??
        store.captureFence(
          serviceId: definition.id,
          scopeKey: targetScopeKey,
          sessionRevision: AuthService.sessionRevision,
        );
    if (capturedFence.serviceId != definition.id ||
        capturedFence.accountKey != store.accountKey ||
        !capturedFence.serviceGenerations.containsKey(targetScopeKey)) {
      throw StateError('认证 WebView 会话 fence 与导出范围不匹配');
    }
    final capturedMaterializationFence =
        materializationFence ??
        await store.captureWebViewFence(
          serviceId: definition.id,
          sessionRevision: capturedFence.sessionRevision,
        );
    await _assertFenceCurrent(
      store,
      capturedFence,
      materializationFence: capturedMaterializationFence,
    );
    final jar = store.cookieJar(definition.id, scope: scope);
    final serviceCookies = await jar.cookiesFor(entryUri);
    final rootCookies = await store.rootCookieJar.snapshot();
    final seeds = <CampusWebViewCookieSeed>[
      ...[
        ...rootCookies.where(_isAllowedRootCookie),
        ...serviceCookies.where(
          (cookie) => _isAllowedCookie(definition, entryUri, cookie),
        ),
      ].map(
        (cookie) => CampusWebViewCookieSeed(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          hostOnly: cookie.hostOnly,
          path: cookie.path,
          expires: cookie.expires,
          secure: cookie.secure,
          httpOnly: cookie.httpOnly,
          sameSite: cookie.sameSite,
        ),
      ),
      ...transientCookies.where(
        (cookie) => _isAllowedSeed(definition, entryUri, cookie),
      ),
    ];
    final derivedHeaders = await _materializedHeaders(
      store,
      definition,
      entryUri,
      jar,
    );
    derivedHeaders.addAll(initialHeaders);
    await _assertFenceCurrent(
      store,
      capturedFence,
      materializationFence: capturedMaterializationFence,
    );
    return CampusWebViewSessionBootstrap(
      accountKey: store.accountKey,
      serviceId: definition.id,
      entryUri: entryUri,
      cookies: seeds,
      initialHeaders: Map.unmodifiable(derivedHeaders),
      sessionUri: sessionUri,
      fence: capturedFence,
      materializationFence: capturedMaterializationFence,
      identityEpoch: store.identityEpoch,
      sessionRevision: capturedFence.sessionRevision,
    );
  }

  /// Acquires the shared service lease before exporting a WebView bootstrap.
  /// The bridge only materializes the lease, so a feature page never receives
  /// a cookie header, token, or credential object.
  static Future<CampusWebViewSessionBootstrap> prepareSession({
    required CampusServiceDefinition definition,
    required Uri entryUri,
    Map<String, String> initialHeaders = const {},
    bool forceRefresh = false,
    String? expectedAccountKey,
    int? expectedCookieManagerEpoch,
  }) async {
    _validateEntry(definition, entryUri);
    _assertExpectedCookieManagerEpoch(
      expectedCookieManagerEpoch,
      definition.id,
    );
    if (definition.webViewBootstrapMode == WebViewBootstrapMode.browserRelay) {
      return _prepareBrowserRelaySession(
        definition: definition,
        entryUri: entryUri,
        initialHeaders: initialHeaders,
        expectedAccountKey: expectedAccountKey,
        expectedCookieManagerEpoch: expectedCookieManagerEpoch,
      );
    }
    final lease = await CampusSessionService.acquireForWebView(
      definition: definition,
      entryUri: entryUri,
      forceRefresh: forceRefresh,
      expectedAccountKey: expectedAccountKey,
    );
    _assertExpectedCookieManagerEpoch(
      expectedCookieManagerEpoch,
      definition.id,
    );
    if (lease == null) {
      throw StateError('认证 WebView 服务会话不可用');
    }
    final sessionUri = lease.session.sessionUri;
    final usesWebViewSessionMaterializer =
        definition.sessionMaterializer.containsWebViewSessionMaterializer;
    if ((usesWebViewSessionMaterializer || definition.webViewUsesSessionUri) &&
        (sessionUri == null ||
            !_isValidWebViewSessionUri(definition, sessionUri))) {
      throw StateError('认证 WebView 会话入口无效');
    }
    final transientCookies = usesWebViewSessionMaterializer
        ? _cookieSeedsForHeader(entryUri, lease.session.cookieHeader)
        : const <CampusWebViewCookieSeed>[];
    // Acquisition may silently replace the identity for the same account.
    // Reopen after acquisition so reads use the new identity epoch.
    final store = await CampusSessionStore.open(accountKey: lease.accountKey);
    _assertExpectedCookieManagerEpoch(
      expectedCookieManagerEpoch,
      definition.id,
    );
    return exportSession(
      store: store,
      definition: definition,
      entryUri: entryUri,
      initialHeaders: initialHeaders,
      transientCookies: transientCookies,
      sessionUri:
          usesWebViewSessionMaterializer || definition.webViewUsesSessionUri
              ? sessionUri
              : null,
      fence: lease.fence,
      materializationFence: lease.materializationFence,
    );
  }

  /// Static SPA entries do not issue a service cookie until their JavaScript
  /// starts an OAuth/CAS navigation. Materialize only the account-owned root
  /// identity here, then let the WebView complete that declared redirect.
  static Future<CampusWebViewSessionBootstrap> _prepareBrowserRelaySession({
    required CampusServiceDefinition definition,
    required Uri entryUri,
    required Map<String, String> initialHeaders,
    required String? expectedAccountKey,
    required int? expectedCookieManagerEpoch,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null ||
        expectedAccountKey != null &&
            account.accountKey != expectedAccountKey) {
      throw StateError('认证 WebView 会话的账号已切换');
    }
    _assertExpectedCookieManagerEpoch(
      expectedCookieManagerEpoch,
      definition.id,
    );
    final store = await CampusSessionStore.open(accountKey: account.accountKey);
    if ((await store.rootCookieJar.snapshot()).isEmpty) {
      throw StateError('认证 WebView 根身份会话不可用');
    }
    _assertExpectedCookieManagerEpoch(
      expectedCookieManagerEpoch,
      definition.id,
    );
    return exportSession(
      store: store,
      definition: definition,
      entryUri: entryUri,
      initialHeaders: initialHeaders,
    );
  }

  /// Prepares, materializes, and validates a WebView session through the
  /// shared credential broker. A stale runtime fence gets one fresh flight;
  /// account switches and platform write failures are not retried here.
  static Future<CampusWebViewSessionBootstrap> prepareAndSeedSession({
    required CampusServiceId serviceId,
    required Uri entryUri,
    Map<String, String> initialHeaders = const {},
    bool forceRefresh = false,
  }) async {
    // Fix the platform epoch before the first await. If a manual-login reset
    // happens later, this operation is no longer allowed to acquire a new
    // epoch and reseed the account that the reset was meant to detach.
    final expectedCookieManagerEpoch =
        SessionMaterializationRegistry.cookieManagerEpoch;
    final initialAccount = await AuthService.getCurrentAccount();
    if (initialAccount == null) throw StateError('请先登录');
    return _prepareAndSeedSession(
      serviceId: serviceId,
      entryUri: entryUri,
      initialHeaders: initialHeaders,
      forceRefresh: forceRefresh,
      expectedAccountKey: initialAccount.accountKey,
      expectedCookieManagerEpoch: expectedCookieManagerEpoch,
    );
  }

  /// Refreshes only a same-account materialization drift for an existing
  /// WebView. Account/session/generation changes and CookieManager resets stay
  /// fail-closed and cannot be converted into a fresh lease here.
  static Future<WebViewSessionBinding> refreshAndSeedBinding({
    required WebViewSessionBinding binding,
    required Uri entryUri,
  }) async {
    final definition = CampusServiceEndpoints.definitionForId(
      binding.serviceId,
    );
    if (definition == null) {
      throw ArgumentError.value(binding.serviceId, 'binding.serviceId');
    }
    _validateEntry(definition, entryUri);
    if (definition.webViewBootstrapMode !=
            WebViewBootstrapMode.serviceSession ||
        definition.sessionMaterializer.containsWebViewSessionMaterializer ||
        definition.webViewUsesSessionUri) {
      throw CampusWebViewSessionFenceExpiredException(binding.serviceId);
    }
    _assertMaterializationCookieManagerCurrent(binding.materializationFence);
    final account = await AuthService.getCurrentAccount();
    if (account == null || account.accountKey != binding.accountKey) {
      throw CampusWebViewSessionFenceExpiredException(binding.serviceId);
    }
    final store = await CampusSessionStore.open(accountKey: binding.accountKey);
    for (var attempt = 0; attempt < 2; attempt++) {
      await _assertRefreshBindingRuntimeCurrent(store, binding);
      try {
        final bootstrap = await exportSession(
          store: store,
          definition: definition,
          entryUri: entryUri,
          fence: binding.runtimeFence,
        );
        await seedCookieManager(bootstrap);
        await assertBootstrapCurrent(bootstrap);
        return bindingForBootstrap(bootstrap);
      } on CampusWebViewCookieManagerResetException {
        rethrow;
      } on CampusWebViewSessionFenceExpiredException {
        if (attempt == 1) rethrow;
      }
    }
    throw CampusWebViewSessionFenceExpiredException(binding.serviceId);
  }

  static Future<void> _assertRefreshBindingRuntimeCurrent(
    CampusSessionStore store,
    WebViewSessionBinding binding,
  ) async {
    _assertMaterializationCookieManagerCurrent(binding.materializationFence);
    await _assertFenceCurrent(store, binding.runtimeFence);
  }

  static Future<CampusWebViewSessionBootstrap> _prepareAndSeedSession({
    required CampusServiceId serviceId,
    required Uri entryUri,
    Map<String, String> initialHeaders = const {},
    bool forceRefresh = false,
    required String expectedAccountKey,
    required int expectedCookieManagerEpoch,
    int? expectedSessionRevision,
    String? expectedIdentityEpoch,
  }) async {
    final definition = CampusServiceEndpoints.definitionForId(serviceId);
    if (definition == null) throw ArgumentError.value(serviceId, 'serviceId');
    // Keep the original account fixed across both bounded attempts. A retry
    // must never turn into recovery for a newly selected account.
    for (var attempt = 0; attempt < 2; attempt++) {
      _assertExpectedCookieManagerEpoch(
        expectedCookieManagerEpoch,
        definition.id,
      );
      await _assertCurrentAccountKey(expectedAccountKey);
      _assertExpectedCookieManagerEpoch(
        expectedCookieManagerEpoch,
        definition.id,
      );
      try {
        final bootstrap = await prepareSession(
          definition: definition,
          entryUri: entryUri,
          initialHeaders: initialHeaders,
          forceRefresh:
              forceRefresh ||
              attempt > 0 &&
                  expectedSessionRevision == null &&
                  expectedIdentityEpoch == null,
          expectedAccountKey: expectedAccountKey,
          expectedCookieManagerEpoch: expectedCookieManagerEpoch,
        );
        if (expectedSessionRevision != null &&
                bootstrap.sessionRevision != expectedSessionRevision ||
            expectedIdentityEpoch != null &&
                bootstrap.identityEpoch != expectedIdentityEpoch) {
          throw CampusWebViewSessionFenceExpiredException(definition.id);
        }
        _assertExpectedCookieManagerEpoch(
          expectedCookieManagerEpoch,
          definition.id,
        );
        await seedCookieManager(bootstrap);
        _assertExpectedCookieManagerEpoch(
          expectedCookieManagerEpoch,
          definition.id,
        );
        await assertBootstrapCurrent(bootstrap);
        return bootstrap;
      } on CampusWebViewCookieManagerResetException {
        rethrow;
      } on CampusWebViewSessionFenceExpiredException {
        if (attempt == 1) rethrow;
        await _assertCurrentAccountKey(expectedAccountKey);
      }
    }
    throw StateError('认证 WebView 会话恢复失败');
  }

  static Future<void> importFromWebView({
    required CampusSessionStore store,
    required CampusServiceDefinition definition,
    required Uri uri,
    required Iterable<CampusWebViewCookieSeed> cookieSnapshot,
  }) async {
    _validateEntry(definition, uri);
    final scope = definition.scopeFor(uri);
    final jar = store.cookieJar(definition.id, scope: scope);
    final mutation =
        definition.rootIdentity
            ? await store.beginRootMaterializationMutation()
            : await store.beginServiceMaterializationMutation(definition.id);
    var ended = false;
    try {
      for (final seed in cookieSnapshot) {
        if (!_isAllowedSeed(definition, uri, seed)) continue;
        await jar.importCookie(
          PersistentCampusCookie(
            name: seed.name,
            value: seed.value,
            domain: seed.domain.toLowerCase(),
            hostOnly: seed.hostOnly,
            path: seed.path,
            expires: seed.expires,
            maxAge: null,
            secure: seed.secure,
            httpOnly: seed.httpOnly,
            sameSite: seed.sameSite,
            createdAt: DateTime.now().toUtc(),
            identityEpoch: store.identityEpoch,
            sessionScope: scope.key,
          ),
          mutation: mutation,
        );
      }
      await mutation.end(commit: true);
      ended = true;
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  static Future<void> seedCookieManager(
    CampusWebViewSessionBootstrap bootstrap,
  ) => WebViewCookieCoordinator.transaction(
    (context) => _seedCookieManager(bootstrap, context),
  );

  static Future<void> _seedCookieManager(
    CampusWebViewSessionBootstrap bootstrap,
    WebViewCookieTransactionContext context,
  ) async {
    final written = <_WebViewCookieMutation>[];
    final store = await CampusSessionStore.open(
      accountKey: bootstrap.accountKey,
    );
    try {
      await _assertBootstrapCurrentWithStore(bootstrap, store);
      await _removeLegacyAcademicRootSession(bootstrap, context, written);
      final browserRelayCleanupKey = _browserRelayCleanupKey(bootstrap);
      if (browserRelayCleanupKey != null &&
          !_browserRelayCleanupFences.contains(browserRelayCleanupKey)) {
        await _clearBrowserRelayCookies(bootstrap, context, written);
      }
      final cookiesToSeed = _cookiesForBrowserRelay(bootstrap);
      final cookiesByUrl = <Uri, List<CampusWebViewCookieSeed>>{};
      for (final cookie in cookiesToSeed) {
        final url = Uri.parse(_seedUrl(cookie, bootstrap.entryUri));
        cookiesByUrl.putIfAbsent(url, () => []).add(cookie);
      }
      final skippedCookies = bootstrap.cookies
          .where((cookie) => !cookiesToSeed.contains(cookie))
          .toList(growable: false);
      for (final cookie in skippedCookies) {
        _assertBootstrapRuntimeCurrent(bootstrap);
        final url = Uri.parse(_seedUrl(cookie, bootstrap.entryUri));
        final previous = await _readCookie(context, url, cookie.name);
        if (previous == null) continue;
        final removed = await _deleteCookie(context, url, previous);
        if (removed) {
          written.add(
            _WebViewCookieMutation(
              url: url,
              cookie: previous,
              previous: previous,
            ),
          );
        }
      }
      for (final entry in cookiesByUrl.entries) {
        _assertBootstrapRuntimeCurrent(bootstrap);
        final previousCookies = await _readCookies(
          context,
          entry.key,
          entry.value.map((cookie) => cookie.name),
        );
        for (final cookie in entry.value) {
          _assertBootstrapRuntimeCurrent(bootstrap);
          final previous = previousCookies[cookie.name];
          if (previous?.value == cookie.value) {
            continue;
          }
          final committed = await _setCookie(context, entry.key, cookie);
          if (!committed) {
            final confirmed = await _readCookie(
              context,
              entry.key,
              cookie.name,
            );
            if (confirmed?.value == cookie.value) {
              written.add(
                _WebViewCookieMutation(
                  url: entry.key,
                  cookie: cookie,
                  previous: previous,
                ),
              );
              continue;
            }
            AppLogger.event(
              level: 'WARN',
              code: 'webview.cookie.commit_failed',
              message: '认证 WebView 会话数据写入失败',
              operation: operationForAuthenticatedService(
                bootstrap.serviceId.value,
              ),
              exceptionType: 'CookieCommitFailure',
            );
            throw StateError('认证 WebView Cookie 写入失败');
          }
          written.add(
            _WebViewCookieMutation(
              url: entry.key,
              cookie: cookie,
              previous: previous,
            ),
          );
        }
      }
      await _assertBootstrapCurrentWithStore(bootstrap, store);
      if (browserRelayCleanupKey != null) {
        _browserRelayCleanupFences.add(browserRelayCleanupKey);
      }
    } catch (error) {
      await _rollbackCookieWrites(context, written);
      rethrow;
    }
  }

  static Future<void> _removeLegacyAcademicRootSession(
    CampusWebViewSessionBootstrap bootstrap,
    WebViewCookieTransactionContext context,
    List<_WebViewCookieMutation> written,
  ) async {
    if (bootstrap.serviceId != CampusServices.academicAffairs) return;
    final rootUri = bootstrap.entryUri.replace(path: '/', query: null);
    final previous = await _readCookie(context, rootUri, 'JSESSIONID');
    if (previous == null || previous.path != '/') return;
    final removed = await _deleteCookie(context, rootUri, previous);
    if (!removed) return;
    written.add(
      _WebViewCookieMutation(
        url: rootUri,
        cookie: previous,
        previous: previous,
      ),
    );
  }

  /// CAS may expose the same identity cookie at both `/` and
  /// `/authserver`. Android WebView sends both values when they are seeded,
  /// while the IDS login endpoint can interpret the duplicate name as an
  /// invalid session. A browser-relay launch only needs the most specific
  /// path for each identity-host cookie; keep the root copy for names that do
  /// not have a path-scoped replacement.
  static List<CampusWebViewCookieSeed> _cookiesForBrowserRelay(
    CampusWebViewSessionBootstrap bootstrap,
  ) {
    if (bootstrap.serviceId != CampusServices.sportsPortal) {
      return bootstrap.cookies;
    }
    final grouped = <String, List<CampusWebViewCookieSeed>>{};
    for (final cookie in bootstrap.cookies) {
      final host = cookie.domain.toLowerCase();
      final isIdentityHost =
          host == 'ids.chd.edu.cn' || host == 'identity.chd.edu.cn';
      if (!isIdentityHost) continue;
      final key = '$host|${cookie.hostOnly}|${cookie.name.toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(cookie);
    }
    final skipped = <CampusWebViewCookieSeed>{};
    for (final cookies in grouped.values) {
      if (cookies.length < 2) continue;
      final longestPath = cookies
          .map((cookie) => cookie.path.length)
          .reduce(math.max);
      skipped.addAll(
        cookies.where((cookie) => cookie.path.length < longestPath),
      );
    }
    if (skipped.isEmpty) return bootstrap.cookies;
    return [
      for (final cookie in bootstrap.cookies)
        if (!skipped.contains(cookie)) cookie,
    ];
  }

  static String? _browserRelayCleanupKey(
    CampusWebViewSessionBootstrap bootstrap,
  ) {
    if (bootstrap.serviceId != CampusServices.sportsPortal) return null;
    return '${bootstrap.accountKey}|${bootstrap.identityEpoch}';
  }

  /// Removes the previous WebView projection for the sports browser-relay
  /// once per account identity epoch. The persistent root session is seeded
  /// immediately afterwards, so this only drops stale platform copies and
  /// cannot affect cookies belonging to another account.
  static Future<void> _clearBrowserRelayCookies(
    CampusWebViewSessionBootstrap bootstrap,
    WebViewCookieTransactionContext context,
    List<_WebViewCookieMutation> written,
  ) async {
    final entryRoot = bootstrap.entryUri.replace(
      path: '/',
      query: null,
      fragment: null,
    );
    final identityRoot = CampusServiceEndpoints.idsAuthUri.replace(
      path: '/',
      query: null,
      fragment: null,
    );
    final identityAuth = CampusServiceEndpoints.idsAuthUri.replace(
      query: null,
      fragment: null,
    );
    final realmRoot = CampusServiceEndpoints.identityRealmUri.replace(
      path: '/',
      query: null,
      fragment: null,
    );
    final urls = <Uri>{
      entryRoot,
      identityRoot,
      identityAuth,
      CampusServiceEndpoints.identityRealmUri,
      realmRoot,
    };
    final seen = <String>{};
    for (final url in urls) {
      List<WebViewCookieValue> cookies;
      try {
        cookies = await context.readCookies(url);
      } catch (_) {
        continue;
      }
      for (final cookie in cookies) {
        final domain = cookie.domain.toLowerCase();
        if (!_isAllowedBrowserRelayCookieDomain(domain, url.host)) continue;
        final key =
            '$domain|${cookie.hostOnly}|${cookie.path}|${cookie.name.toLowerCase()}';
        if (!seen.add(key)) continue;
        final seed = CampusWebViewCookieSeed(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          hostOnly: cookie.hostOnly,
          path: cookie.path,
          expires: cookie.expires,
          secure: cookie.secure,
          httpOnly: cookie.httpOnly,
          sameSite: cookie.sameSite,
        );
        final lookupUri = url.replace(
          path: cookie.path,
          query: null,
          fragment: null,
        );
        if (await _deleteCookie(context, lookupUri, seed)) {
          written.add(
            _WebViewCookieMutation(
              url: lookupUri,
              cookie: seed,
              previous: seed,
            ),
          );
        }
      }
    }
  }

  static bool _isAllowedBrowserRelayCookieDomain(
    String domain,
    String requestHost,
  ) {
    if (domain == 'ids.chd.edu.cn' ||
        domain == 'identity.chd.edu.cn' ||
        domain == 'stuh5.chd.edu.cn') {
      return true;
    }
    if (domain == 'chd.edu.cn' || domain.endsWith('.chd.edu.cn')) {
      return requestHost == domain || requestHost.endsWith('.$domain');
    }
    return false;
  }

  /// Re-checks a bootstrap immediately before a WebView load.
  static Future<void> assertBootstrapCurrent(
    CampusWebViewSessionBootstrap bootstrap,
  ) => _assertBootstrapCurrent(bootstrap);

  static Future<void> _assertCurrentAccountKey(String accountKey) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null || account.accountKey != accountKey) {
      throw StateError('认证 WebView 会话的账号已切换');
    }
  }

  static void _assertExpectedCookieManagerEpoch(
    int? expectedEpoch,
    CampusServiceId serviceId,
  ) {
    if (expectedEpoch != null &&
        SessionMaterializationRegistry.cookieManagerEpoch != expectedEpoch) {
      throw CampusWebViewCookieManagerResetException(serviceId);
    }
  }

  static void _assertMaterializationCookieManagerCurrent(
    WebViewMaterializationFence fence,
  ) {
    if (fence.cookieManagerEpoch !=
            SessionMaterializationRegistry.cookieManagerEpoch ||
        !SessionMaterializationRegistry.isCookieManagerCurrent(
          epoch: fence.cookieManagerEpoch,
        )) {
      throw CampusWebViewCookieManagerResetException(fence.serviceId);
    }
  }

  static Future<void> _assertFenceCurrent(
    CampusSessionStore store,
    SessionRuntimeFence fence, {
    WebViewMaterializationFence? materializationFence,
  }) async {
    if (fence.accountKey != store.accountKey) {
      throw StateError('认证 WebView 会话的账号已切换');
    }
    final account = await AuthService.getCurrentAccount();
    if (account != null && account.accountKey != fence.accountKey) {
      throw StateError('认证 WebView 会话的账号已切换');
    }
    if (materializationFence != null) {
      _assertMaterializationCookieManagerCurrent(materializationFence);
    }
    final currentStore = await CampusSessionStore.open(
      accountKey: fence.accountKey,
    );
    if (materializationFence != null) {
      _assertMaterializationCookieManagerCurrent(materializationFence);
    }
    if (!fence.isCurrent(
      currentAccountKey: account?.accountKey ?? fence.accountKey,
      currentSessionRevision: AuthService.sessionRevision,
    )) {
      throw CampusWebViewSessionFenceExpiredException(fence.serviceId);
    }
    if (materializationFence != null &&
        !materializationFence.isCurrent(
          currentAccountKey: account?.accountKey ?? fence.accountKey,
          currentIdentityEpoch: currentStore.identityEpoch,
          currentSessionRevision: AuthService.sessionRevision,
        )) {
      throw CampusWebViewSessionFenceExpiredException(fence.serviceId);
    }
  }

  static Future<void> _assertBootstrapCurrent(
    CampusWebViewSessionBootstrap bootstrap,
  ) async {
    final store = await CampusSessionStore.open(
      accountKey: bootstrap.accountKey,
    );
    await _assertBootstrapCurrentWithStore(bootstrap, store);
  }

  static void _assertBootstrapRuntimeCurrent(
    CampusWebViewSessionBootstrap bootstrap,
  ) {
    final fence = bootstrap.fence;
    if (fence.accountKey != bootstrap.accountKey ||
        fence.serviceId != bootstrap.serviceId ||
        fence.sessionRevision != bootstrap.sessionRevision ||
        bootstrap.materializationFence.accountKey != bootstrap.accountKey ||
        bootstrap.materializationFence.serviceId != bootstrap.serviceId ||
        bootstrap.materializationFence.identityEpoch !=
            bootstrap.identityEpoch ||
        bootstrap.materializationFence.sessionRevision !=
            bootstrap.sessionRevision) {
      throw StateError('认证 WebView 会话 bootstrap fence 无效');
    }
    _assertMaterializationCookieManagerCurrent(bootstrap.materializationFence);
    if (!fence.isCurrent(
          currentAccountKey: bootstrap.accountKey,
          currentSessionRevision: AuthService.sessionRevision,
        ) ||
        !bootstrap.materializationFence.isCurrent(
          currentAccountKey: bootstrap.accountKey,
          currentIdentityEpoch: bootstrap.identityEpoch,
          currentSessionRevision: AuthService.sessionRevision,
        )) {
      throw CampusWebViewSessionFenceExpiredException(bootstrap.serviceId);
    }
  }

  static Future<void> _assertBootstrapCurrentWithStore(
    CampusWebViewSessionBootstrap bootstrap,
    CampusSessionStore store,
  ) async {
    _assertBootstrapRuntimeCurrent(bootstrap);
    final account = await AuthService.getCurrentAccount();
    if (account == null || account.accountKey != bootstrap.accountKey) {
      throw StateError('认证 WebView 会话的账号已切换');
    }
    if (store.accountKey != bootstrap.accountKey ||
        !await store.isCurrentIdentityEpoch()) {
      throw CampusWebViewSessionFenceExpiredException(bootstrap.serviceId);
    }
    _assertBootstrapRuntimeCurrent(bootstrap);
  }

  static Future<void> assertBindingCurrent(
    WebViewSessionBinding binding,
  ) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null || account.accountKey != binding.accountKey) {
      throw CampusWebViewSessionFenceExpiredException(binding.serviceId);
    }
    if (binding.runtimeFence.accountKey != binding.accountKey ||
        binding.runtimeFence.serviceId != binding.serviceId ||
        binding.runtimeFence.sessionRevision != binding.sessionRevision) {
      throw StateError('认证 WebView binding fence 无效');
    }
    _assertMaterializationCookieManagerCurrent(binding.materializationFence);
    final store = await CampusSessionStore.open(accountKey: binding.accountKey);
    await _assertFenceCurrent(
      store,
      binding.runtimeFence,
      materializationFence: binding.materializationFence,
    );
  }

  static Future<bool> isBindingCurrent(WebViewSessionBinding binding) async {
    try {
      await assertBindingCurrent(binding);
      return true;
    } on CampusWebViewSessionFenceExpiredException {
      return false;
    } on StateError {
      return false;
    }
  }

  static WebViewSessionBinding bindingForBootstrap(
    CampusWebViewSessionBootstrap bootstrap,
  ) => WebViewSessionBinding(
    accountKey: bootstrap.accountKey,
    serviceId: bootstrap.serviceId,
    sessionRevision: bootstrap.sessionRevision,
    identityEpoch: bootstrap.identityEpoch,
    runtimeFence: bootstrap.fence,
    materializationFence: bootstrap.materializationFence,
  );

  static Future<CampusWebViewCookieSeed?> _readCookie(
    WebViewCookieTransactionContext context,
    Uri url,
    String name,
  ) async {
    final override = readCookieOverride;
    if (override != null) return override(url, name);
    try {
      final cookie = await context.readCookie(url, name);
      if (cookie == null) return null;
      return CampusWebViewCookieSeed(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        hostOnly: cookie.hostOnly,
        path: cookie.path,
        expires: cookie.expires,
        secure: cookie.secure,
        httpOnly: cookie.httpOnly,
        sameSite: cookie.sameSite,
      );
    } catch (_) {
      // Some platform implementations do not expose getCookie. A failed
      // read still permits best-effort deletion during rollback.
      return null;
    }
  }

  static Future<Map<String, CampusWebViewCookieSeed>> _readCookies(
    WebViewCookieTransactionContext context,
    Uri url,
    Iterable<String> names,
  ) async {
    final override = readCookieOverride;
    if (override != null) {
      final cookies = <String, CampusWebViewCookieSeed>{};
      for (final name in names.toSet()) {
        final cookie = await override(url, name);
        if (cookie != null) cookies[name] = cookie;
      }
      return cookies;
    }
    try {
      return {
        for (final cookie in await context.readCookies(url))
          cookie.name: CampusWebViewCookieSeed(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            hostOnly: cookie.hostOnly,
            path: cookie.path,
            expires: cookie.expires,
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            sameSite: cookie.sameSite,
          ),
      };
    } catch (_) {
      return const <String, CampusWebViewCookieSeed>{};
    }
  }

  static Future<bool> _setCookie(
    WebViewCookieTransactionContext context,
    Uri url,
    CampusWebViewCookieSeed cookie,
  ) {
    final override = setCookieOverride;
    if (override != null) return override(url, cookie);
    return context.setCookie(
      url,
      WebViewCookieValue(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        hostOnly: cookie.hostOnly,
        path: cookie.path,
        expires: cookie.expires,
        secure: cookie.secure,
        httpOnly: cookie.httpOnly,
        sameSite: cookie.sameSite,
      ),
    );
  }

  static Future<bool> _deleteCookie(
    WebViewCookieTransactionContext context,
    Uri url,
    CampusWebViewCookieSeed cookie,
  ) {
    final override = deleteCookieOverride;
    if (override != null) return override(url, cookie);
    return context.deleteCookie(
      url,
      WebViewCookieValue(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        hostOnly: cookie.hostOnly,
        path: cookie.path,
        expires: cookie.expires,
        secure: cookie.secure,
        httpOnly: cookie.httpOnly,
        sameSite: cookie.sameSite,
      ),
    );
  }

  static Future<void> _rollbackCookieWrites(
    WebViewCookieTransactionContext context,
    List<_WebViewCookieMutation> written,
  ) async {
    for (final mutation in written.reversed) {
      try {
        if (mutation.previous == null) {
          await _deleteCookie(context, mutation.url, mutation.cookie);
        } else {
          await _setCookie(context, mutation.url, mutation.previous!);
        }
      } catch (_) {
        // Rollback is best effort; the original stale/failure exception is
        // the actionable result for the caller.
      }
    }
  }

  static void _validateEntry(CampusServiceDefinition definition, Uri uri) {
    if (!definition.allowsUri(uri)) {
      throw ArgumentError.value(uri, 'uri', '不属于服务允许的主机、端口或路径');
    }
  }

  static bool _isAllowedCookie(
    CampusServiceDefinition definition,
    Uri entryUri,
    PersistentCampusCookie cookie,
  ) {
    if (cookie.value.isEmpty ||
        !_hostAllowed(definition, entryUri.host) ||
        !_pathAllowed(definition, entryUri.path) ||
        !_pathMatches(entryUri.path, cookie.path)) {
      return false;
    }
    if (cookie.hostOnly && cookie.domain != entryUri.host.toLowerCase()) {
      return false;
    }
    if (!cookie.hostOnly && !_domainAllowed(definition, cookie.domain)) {
      return false;
    }
    return !cookie.secure || entryUri.scheme.toLowerCase() == 'https';
  }

  static bool _isAllowedRootCookie(PersistentCampusCookie cookie) {
    if (cookie.value.isEmpty) return false;
    if (cookie.hostOnly) {
      return cookie.domain == 'ids.chd.edu.cn' ||
          cookie.domain == 'identity.chd.edu.cn';
    }
    return cookie.domain == 'chd.edu.cn' ||
        cookie.domain.endsWith('.chd.edu.cn');
  }

  static Future<Map<String, String>> _materializedHeaders(
    CampusSessionStore store,
    CampusServiceDefinition definition,
    Uri entryUri,
    PersistentCampusCookieJar jar,
  ) async {
    final headers = <String, String>{};
    Future<void> visit(SessionMaterializer materializer) async {
      switch (materializer) {
        case HeaderFromCookie(
          :final cookieName,
          :final fallbackCookieName,
          :final headerName,
        ):
          final cookies = await jar.cookiesFor(entryUri);
          final cookie =
              cookies
                  .where((cookie) => cookie.name == cookieName)
                  .firstOrNull ??
              (fallbackCookieName == null
                  ? null
                  : cookies
                      .where((cookie) => cookie.name == fallbackCookieName)
                      .firstOrNull);
          final value = cookie?.value;
          if (value != null && value.isNotEmpty) {
            headers[headerName] = value;
            // The legacy campus-app bootstrap sent JWSESSION both ways. Keep
            // that compatibility header in the host-side WebView bridge;
            // feature pages still never handle the cookie themselves.
            if (definition.id == CampusServices.campusApp &&
                cookieName == 'JWSESSION') {
              headers['Cookie'] = '$cookieName=$value';
            }
          }
        case CompositeMaterializer(:final materializers):
          for (final child in materializers) {
            await visit(child);
          }
        case TokenFromRedirect(:final headerName, :final prefix):
          final artifact = await store.artifacts.read(definition.id);
          if (artifact != null) {
            headers[headerName] = '$prefix${artifact.rawValue}';
          }
        case CookieMaterializer():
        case WebViewSessionMaterializer():
        case CustomPostSsoBootstrap():
          break;
      }
    }

    await visit(definition.sessionMaterializer);
    return headers;
  }

  static bool _isAllowedSeed(
    CampusServiceDefinition definition,
    Uri uri,
    CampusWebViewCookieSeed seed,
  ) {
    final domain = seed.domain.toLowerCase();
    if (seed.name.isEmpty ||
        seed.value.isEmpty ||
        !seed.path.startsWith('/') ||
        !_pathAllowed(definition, uri.path) ||
        !_pathMatches(uri.path, seed.path) ||
        (seed.secure && uri.scheme.toLowerCase() != 'https')) {
      return false;
    }
    if (seed.hostOnly) return domain == uri.host.toLowerCase();
    return _domainAllowed(definition, domain);
  }

  static bool _hostAllowed(CampusServiceDefinition definition, String host) {
    final normalized = host.toLowerCase();
    return definition.hosts.any(
      (allowed) => allowed.toLowerCase() == normalized,
    );
  }

  static bool _domainAllowed(
    CampusServiceDefinition definition,
    String domain,
  ) {
    final normalized = domain.toLowerCase();
    return definition.hosts.any((allowed) {
      final host = allowed.toLowerCase();
      return host == normalized || host.endsWith('.$normalized');
    });
  }

  static bool _pathAllowed(CampusServiceDefinition definition, String path) {
    for (final prefix in definition.allowedPaths) {
      if (prefix == '/') return true;
      final normalized =
          prefix.endsWith('/')
              ? prefix.substring(0, prefix.length - 1)
              : prefix;
      if (path == normalized || path.startsWith('$normalized/')) return true;
    }
    return false;
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    if (cookiePath == '/') return true;
    if (requestPath == cookiePath) return true;
    return requestPath.startsWith(cookiePath) &&
        (cookiePath.endsWith('/') ||
            requestPath.length > cookiePath.length &&
                requestPath[cookiePath.length] == '/');
  }

  static bool _isValidWebViewSessionUri(
    CampusServiceDefinition definition,
    Uri uri,
  ) {
    if (FederatedSession.isIdentityLoginUri(uri)) return false;
    if (definition.webViewUsesSessionUri) {
      final parameter = definition.sessionMaterializer.tokenFromRedirect;
      return definition.allowsUri(uri) &&
          parameter != null &&
          (uri.queryParameters[parameter.queryParameter]?.isNotEmpty ?? false);
    }
    final value = uri.toString();
    return value.contains('caslogin') && value.contains('userToken');
  }

  static List<CampusWebViewCookieSeed> _cookieSeedsForHeader(
    Uri entryUri,
    String cookieHeader,
  ) {
    if (cookieHeader.isEmpty) return const [];
    return [
      for (final entry
          in PersistentCampusCookieJar.parseCookieHeader(cookieHeader).entries)
        if (entry.key.isNotEmpty && entry.value.isNotEmpty)
          CampusWebViewCookieSeed(
            name: entry.key,
            value: entry.value,
            domain: entryUri.host,
            hostOnly: true,
            path: '/',
            expires: null,
            secure: entryUri.scheme.toLowerCase() == 'https',
            httpOnly: false,
            sameSite: null,
          ),
    ];
  }

  static String _seedUrl(CampusWebViewCookieSeed cookie, Uri entryUri) {
    final domain = cookie.domain.toLowerCase();
    final entryHost = entryUri.host.toLowerCase();
    final entryHostBelongsToDomain =
        entryHost == domain || entryHost.endsWith('.$domain');
    // A host-only cookie must be written against its own host. For a domain
    // cookie, use the concrete service host whenever it belongs to that
    // domain; Android WebView rejects some otherwise valid writes when the
    // URL itself is the parent domain. Identity cookies on a sibling host
    // still use their own domain as the target.
    final host =
        cookie.hostOnly || !entryHostBelongsToDomain ? domain : entryUri.host;
    final scheme =
        cookie.secure || _isIdentityHost(host)
            ? 'https'
            : (entryUri.scheme.isEmpty ? 'https' : entryUri.scheme);
    final port =
        host.toLowerCase() == entryHost && entryUri.hasPort
            ? entryUri.port
            : null;
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: cookie.path,
    ).toString();
  }

  static bool _isIdentityHost(String host) =>
      host.toLowerCase() == 'ids.chd.edu.cn' ||
      host.toLowerCase() == 'identity.chd.edu.cn';
}

class _WebViewCookieMutation {
  const _WebViewCookieMutation({
    required this.url,
    required this.cookie,
    required this.previous,
  });

  final Uri url;
  final CampusWebViewCookieSeed cookie;
  final CampusWebViewCookieSeed? previous;
}
