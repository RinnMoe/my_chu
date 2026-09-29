import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../capabilities/account_scoped_cache.dart';
import '../models/account.dart';
import 'account_network_session_service.dart';
import 'auth_service.dart';
import 'campus_session_store.dart';
import 'identity_silent_login_service.dart';
import 'logger_service.dart';
import 'login_required_notifier.dart';
import 'mobile_campus_request_signer.dart';
import 'federated_session.dart';
import 'network_self_service_auth_service.dart';
import 'persistent_campus_cookie_jar.dart';
import 'scoped_cookie_jar.dart';
import 'session_artifact_store.dart';
import 'session_materialization.dart';
import 'session_runtime_fence.dart';
import 'service_endpoints.dart';

class CampusServiceSession {
  final String cookieHeader;
  final Map<String, String> headers;

  /// 会话 URL 型服务的播种入口：认证 WebView 打开该短时地址后由服务端或
  /// 平台 SPA 完成登录。凭证值只停留在共享会话和宿主 WebView 桥内。
  final Uri? sessionUri;
  final MaterializationRevisionStamp? materializationStamp;

  const CampusServiceSession({
    required this.cookieHeader,
    this.headers = const {},
    this.sessionUri,
    this.materializationStamp,
  });

  CampusServiceSession withMaterializationStamp(
    MaterializationRevisionStamp stamp,
  ) => CampusServiceSession(
    cookieHeader: cookieHeader,
    headers: headers,
    sessionUri: sessionUri,
    materializationStamp: stamp,
  );
}

/// A short-lived, account-scoped projection for an authenticated WebView.
///
/// The WebView host may materialize this lease, but it must not acquire a
/// second credential independently. The fence remains valid only for the
/// account/session/service scope captured by the shared broker.
class CampusServiceWebViewSessionLease {
  final String accountKey;
  final CampusServiceId serviceId;
  final CampusServiceSession session;
  final SessionRuntimeFence fence;
  final WebViewMaterializationFence materializationFence;
  final int sessionRevision;

  const CampusServiceWebViewSessionLease({
    required this.accountKey,
    required this.serviceId,
    required this.session,
    required this.fence,
    required this.materializationFence,
    required this.sessionRevision,
  });
}

enum _CampusServiceWebViewAcquisitionFailure {
  none,
  noSession,
  cooldown,
  staleGeneration,
  materializationChanged,
  accountChanged,
}

class _CampusServiceWebViewAcquisition {
  final CampusServiceWebViewSessionLease? lease;
  final _CampusServiceWebViewAcquisitionFailure failure;

  const _CampusServiceWebViewAcquisition({
    required this.lease,
    required this.failure,
  });

  bool get succeeded =>
      lease != null && failure == _CampusServiceWebViewAcquisitionFailure.none;
}

class _CredentialPersistenceResult {
  const _CredentialPersistenceResult({required this.committed, this.stamp});

  final bool committed;
  final MaterializationRevisionStamp? stamp;
}

/// Signals that a service generation changed while a WebView lease was being
/// acquired. The caller may perform one bounded fresh acquisition, but must
/// never materialize the stale session with a newer fence.
class CampusServiceWebViewSessionStaleException extends StateError {
  final CampusServiceId serviceId;

  CampusServiceWebViewSessionStaleException(this.serviceId)
    : super('认证 WebView 服务会话在换取期间已失效 (${serviceId.value})');
}

typedef CampusServiceExchangeOverride =
    Future<(CampusServiceSession?, bool)> Function(
      Account account,
      CampusServiceDefinition definition,
      String authCookies,
    );

enum SessionInvalidationReason { authFailure, identityChanged, explicitRefresh }

/// Central credential broker used by application features and plugins.
///
/// Apps request a credential for a target service and never need to know
/// how CAS redirects, cookie scoping, persistence, or concurrent refreshes are
/// implemented.
class CampusSessionService {
  static const _connectionTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 12);
  static const _exchangeCooldown = Duration(minutes: 5);
  static const _serviceExchangeCooldown = Duration(minutes: 2);

  static final Map<String, Future<(CampusServiceSession?, bool)>> _refreshes =
      {};
  static final Map<String, Future<(CampusServiceSession?, bool)>>
  _serviceRefreshes = {};

  /// Test seam for exercising guarded service persistence and exact WebView
  /// exchange paths without depending on a live campus endpoint. The returned
  /// session still flows through the production fence and Store mutation when
  /// the regular service path is used.
  @visibleForTesting
  static CampusServiceExchangeOverride? exchangeOverride;

  /// Test seam for switching the active account immediately before a WebView
  /// acquisition reads it. Production callers leave this unset.
  @visibleForTesting
  static Future<void> Function()? beforeWebViewAccountReadOverride;

  /// 最近一次成功换取凭证的时间（key = accountKey:target）。EAMS 等服务在
  /// 换票链结束后会短暂限流，紧接其后的首个数据请求常被服务端主动断开；
  /// 上层据此在换票后留出风控间隔再发数据请求。
  static final Map<String, DateTime> _lastExchangeAt = {};
  static final AccountScopedBackoff _exchangeCooldowns = AccountScopedBackoff(
    duration: _exchangeCooldown,
  );
  static final AccountScopedBackoff _serviceExchangeCooldowns =
      AccountScopedBackoff(duration: _serviceExchangeCooldown);

  /// Drops one service's persisted and in-memory credential scope. This must
  /// happen before retrying an authentication failure; otherwise a failed
  /// refresh can be followed by another request reusing the stale Account
  /// field.
  static Future<void> invalidate(
    CampusServiceId serviceId, {
    String? accountKey,
    Uri? serviceUri,
    SessionInvalidationReason reason =
        SessionInvalidationReason.explicitRefresh,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null ||
        (accountKey != null && account.accountKey != accountKey)) {
      return;
    }
    final effectiveKey = account.accountKey;
    final sessionRevision = AuthService.sessionRevision;
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    final scopedScope =
        serviceUri == null ? null : definition?.scopeFor(serviceUri);
    final isScopedServiceSession =
        definition != null &&
        scopedScope != null &&
        scopedScope.key != definition.sessionScope.key;
    final scopedPath =
        isScopedServiceSession && scopedScope is PathPrefixSessionScope
            ? scopedScope.prefix
            : null;
    if (isScopedServiceSession && scopedPath == null) return;
    final generationScope =
        scopedPath == null
            ? definition?.sessionScope ?? const ServiceSessionScope()
            : PathPrefixSessionScope(scopedPath);
    ServiceGenerationRegistry.bump(
      accountKey: effectiveKey,
      serviceId: definition?.id ?? serviceId,
      scopeKey: generationScope.key,
    );
    final credentialKey = '$effectiveKey:${serviceId.value}';
    if (serviceId == CampusServices.networkSelfService) {
      NetworkSelfServiceAuthService.clearAccount(effectiveKey);
    }
    _refreshes.removeWhere((key, _) => key.startsWith('$credentialKey:'));
    if (serviceUri != null && isScopedServiceSession) {
      if (AuthService.sessionRevision != sessionRevision) return;
      final scopePath = scopedPath;
      if (scopePath == null) return;
      AccountNetworkSessionService.clearScoped(
        effectiveKey,
        serviceUri,
        scopePath,
      );
      final store = await CampusSessionStore.open(accountKey: effectiveKey);
      await store.invalidateService(
        serviceId: definition.id,
        scope: PathPrefixSessionScope(scopePath),
      );
      final serviceKey = '$effectiveKey:${_serviceKey(serviceUri)}';
      _serviceRefreshes.removeWhere((key, _) => key.startsWith('$serviceKey:'));
      _serviceExchangeCooldowns.clear(serviceKey);
    } else if (!(definition?.rootIdentity ?? false)) {
      if (AuthService.sessionRevision != sessionRevision) return;
      AccountNetworkSessionService.clearServiceSession(effectiveKey, serviceId);
      final store = await CampusSessionStore.open(accountKey: effectiveKey);
      await store.invalidateService(
        serviceId: definition?.id ?? serviceId,
        scope: definition?.sessionScope ?? const ServiceSessionScope(),
      );
      _exchangeCooldowns.clear('$effectiveKey:${serviceId.value}');
    }
    _lastExchangeAt.remove('$effectiveKey:${serviceId.value}');
    AppLogger.info('${serviceId.value} 会话已失效并清理 (${reason.name})');
  }

  static Future<CampusServiceSession?> get(
    CampusServiceId serviceId, {
    bool forceRefresh = false,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) return null;
    var sessionRevision = AuthService.sessionRevision;
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (definition == null) return null;
    var store = await CampusSessionStore.open(accountKey: account.accountKey);
    var fence = _captureServiceFence(
      store: store,
      definition: definition,
      sessionRevision: sessionRevision,
    );
    final usesSavedIdentityPassword =
        definition.authentication is SavedIdentityPasswordAuthentication;
    final storeCached = await _cachedFromSessionStore(
      account.accountKey,
      serviceId,
    );
    if (!forceRefresh &&
        AuthService.sessionRevision == sessionRevision &&
        storeCached != null &&
        (storeCached.cookieHeader.isNotEmpty ||
            storeCached.headers.isNotEmpty)) {
      return storeCached;
    }
    if (serviceId == CampusServices.unifiedIdentity) {
      if (storeCached != null) return storeCached;
      if (!await _recoverIdentitySession(account.accountKey)) return null;
      final recoveredAccount = await AuthService.getCurrentAccount();
      if (recoveredAccount == null ||
          recoveredAccount.accountKey != account.accountKey) {
        return null;
      }
      return _cachedFromSessionStore(recoveredAccount.accountKey, serviceId);
    }

    final key = '${account.accountKey}:${serviceId.value}';
    final flightKey = '$key:${fence.fingerprint}';
    if (!forceRefresh &&
        !usesSavedIdentityPassword &&
        _exchangeCooldowns.isBlocked(key)) {
      return null;
    }
    final pending = _refreshes[flightKey];
    if (pending != null) return (await pending).$1;

    final refresh = _refresh(account, serviceId, fence: fence);
    _refreshes[flightKey] = refresh;
    try {
      var (credential, authExpired) = await refresh;
      // 换票失败且统一身份会话已过期：优先用已保存账号密码静默重登，
      // 成功后重跑一次目标服务换票；失败由宿主引导手动重新登录。
      if (credential == null && authExpired) {
        if (await _recoverIdentitySession(account.accountKey)) {
          sessionRevision = AuthService.sessionRevision;
          final recovered = await AuthService.getCurrentAccount();
          if (recovered != null && recovered.accountKey == account.accountKey) {
            store = await CampusSessionStore.open(
              accountKey: recovered.accountKey,
            );
            fence = _captureServiceFence(
              store: store,
              definition: definition,
              sessionRevision: sessionRevision,
            );
            (credential, authExpired) = await _refresh(
              recovered,
              serviceId,
              fence: fence,
            );
          }
        }
      }
      if (credential != null) {
        _exchangeCooldowns.clear(key);
        _lastExchangeAt[key] = DateTime.now();
        final latest = await AuthService.getCurrentAccount();
        if (latest == null ||
            latest.accountKey != account.accountKey ||
            !fence.isCurrent(
              currentAccountKey: latest.accountKey,
              currentSessionRevision: AuthService.sessionRevision,
            )) {
          return null;
        }
      } else if (!usesSavedIdentityPassword && !authExpired) {
        _exchangeCooldowns.recordFailure(key);
      }
      return credential;
    } finally {
      if (identical(_refreshes[flightKey], refresh)) {
        _refreshes.remove(flightKey);
      }
    }
  }

  /// 最近一次成功换取目标服务凭证的时间；未换过或换票失败时返回 null。
  static DateTime? lastSuccessfulExchangeAt(
    String accountKey,
    CampusServiceId serviceId,
  ) => _lastExchangeAt['$accountKey:${serviceId.value}'];

  static SessionRuntimeFence _captureServiceFence({
    required CampusSessionStore store,
    required CampusServiceDefinition definition,
    required int sessionRevision,
  }) {
    final scopeKey = definition
        .scopeFor(definition.seedUri)
        .keyFor(definition.seedUri);
    return store.captureFence(
      serviceId: definition.id,
      scopeKey: scopeKey,
      sessionRevision: sessionRevision,
      additionalScopeKeys: definition.sessionScopeKeys,
    );
  }

  /// Acquires the same account/service session used by API clients and turns
  /// it into a fenced WebView lease. WebView callers never run a separate
  /// CAS/OIDC exchange, so concurrent API and WebView consumers share the
  /// existing single-flight and runtime-fence checks.
  static Future<CampusServiceWebViewSessionLease?> acquireForWebView({
    required CampusServiceDefinition definition,
    required Uri entryUri,
    bool forceRefresh = false,
    String? expectedAccountKey,
  }) async {
    if (!definition.allowsUri(entryUri)) {
      throw ArgumentError.value(entryUri, 'entryUri', '不属于声明的服务范围');
    }
    final beforeAccountRead = beforeWebViewAccountReadOverride;
    if (beforeAccountRead != null) await beforeAccountRead();
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      if (expectedAccountKey != null) {
        throw StateError('认证 WebView 会话的账号已切换');
      }
      return null;
    }
    if (expectedAccountKey != null &&
        account.accountKey != expectedAccountKey) {
      throw StateError('认证 WebView 会话的账号已切换');
    }

    final exchangeUri =
        definition.usesExactExchangeFor(entryUri)
            ? entryUri
            : definition.startUri;
    final serviceKey = '${account.accountKey}:${definition.id.value}';
    final cooldownKey =
        definition.usesExactExchangeFor(entryUri)
            ? '${account.accountKey}:${_serviceKey(exchangeUri)}'
            : serviceKey;

    Future<CampusServiceSession?> acquire(bool forced) {
      if (definition.usesExactExchangeFor(entryUri)) {
        return _exchangeServiceSessionForDefinition(
          exchangeUri,
          label: '认证 WebView ${definition.id.value}',
          forceRefresh: forced,
          definitionOverride: definition,
        );
      }
      return get(
        definition.id,
        forceRefresh: forced || definition.webViewUsesSessionUri,
      );
    }

    var acquisition = await _acquireForWebViewAttempt(
      account: account,
      definition: definition,
      exchangeUri: exchangeUri,
      cooldownKey: cooldownKey,
      acquire: acquire,
      forceRefresh: forceRefresh,
    );
    if (acquisition.failure ==
            _CampusServiceWebViewAcquisitionFailure.staleGeneration &&
        !forceRefresh) {
      acquisition = await _acquireForWebViewAttempt(
        account: account,
        definition: definition,
        exchangeUri: exchangeUri,
        cooldownKey: cooldownKey,
        acquire: acquire,
        forceRefresh: true,
      );
    }
    if (acquisition.failure ==
            _CampusServiceWebViewAcquisitionFailure.materializationChanged &&
        !forceRefresh) {
      // The first attempt may have produced a fresh Store value itself. A
      // second non-forced read reuses that stable value; it never wraps the
      // discarded session in a newer fence.
      acquisition = await _acquireForWebViewAttempt(
        account: account,
        definition: definition,
        exchangeUri: exchangeUri,
        cooldownKey: cooldownKey,
        acquire: acquire,
        forceRefresh: false,
      );
    }
    if (acquisition.failure ==
            _CampusServiceWebViewAcquisitionFailure.staleGeneration ||
        acquisition.failure ==
            _CampusServiceWebViewAcquisitionFailure.materializationChanged) {
      throw CampusServiceWebViewSessionStaleException(definition.id);
    }
    if (!acquisition.succeeded) return null;
    return acquisition.lease;
  }

  static Future<_CampusServiceWebViewAcquisition> _acquireForWebViewAttempt({
    required Account account,
    required CampusServiceDefinition definition,
    required Uri exchangeUri,
    required String cooldownKey,
    required Future<CampusServiceSession?> Function(bool forceRefresh) acquire,
    required bool forceRefresh,
  }) async {
    final scopeKey = definition.scopeFor(exchangeUri).keyFor(exchangeUri);
    final beforeStore = await CampusSessionStore.open(
      accountKey: account.accountKey,
    );
    final runtimeFenceBefore = beforeStore.captureFence(
      serviceId: definition.id,
      scopeKey: scopeKey,
      sessionRevision: AuthService.sessionRevision,
      additionalScopeKeys: definition.sessionScopeKeys,
    );
    final materializationBefore = await beforeStore.captureWebViewFence(
      serviceId: definition.id,
      sessionRevision: runtimeFenceBefore.sessionRevision,
    );
    final session = await acquire(forceRefresh);
    final revisionAfterAcquire = AuthService.sessionRevision;
    final afterAcquireStore = await CampusSessionStore.open(
      accountKey: account.accountKey,
    );
    final runtimeFenceAfterAcquire = afterAcquireStore.captureFence(
      serviceId: definition.id,
      scopeKey: scopeKey,
      sessionRevision: revisionAfterAcquire,
      additionalScopeKeys: definition.sessionScopeKeys,
    );
    if (!runtimeFenceBefore.hasSameServiceGenerations(
      runtimeFenceAfterAcquire,
    )) {
      return const _CampusServiceWebViewAcquisition(
        lease: null,
        failure: _CampusServiceWebViewAcquisitionFailure.staleGeneration,
      );
    }
    // Service acquisition may legitimately advance the revision while
    // silently restoring the same account's expired identity session. Capture
    // the revision immediately after acquisition so only a later drift is
    // rejected while the lease fence is being assembled.
    if (session == null) {
      final cooldownBlocked =
          !forceRefresh &&
          (definition.usesExactExchangeFor(exchangeUri)
              ? _serviceExchangeCooldowns.isBlocked(cooldownKey)
              : _exchangeCooldowns.isBlocked(cooldownKey));
      return _CampusServiceWebViewAcquisition(
        lease: null,
        failure:
            cooldownBlocked
                ? _CampusServiceWebViewAcquisitionFailure.cooldown
                : _CampusServiceWebViewAcquisitionFailure.noSession,
      );
    }

    final latest = await AuthService.getCurrentAccount();
    if (latest == null || latest.accountKey != account.accountKey) {
      return const _CampusServiceWebViewAcquisition(
        lease: null,
        failure: _CampusServiceWebViewAcquisitionFailure.accountChanged,
      );
    }
    final store = await CampusSessionStore.open(accountKey: latest.accountKey);
    if (AuthService.sessionRevision != revisionAfterAcquire) {
      return const _CampusServiceWebViewAcquisition(
        lease: null,
        failure: _CampusServiceWebViewAcquisitionFailure.accountChanged,
      );
    }
    final materializationFence = await store.captureWebViewFence(
      serviceId: definition.id,
      sessionRevision: revisionAfterAcquire,
    );
    final sessionStamp = session.materializationStamp;
    if (sessionStamp != null
        ? !sessionStamp.matches(materializationFence)
        : !materializationBefore.hasSameMaterialization(materializationFence)) {
      return const _CampusServiceWebViewAcquisition(
        lease: null,
        failure: _CampusServiceWebViewAcquisitionFailure.materializationChanged,
      );
    }
    final fence = store.captureFence(
      serviceId: definition.id,
      scopeKey: scopeKey,
      sessionRevision: revisionAfterAcquire,
      additionalScopeKeys: definition.sessionScopeKeys,
    );
    return _CampusServiceWebViewAcquisition(
      lease: CampusServiceWebViewSessionLease(
        accountKey: latest.accountKey,
        serviceId: definition.id,
        session: session,
        fence: fence,
        materializationFence: materializationFence,
        sessionRevision: revisionAfterAcquire,
      ),
      failure: _CampusServiceWebViewAcquisitionFailure.none,
    );
  }

  /// Materialized session projection. The source of truth is the account-scoped
  /// session store; header names and prefixes are derived from the service
  /// materializer at read time.
  static Future<CampusServiceSession?> _cachedFromSessionStore(
    String accountKey,
    CampusServiceId serviceId,
  ) async {
    final store = await CampusSessionStore.open(accountKey: accountKey);
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (definition == null) return null;
    if (definition.sessionMaterializer.containsWebViewSessionMaterializer) {
      return null;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final before = await store.captureWebViewFence(
        serviceId: serviceId,
        sessionRevision: AuthService.sessionRevision,
      );
      CampusServiceSession? session;
      if (serviceId == CampusServices.unifiedIdentity) {
        final cookies = await store.rootCookieHeader();
        if (cookies.isNotEmpty) {
          session = CampusServiceSession(cookieHeader: cookies);
        }
      } else if (definition.sessionMaterializer case CustomPostSsoBootstrap(
        :final bootstrapId,
      )) {
        final artifact = await store.artifacts.read(bootstrapId);
        if (artifact != null) {
          session = CampusServiceSession(
            cookieHeader: '',
            headers: {'token': artifact.rawValue},
          );
        }
      } else {
        final jar = store.cookieJar(
          definition.id,
          scope: definition.scopeFor(definition.seedUri),
        );
        final cookies = await jar.headerFor(definition.seedUri);
        final headers = await _storeMaterializedHeaders(store, definition, jar);
        if (_hasCompleteMaterialization(definition, cookies, headers)) {
          session = CampusServiceSession(
            cookieHeader: cookies,
            headers: headers,
          );
        }
      }
      if (session == null) return null;
      final after = await store.captureWebViewFence(
        serviceId: serviceId,
        sessionRevision: AuthService.sessionRevision,
      );
      if (!before.hasSameMaterialization(after)) continue;
      return session.withMaterializationStamp(
        MaterializationRevisionStamp(
          rootRevision: after.rootRevision,
          serviceRevision: after.serviceRevision,
        ),
      );
    }
    return null;
  }

  static bool _hasCompleteMaterialization(
    CampusServiceDefinition definition,
    String cookies,
    Map<String, String> headers,
  ) {
    bool visit(SessionMaterializer materializer) {
      return switch (materializer) {
        CookieMaterializer() => cookies.isNotEmpty,
        HeaderFromCookie(:final headerName) =>
          headers[headerName]?.isNotEmpty ?? false,
        TokenFromRedirect(:final headerName) =>
          headers[headerName]?.isNotEmpty ?? false,
        CompositeMaterializer(:final materializers) => materializers.every(
          visit,
        ),
        WebViewSessionMaterializer() || CustomPostSsoBootstrap() => true,
      };
    }

    return visit(definition.sessionMaterializer);
  }

  static Future<Map<String, String>> _storeMaterializedHeaders(
    CampusSessionStore store,
    CampusServiceDefinition definition,
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
          final cookies = await jar.cookiesFor(definition.seedUri);
          final value =
              cookies
                  .where((cookie) => cookie.name == cookieName)
                  .map((cookie) => cookie.value)
                  .firstOrNull ??
              (fallbackCookieName == null
                  ? null
                  : cookies
                      .where((cookie) => cookie.name == fallbackCookieName)
                      .map((cookie) => cookie.value)
                      .firstOrNull);
          if (value != null && value.isNotEmpty) headers[headerName] = value;
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

  static Future<(CampusServiceSession?, bool)> _refresh(
    Account account,
    CampusServiceId serviceId, {
    required SessionRuntimeFence fence,
  }) async {
    final store = await CampusSessionStore.open(accountKey: account.accountKey);
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (definition == null) return (null, false);

    if (definition.authentication case SavedIdentityPasswordAuthentication()) {
      final local = await NetworkSelfServiceAuthService.acquire(
        account,
        fence: fence,
      );
      if (local == null || !_credentialFenceIsCurrent(fence, store)) {
        return (null, false);
      }
      final session = CampusServiceSession(cookieHeader: local.cookieHeader);
      final committed = await _persistCredentialInSessionStore(
        store: store,
        serviceId: serviceId,
        session: session,
        fence: fence,
      );
      if (!committed.committed) return (null, false);
      AppLogger.info('${serviceId.value} 本地服务会话已建立并保存');
      return (
        committed.stamp == null
            ? session
            : session.withMaterializationStamp(committed.stamp!),
        false,
      );
    }

    final storedAuthCookies = await store.rootCookieHeader();
    final authCookies = storedAuthCookies;
    if (authCookies.isEmpty) return (null, true);
    final materializer = definition.sessionMaterializer;
    if (materializer case CustomPostSsoBootstrap()) {
      final (CampusServiceSession? credential, bool authExpired) =
          exchangeOverride != null
              ? await exchangeOverride!(account, definition, authCookies)
              : await _exchangeMobileCampusCredential(account, fence: fence);
      if (credential == null) return (null, authExpired);
      final token = credential.headers['token'];
      if (token == null || token.isEmpty) return (null, false);
      if (!_credentialFenceIsCurrent(fence, store)) {
        return (null, false);
      }
      final committed = await _persistCredentialInSessionStore(
        store: store,
        serviceId: serviceId,
        session: credential,
        fence: fence,
      );
      if (!committed.committed) return (null, false);
      AppLogger.info('移动校园 token 已换取并保存');
      return (
        committed.stamp == null
            ? credential
            : credential.withMaterializationStamp(committed.stamp!),
        false,
      );
    }

    final (CampusServiceSession? session, bool authExpired) =
        exchangeOverride != null
            ? await exchangeOverride!(account, definition, authCookies)
            : materializer.containsWebViewSessionMaterializer
            ? await _exchangeQualityAssuranceSession(authCookies)
            : await _exchangeFederatedSessionWithState(definition, authCookies);
    if (session == null) return (null, authExpired);

    if (materializer.containsWebViewSessionMaterializer) {
      // 会话 URL 型服务不写入账号持久化字段，仅靠单飞与失败冷却去重；
      // 每次打开认证 WebView 都会换取新的 caslogin userToken 入口。
      if (!_credentialFenceIsCurrent(fence, store)) {
        return (null, false);
      }
      final mutation = await store.beginServiceMaterializationMutation(
        serviceId,
      );
      var ended = false;
      final rootRevision = SessionMaterializationRegistry.currentRootRevision(
        account.accountKey,
      );
      try {
        final result = await mutation.end(commit: true);
        ended = true;
        return (
          session.withMaterializationStamp(
            MaterializationRevisionStamp(
              rootRevision: rootRevision,
              serviceRevision:
                  result.revisions[SessionMaterializationRegistry.serviceKey(
                    account.accountKey,
                    serviceId,
                  )]!,
            ),
          ),
          false,
        );
      } finally {
        if (!ended) await mutation.end(commit: false);
      }
    }

    if (!_credentialFenceIsCurrent(fence, store)) {
      return (null, false);
    }

    final committed = await _persistCredentialInSessionStore(
      store: store,
      serviceId: serviceId,
      session: session,
      fence: fence,
    );
    if (!committed.committed) return (null, false);
    AppLogger.info('${serviceId.value} 服务会话已换取并保存');
    return (
      committed.stamp == null
          ? session
          : session.withMaterializationStamp(committed.stamp!),
      false,
    );
  }

  static Future<_CredentialPersistenceResult> _persistCredentialInSessionStore({
    required CampusSessionStore store,
    required CampusServiceId serviceId,
    required CampusServiceSession session,
    required SessionRuntimeFence fence,
  }) async {
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (definition == null) {
      return const _CredentialPersistenceResult(committed: true);
    }
    if (definition.sessionMaterializer case CustomPostSsoBootstrap(
      :final bootstrapId,
    )) {
      final token = session.headers['token'];
      if (token == null || token.isEmpty) {
        return const _CredentialPersistenceResult(committed: true);
      }
      final mutation = await store.beginServiceMaterializationMutation(
        serviceId,
      );
      var ended = false;
      final rootRevision = SessionMaterializationRegistry.currentRootRevision(
        store.accountKey,
      );
      try {
        final committed = await store.artifacts.writeIfCurrent(
          TokenArtifact(
            serviceId: bootstrapId,
            rawValue: token,
            createdAt: DateTime.now().toUtc(),
            expiresAt: null,
            identityEpoch: store.identityEpoch,
          ),
          isCurrent: () => _credentialFenceIsCurrent(fence, store),
          verifyIdentityEpoch: true,
          mutation: mutation,
        );
        if (!committed) {
          await mutation.end(commit: false);
          ended = true;
          return const _CredentialPersistenceResult(committed: false);
        }
        final result = await mutation.end(commit: true);
        ended = true;
        return _CredentialPersistenceResult(
          committed: true,
          stamp: MaterializationRevisionStamp(
            rootRevision: rootRevision,
            serviceRevision:
                result.revisions[SessionMaterializationRegistry.serviceKey(
                  store.accountKey,
                  serviceId,
                )]!,
          ),
        );
      } finally {
        if (!ended) await mutation.end(commit: false);
      }
    }
    if (definition.sessionMaterializer.containsWebViewSessionMaterializer) {
      return const _CredentialPersistenceResult(committed: true);
    }
    final tokenMaterializer = definition.sessionMaterializer.tokenFromRedirect;
    final accessToken =
        tokenMaterializer == null
            ? null
            : _rawAccessToken(
              session.headers[tokenMaterializer.headerName],
              tokenMaterializer.prefix,
            );
    if (session.cookieHeader.isEmpty &&
        (accessToken == null || accessToken.isEmpty)) {
      return const _CredentialPersistenceResult(committed: true);
    }
    final mutation = await store.beginServiceMaterializationMutation(serviceId);
    var ended = false;
    final rootRevision = SessionMaterializationRegistry.currentRootRevision(
      store.accountKey,
    );
    try {
      if (session.cookieHeader.isNotEmpty) {
        final committed = await store
            .cookieJar(
              serviceId,
              scope: definition.scopeFor(definition.seedUri),
            )
            .seedCookieHeaderIfCurrent(
              definition.seedUri,
              session.cookieHeader,
              isCurrent: () => _credentialFenceIsCurrent(fence, store),
              verifyIdentityEpoch: true,
              mutation: mutation,
            );
        if (!committed) {
          await mutation.end(commit: false);
          ended = true;
          return const _CredentialPersistenceResult(committed: false);
        }
      }
      if (accessToken != null && accessToken.isNotEmpty) {
        final committed = await store.artifacts.writeIfCurrent(
          TokenArtifact(
            serviceId: serviceId,
            rawValue: accessToken,
            createdAt: DateTime.now().toUtc(),
            expiresAt: null,
            identityEpoch: store.identityEpoch,
          ),
          isCurrent: () => _credentialFenceIsCurrent(fence, store),
          verifyIdentityEpoch: true,
          mutation: mutation,
        );
        if (!committed) {
          await mutation.end(commit: false);
          ended = true;
          return const _CredentialPersistenceResult(committed: false);
        }
      }
      final result = await mutation.end(commit: true);
      ended = true;
      return _CredentialPersistenceResult(
        committed: true,
        stamp: MaterializationRevisionStamp(
          rootRevision: rootRevision,
          serviceRevision:
              result.revisions[SessionMaterializationRegistry.serviceKey(
                store.accountKey,
                serviceId,
              )]!,
        ),
      );
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  static bool _credentialFenceIsCurrent(
    SessionRuntimeFence fence,
    CampusSessionStore store,
  ) => fence.isCurrent(
    currentAccountKey: store.accountKey,
    currentSessionRevision: AuthService.sessionRevision,
  );

  /// 通用 federated 换票与 materializer 投影，附带“统一身份会话是否已过期”
  /// 的信号：换票链最终停留在 ids 登录页时 [bool] 为 true。
  static Future<(CampusServiceSession?, bool)>
  _exchangeFederatedSessionWithState(
    CampusServiceDefinition definition,
    String authCookies,
  ) async {
    final result = await _exchangeRedirects(
      definition.startUri,
      authCookies,
      CampusServiceEndpoints.labelFor(definition.id),
      definition: definition,
    );
    // A service can issue a preliminary session cookie before redirecting to
    // CAS. It is not an authenticated credential when the chain ultimately
    // stops at the unified-identity login page.
    if (result.endedAtIdsLogin) return (null, true);
    final cookies = result.jar.headerFor(definition.seedUri);
    final headers = _derivedHeaders(definition, result.jar, cookies);
    final tokenMaterializer = definition.sessionMaterializer.tokenFromRedirect;
    if (tokenMaterializer != null) {
      final tokenHeader = tokenMaterializer.headerValueFrom(result.finalUri);
      if (tokenHeader == null) {
        AppLogger.warn(
          '${CampusServiceEndpoints.labelFor(definition.id)} 未获取到访问令牌',
        );
        return (null, false);
      }
      headers[tokenMaterializer.headerName] = tokenHeader;
    }
    if (definition.sessionMaterializer.containsCookieMaterializer &&
        cookies.isEmpty) {
      return (null, false);
    }
    final session = CampusServiceSession(
      cookieHeader: cookies,
      headers: headers,
      sessionUri: definition.webViewUsesSessionUri ? result.finalUri : null,
    );
    if (!await _validateDefinition(
      definition,
      result.jar,
      cookies,
      headers: headers,
    )) {
      return (null, false);
    }
    return (session, false);
  }

  static String? _rawAccessToken(String? header, String prefix) {
    if (header == null || header.isEmpty) return null;
    return header.startsWith(prefix) ? header.substring(prefix.length) : header;
  }

  /// 评教系统（商鼎）会话 URL 换票（当前唯一不以“收 Cookie”收尾的服务）。
  ///
  /// 真实链路（2026-08 抓包确认）只有 3 跳，不再经过 jxjbztk/ztsjcj：
  /// `GET jxzlpj.chd.edu.cn:8080/api/manage/cas/toUrl?type=mobile` →
  /// ids CAS（`service=toUrl`）自动登录回带 ticket → `toUrl?ticket=ST-…`
  /// 校验后 302 到 `#/pages/login/caslogin?userToken=…&type=mobile`。
  /// userToken 由服务端签发，底层只跟随重定向并捕获最终 URL（含 fragment）
  /// 交给认证 WebView；SPA 再用 userToken 调 `cas/doLogin` 完成登录。
  static Future<(CampusServiceSession?, bool)> _exchangeQualityAssuranceSession(
    String authCookies,
  ) async {
    final definition = CampusServiceEndpoints.definitionFor(
      CampusServices.qualityAssurance,
    );
    if (definition == null) return (null, false);
    final result = await _exchangeRedirects(
      definition.startUri,
      authCookies,
      CampusServiceEndpoints.labelFor(definition.id),
      definition: definition,
    );
    final finalUri = result.finalUri;
    final url = finalUri?.toString() ?? '';
    if (!url.contains('caslogin') || !url.contains('userToken')) {
      AppLogger.warn('评教服务 CAS 入口校验失败');
      return (null, result.endedAtIdsLogin);
    }
    return (
      CampusServiceSession(
        cookieHeader: result.jar.headerFor(finalUri!),
        sessionUri: finalUri,
      ),
      false,
    );
  }

  /// 移动校园专用换票：统一身份移动授权 → WMA 登录 → SDK 校验 → skipLogin
  /// 换取业务 token。业务 API 不依赖 Cookie，只使用 `token` 请求头。
  static Future<(CampusServiceSession?, bool)> _exchangeMobileCampusCredential(
    Account account, {
    required SessionRuntimeFence fence,
  }) async {
    final store = await CampusSessionStore.open(accountKey: account.accountKey);
    final storedAuthCookies = await store.rootCookieHeader();
    final authCookies = storedAuthCookies;
    if (authCookies.isEmpty) return (null, false);
    final redirectResult = await _exchangeRedirects(
      CampusServiceEndpoints.idsMobileCallbackLoginUri,
      authCookies,
      '移动校园移动授权',
      definition: null,
    );
    if (redirectResult.endedAtIdsLogin) return (null, true);
    final mobileCode = mobileCampusCodeFrom(redirectResult.finalUri);
    if (mobileCode == null || mobileCode.isEmpty) {
      AppLogger.warn('移动校园移动授权未返回 mobile_code');
      return (null, false);
    }

    final client = _newClient();
    try {
      final wmaResponse = await _postMobileCampusForm(
        client,
        CampusServiceEndpoints.mobileCampusWmaLoginUri,
        {'mobileCode': mobileCode},
        '移动校园 WMA 登录',
      );
      if (wmaResponse == null) return (null, false);
      final appToken = wmaResponse['appToken'];
      if (appToken is! List || appToken.length != 2) {
        AppLogger.warn('移动校园 WMA 登录响应缺少 appToken');
        return (null, false);
      }
      final wmaToken = mobileCampusTokenFromParts(appToken);
      final verifyResponse = await _postMobileCampusJson(
        client,
        CampusServiceEndpoints.mobileCampusVerifyUri,
        MobileCampusRequestSigner.signedBody({
          'campusType': 1,
          'appKey': CampusServiceEndpoints.mobileCampusSdkAppKey,
          'appDomain': CampusServiceEndpoints.mobileCampusBase,
          'schoolId': CampusServiceEndpoints.mobileCampusSchoolId,
          'wxCode': null,
          'client': null,
          'openId': null,
        }),
        label: '移动校园 SDK 校验',
      );
      if (verifyResponse == null ||
          verifyResponse['isValid'] != true ||
          verifyResponse['msgState'] != 1) {
        AppLogger.warn('移动校园 SDK 校验未通过');
        return (null, false);
      }
      final uuId = await _mobileCampusUuId(account, fence: fence);
      if (uuId == null) return (null, false);

      final skipLoginBody = MobileCampusRequestSigner.signedBody({
        'campusType': 1,
        'uuId': uuId,
        'wxCode': null,
        'client': null,
        'openId': null,
      });
      final skipLoginResponse = await _postMobileCampusJson(
        client,
        CampusServiceEndpoints.mobileCampusSkipLoginUri,
        skipLoginBody,
        headers: {'token': wmaToken},
        label: '移动校园 skipLogin',
      );
      if (skipLoginResponse == null) return (null, false);
      final token = skipLoginResponse['token'];
      if (token is! List || token.length != 2) {
        AppLogger.warn('移动校园 skipLogin 响应缺少 token');
        return (null, false);
      }
      final joinedToken = mobileCampusTokenFromParts(token);
      if (joinedToken.isEmpty) return (null, false);
      final mobileUserId = mobileCampusUserIdFrom(skipLoginResponse);
      if (mobileUserId != null) {
        final updated = await AuthService.patchAccount(
          account.accountKey,
          (latest) => latest.copyWith(mobileCampusUserId: mobileUserId),
          expectedRevision: fence.sessionRevision,
        );
        if (updated == null) {
          AppLogger.warn('移动校园 userId 保存失败，用户资料接口将回退门户');
        }
      }
      return (
        CampusServiceSession(cookieHeader: '', headers: {'token': joinedToken}),
        false,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 移动授权最终可能把 `mobile_code` 放在 query，也可能放在
  /// `default.html#mobile_code=...` fragment（HAR 抓包实测）。
  @visibleForTesting
  static String? mobileCampusCodeFrom(Uri? uri) {
    if (uri == null) return null;
    final queryCode = uri.queryParameters['mobile_code'];
    if (queryCode != null && queryCode.isNotEmpty) return queryCode;
    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    final fragmentUri = Uri.tryParse('https://ids.chd.edu.cn/?$fragment');
    return fragmentUri?.queryParameters['mobile_code'];
  }

  /// skipLogin 成功响应中的 `userBaseInfo.userId`，供 `getUserInfo.do` 使用。
  @visibleForTesting
  static String? mobileCampusUserIdFrom(Object? response) {
    if (response is! Map) return null;
    final base = response['userBaseInfo'];
    if (base is! Map) return null;
    final value = base['userId']?.toString().trim() ?? '';
    final parsedUserId = int.tryParse(value);
    if (value.isEmpty || parsedUserId == null || parsedUserId <= 0) return null;
    return value;
  }

  static Future<String?> _mobileCampusUuId(
    Account account, {
    required SessionRuntimeFence fence,
  }) async {
    final existing = account.mobileCampusUuId;
    if (existing != null && RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    final generated =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final updated = await AuthService.patchAccount(
      account.accountKey,
      (latest) => latest.copyWith(mobileCampusUuId: generated),
      expectedRevision: fence.sessionRevision,
    );
    if (updated == null) return null;
    if (!fence.isCurrent(
      currentAccountKey: account.accountKey,
      currentSessionRevision: AuthService.sessionRevision,
    )) {
      return null;
    }
    return updated.mobileCampusUuId;
  }

  @visibleForTesting
  static String mobileCampusTokenFromParts(List<Object?> parts) =>
      parts.map((part) => part.toString()).join('_');

  static Future<Map<String, dynamic>?> _postMobileCampusForm(
    HttpClient client,
    Uri uri,
    Map<String, String> form,
    String label,
  ) async {
    try {
      final request = await client.postUrl(uri).timeout(_connectionTimeout);
      _setMobileCampusHeaders(request);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        form.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}='
                  '${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      );
      return await _readMobileCampusJson(request, label);
    } catch (error) {
      AppLogger.warn('$label 请求失败 (${error.runtimeType})');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _postMobileCampusJson(
    HttpClient client,
    Uri uri,
    Map<String, Object?> body, {
    Map<String, String>? headers,
    required String label,
  }) async {
    try {
      final request = await client.postUrl(uri).timeout(_connectionTimeout);
      _setMobileCampusHeaders(request);
      if (headers != null) {
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      return await _readMobileCampusJson(request, label);
    } catch (error) {
      AppLogger.warn('$label 请求失败 (${error.runtimeType})');
      return null;
    }
  }

  static void _setMobileCampusHeaders(HttpClientRequest request) {
    _setBrowserHeaders(request);
    request.headers.set('Origin', 'file://');
    request.headers.set('X-Requested-With', 'com.lantu.MobileCampus.chd');
  }

  static Future<Map<String, dynamic>?> _readMobileCampusJson(
    HttpClientRequest request,
    String label,
  ) async {
    try {
      final response = await request.close().timeout(_requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        AppLogger.warn('$label 返回 HTTP ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      AppLogger.warn('$label 响应超时');
      return null;
    } on HttpException {
      AppLogger.warn('$label 响应中断');
      return null;
    } on FormatException {
      AppLogger.warn('$label 返回非 JSON');
      return null;
    }
  }

  /// 按声明式定义的 [ValidationPolicy] 做会话校验。
  static Future<bool> _validateDefinition(
    CampusServiceDefinition definition,
    ScopedCookieJar jar,
    String cookies, {
    Map<String, String> headers = const <String, String>{},
  }) => _validatePolicy(
    definition.validationPolicy,
    definition,
    jar,
    cookies,
    headers: headers,
  );

  static Future<bool> _validatePolicy(
    ValidationPolicy policy,
    CampusServiceDefinition definition,
    ScopedCookieJar jar,
    String cookies, {
    required Map<String, String> headers,
  }) async {
    switch (policy) {
      case NoValidationPolicy():
        return true;
      case HttpStatusValidation():
        final validationUri = definition.validationUri;
        return validationUri == null
            ? true
            : _isGet200(validationUri, cookies, headers: headers);
      case CampusHomeValidation():
        final session = jar.valueFor(definition.seedUri, 'JWSESSION');
        if (session == null || session.isEmpty) return false;
        return _isCampusSessionValid(session);
      case CompositeValidationPolicy(:final policies):
        for (final child in policies) {
          if (!await _validatePolicy(
            child,
            definition,
            jar,
            cookies,
            headers: headers,
          )) {
            return false;
          }
        }
        return true;
    }
  }

  /// 解释声明式 [HeaderFromCookie] materializer，递归处理组合 materializer。
  static Map<String, String> _derivedHeaders(
    CampusServiceDefinition definition,
    ScopedCookieJar jar,
    String cookies,
  ) {
    final headers = <String, String>{};
    void visit(SessionMaterializer materializer) {
      switch (materializer) {
        case HeaderFromCookie(
          :final cookieName,
          :final fallbackCookieName,
          :final headerName,
        ):
          final value =
              jar.valueFor(definition.seedUri, cookieName) ??
              _cookieValue(cookies, cookieName) ??
              (fallbackCookieName == null
                  ? null
                  : jar.valueFor(definition.seedUri, fallbackCookieName) ??
                      _cookieValue(cookies, fallbackCookieName));
          if (value != null && value.isNotEmpty) headers[headerName] = value;
        case CompositeMaterializer(:final materializers):
          for (final child in materializers) {
            visit(child);
          }
        case CookieMaterializer():
        case TokenFromRedirect():
        case WebViewSessionMaterializer():
        case CustomPostSsoBootstrap():
          break;
      }
    }

    visit(definition.sessionMaterializer);
    return headers;
  }

  /// Exchanges the unified-identity session for a specific service URL.
  ///
  /// Some portal sub-applications have their own CAS service parameter, so a
  /// generic portal session alone is insufficient for their first API call.
  static Future<CampusServiceSession?> exchangeServiceSession(
    Uri serviceUri, {
    required String label,
    bool forceRefresh = false,
  }) => _exchangeServiceSessionForDefinition(
    serviceUri,
    label: label,
    forceRefresh: forceRefresh,
  );

  static Future<CampusServiceSession?> _exchangeServiceSessionForDefinition(
    Uri serviceUri, {
    required String label,
    bool forceRefresh = false,
    CampusServiceDefinition? definitionOverride,
  }) async {
    var account = await AuthService.getCurrentAccount();
    if (account == null) return null;
    var store = await CampusSessionStore.open(accountKey: account.accountKey);
    var storedAuthCookies = await store.rootCookieHeader();
    var authCookies = storedAuthCookies;
    if (authCookies.isEmpty) {
      if (!await _recoverIdentitySession(account.accountKey)) return null;
      final recoveredAccount = await AuthService.getCurrentAccount();
      if (recoveredAccount == null ||
          recoveredAccount.accountKey != account.accountKey) {
        return null;
      }
      account = recoveredAccount;
      store = await CampusSessionStore.open(accountKey: account.accountKey);
      storedAuthCookies = await store.rootCookieHeader();
      authCookies = storedAuthCookies;
      if (authCookies.isEmpty) return null;
    }

    var sessionRevision = AuthService.sessionRevision;
    final key = '${account.accountKey}:${_serviceKey(serviceUri)}';
    final serviceId = CampusServiceEndpoints.serviceIdForHost(serviceUri.host);
    final definition =
        definitionOverride ??
        (serviceId == null
            ? null
            : CampusServiceEndpoints.definitionFor(serviceId));
    final effectiveServiceId = definition?.id ?? serviceId;
    final exchangeServiceId =
        effectiveServiceId ??
        CampusServiceId('service:${_serviceKey(serviceUri)}');
    final exchangeScopeKey =
        definition?.scopeFor(serviceUri).keyFor(serviceUri) ?? 'service';
    var exchangeStore = store;
    var exchangeFence = exchangeStore.captureFence(
      serviceId: exchangeServiceId,
      scopeKey: exchangeScopeKey,
      sessionRevision: sessionRevision,
      additionalScopeKeys: definition?.sessionScopeKeys ?? const [],
    );
    final flightKey = '$key:${exchangeFence.fingerprint}';
    if (!forceRefresh && _serviceExchangeCooldowns.isBlocked(key)) return null;
    final pending = _serviceRefreshes[flightKey];
    if (pending != null) return (await pending).$1;

    final override = exchangeOverride;
    final refresh =
        override != null && definition != null
            ? override(account, definition, authCookies)
            : _exchangeServiceSession(
              account,
              authCookies,
              serviceUri,
              label,
              store: exchangeStore,
              fence: exchangeFence,
              definition: definition,
            );
    _serviceRefreshes[flightKey] = refresh;
    try {
      var (session, authExpired) = await refresh;
      // 精确服务换票失败且统一身份已过期：同样先静默重登再重跑一次。
      if (session == null && authExpired) {
        if (await _recoverIdentitySession(account.accountKey)) {
          sessionRevision = AuthService.sessionRevision;
          _serviceExchangeCooldowns.clear(key);
          final recovered = await AuthService.getCurrentAccount();
          if (recovered != null && recovered.accountKey == account.accountKey) {
            final recoveredStore = await CampusSessionStore.open(
              accountKey: recovered.accountKey,
            );
            final recoveredCookies = await recoveredStore.rootCookieHeader();
            if (recoveredCookies.isNotEmpty) {
              exchangeStore = recoveredStore;
              exchangeFence = recoveredStore.captureFence(
                serviceId: exchangeServiceId,
                scopeKey: exchangeScopeKey,
                sessionRevision: sessionRevision,
                additionalScopeKeys: definition?.sessionScopeKeys ?? const [],
              );
              (session, _) = await _exchangeServiceSession(
                recovered,
                recoveredCookies,
                serviceUri,
                label,
                store: exchangeStore,
                fence: exchangeFence,
                definition: definition,
              );
            }
          }
        }
      }
      if (session != null &&
          exchangeFence.isCurrent(
            currentAccountKey: account.accountKey,
            currentSessionRevision: AuthService.sessionRevision,
          )) {
        _serviceExchangeCooldowns.clear(key);
      } else {
        session = null;
        _serviceExchangeCooldowns.recordFailure(key);
      }
      return session;
    } catch (_) {
      _serviceExchangeCooldowns.recordFailure(key);
      rethrow;
    } finally {
      if (identical(_serviceRefreshes[flightKey], refresh)) {
        _serviceRefreshes.remove(flightKey);
      }
    }
  }

  static Future<(CampusServiceSession?, bool)> _exchangeServiceSession(
    Account account,
    String authCookies,
    Uri serviceUri,
    String label, {
    required CampusSessionStore store,
    required SessionRuntimeFence fence,
    required CampusServiceDefinition? definition,
  }) async {
    final result = await _exchangeRedirects(
      serviceUri,
      authCookies,
      label,
      definition: definition,
    );
    if (result.endedAtIdsLogin) return (null, true);
    final jar = result.jar;
    final cookies = jar.headerFor(serviceUri);
    if (cookies.isEmpty) return (null, false);
    final latest = await AuthService.getCurrentAccount();
    if (latest == null ||
        latest.accountKey != account.accountKey ||
        !_serviceFenceIsCurrent(fence, store)) {
      return (null, false);
    }
    if (definition != null) {
      final mutation = await store.beginServiceMaterializationMutation(
        definition.id,
      );
      var ended = false;
      final rootRevision = SessionMaterializationRegistry.currentRootRevision(
        store.accountKey,
      );
      try {
        final committed = await store
            .cookieJar(definition.id, scope: definition.scopeFor(serviceUri))
            .seedCookieHeaderIfCurrent(
              serviceUri,
              cookies,
              isCurrent: () => _serviceFenceIsCurrent(fence, store),
              verifyIdentityEpoch: true,
              mutation: mutation,
            );
        if (!committed) {
          await mutation.end(commit: false);
          ended = true;
          return (null, false);
        }
        final result = await mutation.end(commit: true);
        ended = true;
        return (
          CampusServiceSession(
            cookieHeader: cookies,
            materializationStamp: MaterializationRevisionStamp(
              rootRevision: rootRevision,
              serviceRevision:
                  result.revisions[SessionMaterializationRegistry.serviceKey(
                    store.accountKey,
                    definition.id,
                  )]!,
            ),
          ),
          false,
        );
      } finally {
        if (!ended) await mutation.end(commit: false);
      }
    }
    return (CampusServiceSession(cookieHeader: cookies), false);
  }

  static bool _serviceFenceIsCurrent(
    SessionRuntimeFence fence,
    CampusSessionStore store,
  ) => fence.isCurrent(
    currentAccountKey: store.accountKey,
    currentSessionRevision: AuthService.sessionRevision,
  );

  static String _serviceKey(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  static String? _cookieValue(String cookieHeader, String key) {
    return ScopedCookieJar.parseCookieHeader(cookieHeader)[key];
  }

  static Future<({ScopedCookieJar jar, Uri? finalUri, bool endedAtIdsLogin})>
  _exchangeRedirects(
    Uri startUri,
    String authCookies,
    String label, {
    CampusServiceDefinition? definition,
  }) async {
    final result = await FederatedSession.exchange(
      startUri: startUri,
      identityCookieHeader: authCookies,
      label: label,
      definition: definition,
    );
    return (
      jar: result.jar,
      finalUri: result.finalUri,
      endedAtIdsLogin: result.endedAtIdentityLogin,
    );
  }

  /// 统一身份会话缺失或过期后的静默恢复入口。
  ///
  /// 需要用户操作的结果会通知宿主引导手动登录；网络错误和恢复冷却是
  /// 暂时性失败，留给当前请求所属的模块稍后重试。
  static Future<bool> _recoverIdentitySession(String accountKey) async {
    final result = await IdentitySilentLoginService.tryRecover(
      accountKey: accountKey,
    );
    if (result.isSuccess) {
      _clearExchangeCooldownsFor(accountKey);
      return true;
    }
    switch (result.outcome) {
      case IdentityRecoveryOutcome.noSavedCredential:
      case IdentityRecoveryOutcome.captchaRequired:
      case IdentityRecoveryOutcome.invalidCredential:
        LoginRequiredNotifier.requestRelogin(result.outcome.name);
      case IdentityRecoveryOutcome.success:
      case IdentityRecoveryOutcome.networkError:
      case IdentityRecoveryOutcome.coolingDown:
        break;
    }
    return false;
  }

  /// 静默重登成功后清除该账号的换票冷却，让各服务立刻重新换票。
  static void _clearExchangeCooldownsFor(String accountKey) {
    for (final serviceId in CampusServices.all) {
      _exchangeCooldowns.clear('$accountKey:${serviceId.value}');
      _lastExchangeAt.remove('$accountKey:${serviceId.value}');
    }
    _serviceExchangeCooldowns.clearWhere(
      (key) => key.startsWith('$accountKey:'),
    );
  }

  static Future<bool> _isGet200(
    Uri uri,
    String cookies, {
    Map<String, String> headers = const {},
  }) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      if (cookies.isNotEmpty) request.headers.set('Cookie', cookies);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      _setBrowserHeaders(request);
      request.followRedirects = false;
      final response = await request.close().timeout(_requestTimeout);
      await _drainExchangeResponse(response, '会话校验');
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Redirect exchanges only need response headers: Set-Cookie and Location.
  /// Some legacy servers close the body stream after returning those headers.
  /// Treat that as a completed exchange and let the following validation or
  /// request decide whether the resulting session is usable.
  static Future<void> _drainExchangeResponse(
    HttpClientResponse response,
    String label,
  ) async {
    try {
      await response.drain<void>().timeout(_requestTimeout);
    } on HttpException catch (error) {
      AppLogger.warn('$label SSO 响应提前关闭，继续使用已获取的会话信息 (${error.runtimeType})');
    } on TimeoutException {
      AppLogger.warn('$label SSO 响应读取超时，继续使用已获取的会话信息');
    }
  }

  static Future<bool> _isCampusSessionValid(String session) async {
    final client = _newClient();
    try {
      final request = await client.postUrl(
        CampusServiceEndpoints.campusHomeAppsUri,
      );
      request.headers.set('Cookie', 'JWSESSION=$session');
      request.headers.set('JWSESSION', session);
      request.headers.contentType = ContentType.json;
      request.write('{}');
      final response = await request.close().timeout(_requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) return false;
      final json = jsonDecode(body);
      if (json is! Map) return false;
      final data = json['data'];
      final home =
          data is List
              ? data
              : data is Map
              ? data['home']
              : null;
      return json['code'] == 0 && home is List && home.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static HttpClient _newClient() {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    // 校园内网服务（如 jxzlpj:8080 的评教入口）证书链可能不在系统信任库，
    // 仅对 *.chd.edu.cn 主机放行证书校验；其余主机保持系统默认严格校验。
    client.badCertificateCallback =
        (certificate, host, port) => CampusServiceEndpoints.isChdHost(host);
    return client;
  }

  static void _setBrowserHeaders(HttpClientRequest request) {
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.6778.200 Mobile Safari/537.36',
    );
    request.headers.set('Accept', 'application/json, text/plain, */*');
    request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
    request.headers.set('Referer', '${CampusServiceEndpoints.idsAuthBase}/');
  }
}
