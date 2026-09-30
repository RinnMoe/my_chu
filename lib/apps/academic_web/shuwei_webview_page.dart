import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../capabilities/web_view_back_handler.dart';
import '../../capabilities/web_view_bottom_bar.dart';
import '../../capabilities/web_view_error_view.dart';
import '../../capabilities/web_view_permission_capability.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/error_feedback_service.dart';
import '../../services/service_endpoints.dart';
import '../../services/user_error_message.dart';
import '../../capabilities/shuwei_request_proxy.dart';
import '../../capabilities/web_view_rendering_policy.dart';
import '../../capabilities/web_view_session_binding.dart';
import '../../widgets/root_destination_active_scope.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 教务系统网页版（WakeUp 兼容逻辑，带共享底栏）。
///
/// 使用树维 GET 请求代理（Dio）+ WebView Cookie 双向同步；统一身份会话在
/// 加载前播种进 WebView Cookie 存储，保证免登录访问。底栏提供后退/前进/
/// 刷新与 UA 切换。
class ShuweiWebViewPage extends StatefulWidget {
  const ShuweiWebViewPage({super.key});

  @override
  State<ShuweiWebViewPage> createState() => _ShuweiWebViewPageState();
}

class _ShuweiWebViewPageState extends State<ShuweiWebViewPage> {
  // 直接进入 home.action：避免先加载 eams/ 再跳转产生的连发请求，
  // 首次打开与“刷新”行为一致，不再触发“不要过快点击”风控。
  static final _undergraduateEntry =
      CampusServiceEndpoints.academicAffairsHomeUri;
  static final _graduateEntry =
      CampusServiceEndpoints.graduateAcademicAffairsHomeUri;
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/150.0.0.0 Safari/537.36';

  late final ShuweiRequestProxy _proxy;
  final _webViewPermissions = WebViewPermissionCapability();
  InAppWebViewController? _webViewController;
  var _disposed = false;
  var _webViewReady = false;
  var _loading = true;
  var _canGoBack = false;
  var _canGoForward = false;
  var _rootDestinationActive = true;
  var _routeCurrent = true;
  var _resumeRefreshPending = false;
  var _resumeRefreshRunning = false;
  String? _error;
  ErrorFeedbackAttempt? _feedbackAttempt;
  // 教务系统网页版默认桌面视图：首次进入即按电脑模式渲染，避免
  // 移动端 UA 下页面布局异常；用户仍可通过底栏 UA 按钮切换。
  var _useDesktopUA = true;
  AcademicAffairsBackend? _backend;

  void _startFeedbackAttempt() {
    _feedbackAttempt = ErrorFeedbackCoordinator.shared.begin(
      UserOperationId.academicWebView,
    );
  }

  @override
  void initState() {
    super.initState();
    AuthenticatedWebViewCapability.resumeNotifier.addListener(
      _onAppResumeRevisionChanged,
    );
    _proxy = ShuweiRequestProxy(refreshBinding: _refreshProxyBinding);
    unawaited(_prepareWebView());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rootDestinationActive = RootDestinationActiveScope.activeOf(context);
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _refreshAfterResumeWhenVisible();
  }

  void _onAppResumeRevisionChanged() {
    _resumeRefreshPending = true;
    _refreshAfterResumeWhenVisible();
  }

  void _refreshAfterResumeWhenVisible() {
    if (!_resumeRefreshPending ||
        !_rootDestinationActive ||
        !_routeCurrent ||
        _resumeRefreshRunning ||
        _disposed ||
        !mounted) {
      return;
    }
    _resumeRefreshPending = false;
    _resumeRefreshRunning = true;
    unawaited(
      _refreshAfterAppResume().whenComplete(() {
        _resumeRefreshRunning = false;
        _refreshAfterResumeWhenVisible();
      }),
    );
  }

  Future<void> _refreshAfterAppResume() async {
    final controller = _webViewController;
    if (controller == null) {
      await _prepareWebView();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _startFeedbackAttempt();
    try {
      final binding = await AuthenticatedWebViewCapability.seedServiceSession(
        serviceId: _serviceId,
        entryUri: _entryUri,
      );
      if (_disposed || !mounted) return;
      _proxy.bindSession(binding);
      await controller.reload();
      if (_disposed || !mounted) return;
      await _updateNavigationState();
    } catch (error) {
      _showWebViewError(error);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Uri get _entryUri =>
      _backend == AcademicAffairsBackend.graduate
          ? _graduateEntry
          : _undergraduateEntry;

  CampusServiceId get _serviceId =>
      _backend == AcademicAffairsBackend.graduate
          ? CampusServices.graduateAcademicAffairs
          : CampusServices.academicAffairs;

  @override
  void dispose() {
    _disposed = true;
    AuthenticatedWebViewCapability.resumeNotifier.removeListener(
      _onAppResumeRevisionChanged,
    );
    _webViewController = null;
    _proxy.dispose();
    super.dispose();
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
  }

  Future<void> _prepareWebView() async {
    _startFeedbackAttempt();
    try {
      _backend = await AcademicAffairsBackendResolver.resolveCurrent();
      final binding = await AuthenticatedWebViewCapability.seedServiceSession(
        serviceId: _serviceId,
        entryUri: _entryUri,
      );
      if (_disposed || !mounted) return;
      _proxy.bindSession(binding);
      setState(() {
        _webViewReady = true;
        _loading = true;
        _error = null;
      });
    } catch (error) {
      _showWebViewError(error);
    }
  }

  Future<WebViewSessionBinding> _refreshProxyBinding(
    WebViewSessionBinding binding,
  ) => AuthenticatedWebViewCapability.refreshServiceSession(
    binding: binding,
    entryUri: _entryUri,
  );

  InAppWebViewSettings _settings() => WebViewRenderingPolicy.visible(
    InAppWebViewSettings(
      // WakeUp 中确认存在的设置。
      javaScriptEnabled: true,
      geolocationEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      domStorageEnabled: true,

      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

      useWideViewPort: true,

      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,

      thirdPartyCookiesEnabled: true,

      // 启用 WakeUp 使用的请求接管逻辑。
      useShouldInterceptRequest: _backend != AcademicAffairsBackend.graduate,

      userAgent: _useDesktopUA ? _desktopUserAgent : '',
    ),
  );

  Future<void> _goBack() async {
    if (_disposed || !mounted) return;
    final controller = _webViewController;
    if (controller == null) return;
    try {
      if (await controller.canGoBack()) {
        await controller.goBack();
      }
    } on PlatformException {
      return;
    }
    await _updateNavigationState();
  }

  Future<void> _goForward() async {
    if (_disposed || !mounted) return;
    final controller = _webViewController;
    if (controller == null) return;
    try {
      if (await controller.canGoForward()) {
        await controller.goForward();
      }
    } on PlatformException {
      return;
    }
    await _updateNavigationState();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = _webViewController;
      if (controller == null) {
        await _prepareWebView();
      } else {
        _startFeedbackAttempt();
        final binding = await AuthenticatedWebViewCapability.seedServiceSession(
          serviceId: _serviceId,
          entryUri: _entryUri,
        );
        if (_disposed || !mounted) return;
        _proxy.bindSession(binding);
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(_entryUri.toString())),
        );
      }
    } catch (error) {
      _showWebViewError(error);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showWebViewError(Object error, {bool countFailure = true}) {
    if (countFailure) {
      logUserFacingError(
        UserErrorContext.webView,
        error,
        operationId: UserOperationId.academicWebView,
        feedbackAttempt: _feedbackAttempt,
      );
    }
    if (!mounted) return;
    setState(() {
      _error = userFacingError(UserErrorContext.webView, error);
      _loading = false;
    });
  }

  Future<void> _updateNavigationState() async {
    if (_disposed || !mounted) return;
    final controller = _webViewController;
    if (controller == null) return;
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (_disposed || !mounted) return;
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    } on PlatformException {
      // WebView 可能在加载回调期间销毁，导航状态不是关键 UI。
    }
  }

  Future<void> _toggleUserAgent() async {
    setState(() => _useDesktopUA = !_useDesktopUA);
    try {
      await _webViewController?.setSettings(settings: _settings());
      await _webViewController?.reload();
    } catch (_) {
      // 首屏尚未加载完成时切换 UA，重载失败可忽略。
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_useDesktopUA ? '已修改为桌面端视图' : '已修改为移动端视图'),
          duration: const Duration(milliseconds: 1200),
        ),
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
            title: const Text('教务系统'),
          ),
        ),
        body: _buildWebViewContent(context),
        bottomNavigationBar: WebViewBottomBar(
          canGoBack: _canGoBack,
          canGoForward: _canGoForward,
          useDesktopUA: _useDesktopUA,
          onBack: _goBack,
          onForward: _goForward,
          onReload: _reload,
          onToggleUA: _toggleUserAgent,
        ),
      ),
    );
  }

  Widget _buildWebViewContent(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_webViewReady)
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_entryUri.toString())),
              initialSettings: _settings(),
              onWebViewCreated: _onWebViewCreated,
              onPermissionRequest:
                  (controller, request) =>
                      _webViewPermissions.handlePermissionRequest(request),
              onGeolocationPermissionsShowPrompt:
                  (controller, origin) => _webViewPermissions
                      .handleGeolocationPermissionsShowPrompt(origin),
              shouldInterceptRequest: (controller, request) {
                if (_backend == AcademicAffairsBackend.graduate) {
                  return Future<WebResourceResponse?>.value();
                }
                return _proxy.intercept(request);
              },
              onLoadStart: (controller, url) {
                if (_feedbackAttempt?.completed != false) {
                  _startFeedbackAttempt();
                }
                if (mounted) setState(() => _loading = true);
              },
              onLoadStop: (controller, url) async {
                if (mounted) {
                  _feedbackAttempt?.succeed();
                  setState(() => _loading = false);
                }
                await _updateNavigationState();
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame != true) return;
                _showWebViewError(error);
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                final statusCode = errorResponse.statusCode;
                if (request.isForMainFrame != true ||
                    statusCode == null ||
                    statusCode < 400) {
                  return;
                }
                _showWebViewError(
                  errorResponse,
                  countFailure: statusCode != 401 && statusCode != 403,
                );
              },
              onRenderProcessGone: (controller, detail) {
                if (!mounted) return;
                if (_feedbackAttempt?.completed != false) {
                  _startFeedbackAttempt();
                }
                logUserFacingError(
                  UserErrorContext.webView,
                  StateError('Academic WebView renderer exited'),
                  operationId: UserOperationId.academicWebView,
                  renderProcessCrashed: detail.didCrash,
                  feedbackAttempt: _feedbackAttempt,
                );
                setState(() {
                  _error =
                      detail.didCrash ? '页面渲染进程异常，请点击重试。' : '页面渲染进程已退出，请点击重试。';
                  _loading = false;
                });
              },
            ),
          if (_error case final error?)
            Positioned.fill(
              child: WebViewErrorView(message: error, onRetry: _reload),
            ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}
