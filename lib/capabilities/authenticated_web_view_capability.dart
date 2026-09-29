import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_service.dart';
import '../services/campus_service_session_service.dart';
import '../services/error_feedback_service.dart';
import '../services/federated_session.dart';
import '../services/logger_service.dart';
import '../services/service_endpoints.dart';
import '../services/user_error_message.dart';
import 'campus_web_view_security.dart';
import 'campus_webview_cookie_bridge.dart';
import 'web_view_session_binding.dart';
import 'web_view_back_handler.dart';
import 'web_view_bottom_bar.dart';
import 'web_view_error_view.dart';
import 'web_view_external_navigation.dart';
import 'web_view_permission_capability.dart';
import 'web_view_rendering_policy.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// Host-side bridge for authenticated WebViews.
///
/// WebView is a rendering surface only. The shared credential layer owns the
/// service session; this capability is the single permitted place that turns a
/// service credential into WebView cookies and initial request headers.
/// Feature pages and plugins must not hold credential strings themselves.
class AuthenticatedWebViewCapability {
  /// 桌面版 User-Agent（与教务服务请求使用的桌面 UA 一致）。
  static const desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/150.0.0.0 Safari/537.36';

  @visibleForTesting
  static bool isExternalPaymentUri(Uri uri) =>
      WebViewExternalNavigationCapability.isExternalPaymentUri(uri);

  @visibleForTesting
  static bool shouldRecoverFromHttpError({
    required bool isMainFrame,
    required int? statusCode,
  }) => isMainFrame && (statusCode == 401 || statusCode == 403);

  @visibleForTesting
  static bool shouldUsePublicEntryFallback({
    required bool allowPublicEntryFallback,
    required Uri? requestedUri,
    required bool entryAllowed,
  }) => allowPublicEntryFallback && requestedUri != null && entryAllowed;

  static Future<void> openForService(
    BuildContext context, {
    required String title,
    required String url,
    required CampusServiceId serviceId,
    bool defaultDesktopUA = false,
    bool? useHybridComposition,
    bool showBottomBar = true,
    String? onLoadStopScript,
    UnmodifiableListView<UserScript>? initialUserScripts,
    bool allowPublicEntryFallback = false,
    bool waitForAuthenticationPage = false,
    bool autoCompleteAuthentication = false,
  }) async {
    if (!context.mounted) return;
    final page = AuthenticatedWebViewPage.service(
      title: title,
      url: url,
      serviceId: serviceId,
      defaultDesktopUA: defaultDesktopUA,
      useHybridComposition: useHybridComposition,
      showBottomBar: showBottomBar,
      onLoadStopScript: onLoadStopScript,
      initialUserScripts: initialUserScripts,
      allowPublicEntryFallback: allowPublicEntryFallback,
      waitForAuthenticationPage: waitForAuthenticationPage,
      autoCompleteAuthentication: autoCompleteAuthentication,
    );

    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  static Future<void> openSessionForService(
    BuildContext context, {
    required String title,
    required CampusServiceId serviceId,
    bool showBottomBar = true,
  }) async {
    if (!context.mounted) return;
    final page = AuthenticatedWebViewPage.serviceSession(
      title: title,
      serviceId: serviceId,
      showBottomBar: showBottomBar,
    );

    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  static Widget pageForService({
    required String title,
    required String url,
    required CampusServiceId serviceId,
    bool defaultDesktopUA = false,
    bool? useHybridComposition,
    bool showBottomBar = true,
    String? onLoadStopScript,
    UnmodifiableListView<UserScript>? initialUserScripts,
    bool allowPublicEntryFallback = false,
    bool waitForAuthenticationPage = false,
    bool autoCompleteAuthentication = false,
  }) {
    return AuthenticatedWebViewPage.service(
      title: title,
      url: url,
      serviceId: serviceId,
      defaultDesktopUA: defaultDesktopUA,
      useHybridComposition: useHybridComposition,
      showBottomBar: showBottomBar,
      onLoadStopScript: onLoadStopScript,
      initialUserScripts: initialUserScripts,
      allowPublicEntryFallback: allowPublicEntryFallback,
      waitForAuthenticationPage: waitForAuthenticationPage,
      autoCompleteAuthentication: autoCompleteAuthentication,
    );
  }

  static Widget pageSessionForService({
    required String title,
    required CampusServiceId serviceId,
    bool showBottomBar = true,
  }) {
    return AuthenticatedWebViewPage.serviceSession(
      title: title,
      serviceId: serviceId,
      showBottomBar: showBottomBar,
    );
  }

  /// Prepares and seeds one declared service session for a custom WebView
  /// host. The caller receives no credential or cookie values.
  static Future<WebViewSessionBinding> seedServiceSession({
    required CampusServiceId serviceId,
    required Uri entryUri,
  }) async {
    final bootstrap = await CampusWebViewCookieBridge.prepareAndSeedSession(
      serviceId: serviceId,
      entryUri: entryUri,
    );
    return CampusWebViewCookieBridge.bindingForBootstrap(bootstrap);
  }

  /// Re-materializes a same-account WebView after only its stored service
  /// cookies changed. Hard runtime, generation, and CookieManager fences remain
  /// fixed by the stale binding and cannot be refreshed through this path.
  static Future<WebViewSessionBinding> refreshServiceSession({
    required WebViewSessionBinding binding,
    required Uri entryUri,
  }) => CampusWebViewCookieBridge.refreshAndSeedBinding(
    binding: binding,
    entryUri: entryUri,
  );
}

class AuthenticatedWebViewPage extends StatefulWidget {
  final String title;
  final String? url;
  final CampusServiceId serviceId;
  final bool defaultDesktopUA;
  final bool? useHybridComposition;
  final bool showBottomBar;
  final String? onLoadStopScript;
  final UnmodifiableListView<UserScript>? initialUserScripts;
  final bool allowPublicEntryFallback;
  final bool waitForAuthenticationPage;
  final bool autoCompleteAuthentication;

  const AuthenticatedWebViewPage.service({
    super.key,
    required this.title,
    required this.url,
    required this.serviceId,
    this.defaultDesktopUA = false,
    this.useHybridComposition,
    this.showBottomBar = true,
    this.onLoadStopScript,
    this.initialUserScripts,
    this.allowPublicEntryFallback = false,
    this.waitForAuthenticationPage = false,
    this.autoCompleteAuthentication = false,
  });

  /// 会话 URL 模式：url 为 null，打开时由底层凭证层换取会话入口。
  const AuthenticatedWebViewPage.serviceSession({
    Key? key,
    required String title,
    required CampusServiceId serviceId,
    bool showBottomBar = true,
  }) : this.service(
         key: key,
         title: title,
         url: null,
         serviceId: serviceId,
         showBottomBar: showBottomBar,
       );

  @override
  State<AuthenticatedWebViewPage> createState() =>
      _AuthenticatedWebViewPageState();
}

class _PreparedWebViewLoad {
  const _PreparedWebViewLoad({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class _AuthenticatedWebViewPageState extends State<AuthenticatedWebViewPage> {
  static final UnmodifiableListView<UserScript> _privacyUserScripts =
      UnmodifiableListView([
        UserScript(
          source: r'''
(() => {
  const discard = () => undefined;
  for (const name of ['log', 'info', 'debug', 'warn', 'error']) {
    try {
      Object.defineProperty(console, name, {
        configurable: false,
        enumerable: false,
        writable: false,
        value: discard,
      });
    } catch (_) {
      try { console[name] = discard; } catch (_) {}
    }
  }
})();
''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      ]);

  UnmodifiableListView<UserScript> get _initialUserScripts {
    final identityEpoch = _webViewIdentityEpoch;
    return UnmodifiableListView<UserScript>([
      ..._privacyUserScripts,
      if (identityEpoch != null &&
          _definition.webViewBootstrapMode == WebViewBootstrapMode.browserRelay)
        UserScript(
          // identityEpoch is a non-secret host fence.  It lets a browser
          // relay discard page-local state when the active account changes,
          // without exposing credentials to the feature page.
          source:
              'window.__mychuWebViewIdentityEpoch = ${jsonEncode(identityEpoch)};',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ...?widget.initialUserScripts,
    ]);
  }

  final _webViewPermissions = WebViewPermissionCapability();
  InAppWebViewController? _controller;
  var _disposed = false;
  late bool _useDesktopUA;
  var _loading = true;
  var _canGoBack = false;
  var _canGoForward = false;
  String? _error;
  var _recoveryAttempted = false;
  var _recovering = false;
  _PreparedWebViewLoad? _preparedLoad;
  String? _webViewIdentityEpoch;
  Uri? _sessionLandingUri;
  Map<String, String> _sessionLandingHeaders = const {};
  var _sessionLandingNavigationStarted = false;
  var _browserRelayCallbackSeen = false;
  var _browserRelayCallbackCompleted = false;
  var _authenticationGateReleased = false;
  var _webViewGeneration = 0;
  ErrorFeedbackAttempt? _loadAttempt;

  UserOperationId get _feedbackOperation =>
      operationForAuthenticatedService(widget.serviceId.value);

  CampusServiceDefinition get _definition =>
      CampusServiceEndpoints.definitionForId(widget.serviceId)!;

  @override
  void initState() {
    super.initState();
    _useDesktopUA = widget.defaultDesktopUA;
    unawaited(_prepareInitialLoad());
  }

  @override
  void dispose() {
    _disposed = true;
    _controller = null;
    super.dispose();
  }

  InAppWebViewSettings _settings() => WebViewRenderingPolicy.visible(
    InAppWebViewSettings(
      javaScriptEnabled: true,
      geolocationEnabled: true,
      useShouldOverrideUrlLoading: true,
      userAgent:
          _useDesktopUA ? AuthenticatedWebViewCapability.desktopUserAgent : '',
    ),
    useHybridComposition: widget.useHybridComposition,
  );

  Future<NavigationActionPolicy> _handleNavigation(
    InAppWebViewController _,
    NavigationAction navigationAction,
  ) async {
    if (_disposed || !mounted) return NavigationActionPolicy.CANCEL;
    return WebViewExternalNavigationCapability.handle(
      context,
      navigationAction,
    );
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
  }

  void _startLoadAttempt() {
    _loadAttempt = ErrorFeedbackCoordinator.shared.begin(_feedbackOperation);
  }

  Future<void> _prepareInitialLoad() async {
    _authenticationGateReleased = false;
    _clearSessionLanding();
    final preset = widget.url;
    final presetUri = preset == null ? null : Uri.tryParse(preset);
    if (preset != null) {
      if (presetUri == null || !presetUri.hasScheme) {
        if (mounted) {
          setState(() {
            _preparedLoad = null;
            _error = '地址无效';
            _loading = false;
          });
        }
        return;
      }
    }
    _startLoadAttempt();
    final entryAllowed = presetUri != null && _definition.allowsUri(presetUri);
    final shouldFallbackToPublicEntry =
        AuthenticatedWebViewCapability.shouldUsePublicEntryFallback(
          allowPublicEntryFallback: widget.allowPublicEntryFallback,
          requestedUri: presetUri,
          entryAllowed: entryAllowed,
        );
    try {
      final bootstrap = await _prepareSessionBootstrap(presetUri);
      _webViewIdentityEpoch = bootstrap.identityEpoch;
      final uri = bootstrap.sessionUri ?? presetUri ?? bootstrap.entryUri;
      _armSessionLanding(presetUri, bootstrap);
      if (!mounted || _disposed) return;
      setState(() {
        _controller = null;
        _preparedLoad = _PreparedWebViewLoad(
          uri: uri,
          headers: bootstrap.initialHeaders,
        );
        _webViewGeneration++;
        _error = null;
        _loading = true;
      });
    } catch (error) {
      if (shouldFallbackToPublicEntry) {
        AppLogger.event(
          level: 'INFO',
          code: 'webview.session.fallback_public_entry',
          message: '认证 WebView 服务会话不可用，已回退公共入口',
          operation: operationForAuthenticatedService(widget.serviceId.value),
        );
        if (!mounted || _disposed) return;
        setState(() {
          _controller = null;
          _webViewIdentityEpoch = null;
          _preparedLoad = _PreparedWebViewLoad(
            uri: presetUri!,
            headers: const {},
          );
          _clearSessionLanding();
          _webViewGeneration++;
          _error = null;
          _loading = true;
        });
        return;
      }
      AppLogger.event(
        level: 'WARN',
        code: 'webview.session.prepare_failed',
        message: '认证 WebView 初始会话准备失败',
        operation: operationForAuthenticatedService(widget.serviceId.value),
        exceptionType: error.runtimeType.toString(),
      );
      _loadAttempt?.fail(error);
      if (!mounted) return;
      setState(() {
        _preparedLoad = null;
        _error = '无法获取应用登录态，请返回后重试。';
        _loading = false;
      });
    }
  }

  Future<CampusWebViewSessionBootstrap> _prepareSessionBootstrap(
    Uri? requestedUri, {
    bool forceRefresh = false,
  }) async {
    final entryUri = requestedUri ?? _definition.entryUri;
    return CampusWebViewCookieBridge.prepareAndSeedSession(
      serviceId: widget.serviceId,
      entryUri: entryUri,
      forceRefresh: forceRefresh,
    );
  }

  void _clearSessionLanding() {
    _sessionLandingUri = null;
    _sessionLandingHeaders = const {};
    _sessionLandingNavigationStarted = false;
    _browserRelayCallbackSeen = false;
    _browserRelayCallbackCompleted = false;
  }

  void _armSessionLanding(
    Uri? requestedUri,
    CampusWebViewSessionBootstrap bootstrap,
  ) {
    if (!_definition.webViewUsesSessionUri ||
        bootstrap.sessionUri == null ||
        requestedUri == null ||
        !_definition.allowsUri(requestedUri)) {
      _clearSessionLanding();
      return;
    }
    _sessionLandingUri = requestedUri;
    _sessionLandingHeaders = bootstrap.initialHeaders;
    _sessionLandingNavigationStarted = false;
  }

  Future<bool> _navigateToSessionLanding(
    InAppWebViewController controller,
    Uri? currentUri,
  ) async {
    final targetUri = _sessionLandingUri;
    if (targetUri == null ||
        _sessionLandingNavigationStarted ||
        _disposed ||
        !mounted) {
      return false;
    }
    if (currentUri == targetUri) {
      _sessionLandingNavigationStarted = true;
      return false;
    }

    _sessionLandingNavigationStarted = true;
    if (mounted) setState(() => _loading = true);
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(targetUri.toString()),
          headers: _sessionLandingHeaders,
        ),
      );
    } catch (_) {
      if (!mounted || _disposed) return true;
      setState(() {
        _error = '页面打开失败，请重试。';
        _loading = false;
      });
    }
    return true;
  }

  void _observeBrowserRelayNavigation(Uri? uri) {
    if (_definition.webViewBootstrapMode != WebViewBootstrapMode.browserRelay ||
        uri == null) {
      return;
    }
    // The SPA owns the OAuth exchange.  The callback route is the stable
    // signal that the identity redirect completed; relying on a preceding
    // IDS navigation event is brittle because Android can recreate the
    // renderer/target while following the redirect.
    if (uri.host == _definition.host &&
        uri.fragment.contains('/pages/oauth/callback')) {
      _browserRelayCallbackSeen = true;
      // A cached identity session may complete the redirect too quickly for
      // Android to report a separate IDS document. The callback is still a
      // safe post-authentication signal in the normal gate mode. Automatic
      // authorization keeps the gate up until the SPA reaches its root page.
      if (!widget.autoCompleteAuthentication) {
        _releaseAuthenticationGate();
      }
      return;
    }
    if (_browserRelayCallbackSeen &&
        uri.host == _definition.host &&
        !uri.fragment.contains('/pages/oauth/callback')) {
      _browserRelayCallbackCompleted = true;
    }
  }

  bool _isAuthenticationRedirect(Uri? uri) =>
      uri != null && FederatedSession.isIdentityLoginUri(uri);

  void _observeAuthenticationPage(Uri? uri) {
    if (!widget.waitForAuthenticationPage || _authenticationGateReleased) {
      return;
    }
    if (_isAuthenticationRedirect(uri) && !widget.autoCompleteAuthentication) {
      _releaseAuthenticationGate();
    }
  }

  void _releaseAuthenticationGate() {
    if (!widget.waitForAuthenticationPage || _authenticationGateReleased) {
      return;
    }
    _authenticationGateReleased = true;
    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _observeAuthenticationReady(
    InAppWebViewController controller,
  ) async {
    if (!widget.waitForAuthenticationPage ||
        _authenticationGateReleased ||
        _disposed) {
      return;
    }
    try {
      // Browser-relay SPAs may already have a completed session and therefore
      // never navigate through an identity URL on a later opening. The page
      // can expose this non-sensitive DOM readiness signal at document start.
      final ready = await controller.evaluateJavascript(
        source: r'''
(() => document.documentElement?.dataset?.mychuAuthenticationReady === '1')()
''',
      );
      if (ready == true || '$ready' == 'true') {
        _releaseAuthenticationGate();
      }
    } catch (_) {}
  }

  bool get _authenticationGateActive =>
      widget.waitForAuthenticationPage &&
      !_authenticationGateReleased &&
      (widget.autoCompleteAuthentication || !_browserRelayCallbackCompleted) &&
      _error == null;

  Future<void> _recoverFromAuthenticationRedirect(
    InAppWebViewController controller,
    Uri? redirectUri, {
    bool forceRecovery = false,
  }) async {
    if (!forceRecovery &&
        _definition.webViewBootstrapMode == WebViewBootstrapMode.browserRelay) {
      return;
    }
    if (_disposed ||
        !mounted ||
        _recovering ||
        _recoveryAttempted ||
        !forceRecovery && !_isAuthenticationRedirect(redirectUri)) {
      return;
    }
    _recovering = true;
    _recoveryAttempted = true;
    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final account = await AuthService.getCurrentAccount();
      if (account == null) throw StateError('请先登录');
      final requestedUri =
          widget.url == null ? null : Uri.tryParse(widget.url!);
      final originalUri =
          forceRecovery &&
                  redirectUri != null &&
                  _definition.allowsUri(redirectUri)
              ? redirectUri
              : requestedUri;
      await CampusSessionService.invalidate(
        widget.serviceId,
        accountKey: account.accountKey,
        serviceUri: originalUri ?? _definition.entryUri,
        reason: SessionInvalidationReason.authFailure,
      );
      final bootstrap = await _prepareSessionBootstrap(
        originalUri,
        forceRefresh: true,
      );
      final uri = bootstrap.sessionUri ?? originalUri ?? bootstrap.entryUri;
      _armSessionLanding(requestedUri, bootstrap);
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(uri.toString()),
          headers: bootstrap.initialHeaders,
        ),
      );
      AppLogger.event(
        level: 'INFO',
        code: 'webview.session.recovered',
        message: '认证 WebView 已完成一次服务会话恢复',
        operation: _feedbackOperation,
      );
    } catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'webview.session.recovery_failed',
        message: '认证 WebView 服务会话恢复失败',
        operation: _feedbackOperation,
        exceptionType: error.runtimeType.toString(),
      );
      if (mounted) {
        setState(() {
          _error = '登录状态已失效，请返回后重试或重新登录。';
          _loading = false;
        });
      }
    } finally {
      _recovering = false;
    }
  }

  Future<void> _goBack() async {
    if (_disposed || !mounted) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      if (await controller.canGoBack()) {
        await controller.goBack();
      }
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
    await _updateNavigationState(controller);
  }

  Future<void> _goForward() async {
    if (_disposed || !mounted) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      if (await controller.canGoForward()) {
        await controller.goForward();
      }
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
    await _updateNavigationState(controller);
  }

  Future<void> _reload() async {
    if (_error != null) {
      _error = null;
      _recoveryAttempted = false;
      if (mounted) setState(() => _loading = true);
      await _prepareInitialLoad();
      return;
    }
    _startLoadAttempt();
    setState(() => _loading = true);
    try {
      await _controller?.reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '页面刷新失败，请重试。';
      });
    }
  }

  Future<void> _updateNavigationState([
    InAppWebViewController? expectedController,
  ]) async {
    // 隐藏底栏时仍同步 _canGoBack，供系统返回手势优先回退 WebView 历史。
    if (_disposed || !mounted) return;
    final controller = _controller;
    if (controller == null ||
        expectedController != null &&
            !identical(controller, expectedController)) {
      return;
    }
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (_disposed ||
          !mounted ||
          !identical(_controller, controller) ||
          expectedController != null &&
              !identical(controller, expectedController)) {
        return;
      }
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    } on PlatformException {
      // WebView 可能在加载回调期间销毁，导航状态不是关键 UI。
    } on MissingPluginException {
      // Renderer/channel 退出后，导航状态不是关键 UI；等待重试重建 WebView。
    }
  }

  void _onRenderProcessGone(
    InAppWebViewController controller,
    RenderProcessGoneDetail detail,
  ) {
    if (_disposed || !mounted || !identical(_controller, controller)) return;
    if (_loadAttempt?.completed != false) _startLoadAttempt();
    logUserFacingError(
      UserErrorContext.webView,
      StateError('WebView renderer exited'),
      operationId: _feedbackOperation,
      renderProcessCrashed: detail.didCrash,
      feedbackAttempt: _loadAttempt,
    );
    setState(() {
      _controller = null;
      _loading = false;
      _error ??= detail.didCrash ? '页面渲染进程异常，请点击重试。' : '页面渲染进程已退出，请点击重试。';
    });
  }

  Future<void> _runOnLoadStopScript(InAppWebViewController controller) async {
    final script = widget.onLoadStopScript;
    if (script == null || script.isEmpty) return;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {
      AppLogger.event(
        level: 'WARN',
        code: 'webview.document.init_script_failed',
        message: '认证 WebView 页面初始化脚本执行失败',
        operation: _feedbackOperation,
      );
    }
  }

  Future<void> _toggleUserAgent() async {
    setState(() => _useDesktopUA = !_useDesktopUA);
    try {
      await _controller?.setSettings(settings: _settings());
      await _controller?.reload();
    } catch (_) {
      // 首屏尚未加载完成时切换 UA，重载失败可忽略，后续加载使用新 UA。
    }
    if (!mounted) return;

    // 快速连续点击时立即替换上一条提示，而不是排队等待上一条消失。
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_useDesktopUA ? '已修改为桌面端视图' : '已修改为移动端视图'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<ServerTrustAuthResponse?> _onServerTrustAuth(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async {
    final host = challenge.protectionSpace.host;
    if (shouldUseSystemCertificateValidation(host)) {
      AppLogger.event(
        level: 'INFO',
        code: 'webview.tls.system_validation',
        message: '认证 WebView 服务器证书使用系统校验',
        operation: operationForAuthenticatedService(widget.serviceId.value),
      );
      return null;
    }
    AppLogger.event(
      level: 'WARN',
      code: 'webview.tls.compatibility_validation',
      message: '认证 WebView 服务器证书使用校园兼容校验',
      operation: operationForAuthenticatedService(widget.serviceId.value),
    );
    return ServerTrustAuthResponse(
      action: ServerTrustAuthResponseAction.PROCEED,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    return WebViewBackHandler(
      canGoBack: _canGoBack,
      onBack: _goBack,
      child: Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(
            leading: const WebViewCloseButton(),
            title: Text(widget.title),
          ),
        ),
        body: _buildWebViewContent(context),
        bottomNavigationBar:
            widget.showBottomBar
                ? WebViewBottomBar(
                  canGoBack: _canGoBack,
                  canGoForward: _canGoForward,
                  useDesktopUA: _useDesktopUA,
                  onBack: _goBack,
                  onForward: _goForward,
                  onReload: _reload,
                  onToggleUA: _toggleUserAgent,
                )
                : null,
      ),
    );
  }

  Widget _buildWebViewContent(BuildContext context) {
    final preparedLoad = _preparedLoad;
    return SafeArea(
      // 隐藏底栏时隔离系统导航栏（手势白条），避免 WebView 内容与之混叠。
      top: false,
      bottom: !widget.showBottomBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_error case final error?)
            WebViewErrorView(message: error, onRetry: _reload)
          else if (preparedLoad != null)
            InAppWebView(
              key: ValueKey(_webViewGeneration),
              initialUserScripts: _initialUserScripts,
              initialUrlRequest: URLRequest(
                url: WebUri(preparedLoad.uri.toString()),
                headers: preparedLoad.headers,
              ),
              initialSettings: _settings(),
              onWebViewCreated: _onWebViewCreated,
              shouldOverrideUrlLoading: _handleNavigation,
              onPermissionRequest:
                  (controller, request) =>
                      _webViewPermissions.handlePermissionRequest(request),
              onGeolocationPermissionsShowPrompt:
                  (controller, origin) => _webViewPermissions
                      .handleGeolocationPermissionsShowPrompt(origin),
              onLoadStart: (controller, url) {
                final parsedUrl =
                    url == null ? null : Uri.tryParse(url.toString());
                _observeAuthenticationPage(parsedUrl);
                _observeBrowserRelayNavigation(parsedUrl);
                AppLogger.event(
                  level: 'INFO',
                  code: 'webview.document.load_started',
                  message: '认证 WebView 开始加载',
                  operation: _feedbackOperation,
                );
                if (_loadAttempt?.completed != false) _startLoadAttempt();
                if (mounted) setState(() => _loading = true);
                unawaited(_recoverFromAuthenticationRedirect(controller, url));
              },
              onUpdateVisitedHistory: (controller, url, isReload) async {
                _observeBrowserRelayNavigation(url);
                unawaited(_observeAuthenticationReady(controller));
                // uni-app completes the OAuth exchange and switches from the
                // callback hash to the SPA root without a document load.  In
                // that case onLoadStop is not emitted, so advance to the
                // requested business route from the history callback.
                unawaited(_navigateToSessionLanding(controller, url));
              },
              onLoadStop: (controller, url) async {
                final parsedUrl =
                    url == null ? null : Uri.tryParse(url.toString());
                _observeAuthenticationPage(parsedUrl);
                _observeBrowserRelayNavigation(parsedUrl);
                AppLogger.event(
                  level: 'INFO',
                  code: 'webview.document.load_completed',
                  message: '认证 WebView 加载完成',
                  operation: _feedbackOperation,
                );
                await _recoverFromAuthenticationRedirect(controller, url);
                if (_recovering || _disposed) return;
                await _observeAuthenticationReady(controller);
                if (await _navigateToSessionLanding(controller, url)) return;
                if (mounted) {
                  setState(() => _loading = _authenticationGateActive);
                }
                await _runOnLoadStopScript(controller);
                await _updateNavigationState(controller);
                _loadAttempt?.succeed();
              },
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame != true) return;
                logUserFacingError(
                  UserErrorContext.webView,
                  error,
                  operationId: _feedbackOperation,
                  feedbackAttempt: _loadAttempt,
                );
                setState(() {
                  _error = userFacingError(UserErrorContext.webView, error);
                  _loading = false;
                });
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                final statusCode = errorResponse.statusCode;
                if (request.isForMainFrame != true ||
                    statusCode == null ||
                    statusCode < 400) {
                  return;
                }
                if (AuthenticatedWebViewCapability.shouldRecoverFromHttpError(
                  isMainFrame: request.isForMainFrame == true,
                  statusCode: statusCode,
                )) {
                  unawaited(
                    _recoverFromAuthenticationRedirect(
                      controller,
                      Uri.tryParse(request.url.toString()),
                      forceRecovery: true,
                    ),
                  );
                  return;
                }
                AppLogger.event(
                  level: 'WARN',
                  code: 'webview.document.http_error',
                  message: '认证 WebView 主文档返回 HTTP 错误',
                  operation: _feedbackOperation,
                  statusCode: statusCode,
                );
                if (!mounted) return;
                logUserFacingError(
                  UserErrorContext.webView,
                  errorResponse,
                  operationId: _feedbackOperation,
                  statusCode: statusCode,
                  feedbackAttempt: _loadAttempt,
                );
                setState(() {
                  _error = userFacingError(
                    UserErrorContext.webView,
                    errorResponse,
                  );
                  _loading = false;
                });
              },
              onReceivedServerTrustAuthRequest: _onServerTrustAuth,
              onRenderProcessGone: _onRenderProcessGone,
            ),
          if (_authenticationGateActive)
            _buildAuthenticationGate(context)
          else if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildAuthenticationGate(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    const indicator = CircularProgressIndicator();
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: backgroundColor,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [indicator, SizedBox(height: 12), Text('正在打开统一身份授权…')],
            ),
          ),
        ),
      ),
    );
  }
}
