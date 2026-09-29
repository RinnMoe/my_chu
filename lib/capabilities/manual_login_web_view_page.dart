import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/logger_service.dart';
import '../services/error_feedback_service.dart';
import '../services/user_error_message.dart';
import 'campus_web_view_security.dart';
import 'web_view_back_handler.dart';
import 'web_view_bottom_bar.dart';
import 'web_view_error_view.dart';
import 'web_view_external_navigation.dart';
import 'web_view_permission_capability.dart';
import 'web_view_rendering_policy.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 手动登录 WebView 页面（共享能力）。
///
/// 用于未接入统一身份认证的站点（如可信电子文档、第二课堂）：不注入任何
/// 统一身份 Cookie，用户首次打开自行登录；登录后的 Cookie 由平台 WebView
/// 存储在本机（与浏览器一致），下次打开无需重复登录。账号重新登录时登录页
/// 会清空 WebView Cookie，保证账号间隔离。页面自身不持有任何凭证字符串。
class ManualLoginWebViewPage extends StatefulWidget {
  final String title;
  final String url;
  final bool showBottomBar;

  /// Optional Android composition override for pages that render poorly in
  /// Texture Layer Hybrid Composition. Other pages keep the shared policy.
  final bool? useHybridComposition;

  /// 页面级预置脚本，在 WebView 初始化时注入（AT_DOCUMENT_START）。
  /// 仅用于站点级初始化配置（如学校选择）或按选择器移除站点冗余区块，
  /// 不携带任何凭证字符串。
  final UnmodifiableListView<UserScript>? initialUserScripts;

  const ManualLoginWebViewPage({
    super.key,
    required this.title,
    required this.url,
    this.showBottomBar = true,
    this.useHybridComposition,
    this.initialUserScripts,
  });

  @override
  State<ManualLoginWebViewPage> createState() => _ManualLoginWebViewPageState();
}

class _ManualLoginWebViewPageState extends State<ManualLoginWebViewPage> {
  final _webViewPermissions = WebViewPermissionCapability();
  InAppWebViewController? _controller;
  var _disposed = false;
  var _loading = true;
  var _canGoBack = false;
  var _canGoForward = false;
  var _useDesktopUA = false;
  String? _error;
  ErrorFeedbackAttempt? _feedbackAttempt;

  void _startFeedbackAttempt() {
    _feedbackAttempt = ErrorFeedbackCoordinator.shared.begin(
      UserOperationId.manualWebView,
    );
  }

  @override
  void initState() {
    super.initState();
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
      userAgent: _useDesktopUA ? _desktopUserAgent : '',
    ),
    useHybridComposition: widget.useHybridComposition,
  );

  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/150.0.0.0 Safari/537.36';

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;
    _startFeedbackAttempt();
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
    } catch (error) {
      if (!mounted) return;
      logUserFacingError(
        UserErrorContext.webView,
        error,
        operationId: UserOperationId.manualWebView,
        feedbackAttempt: _feedbackAttempt,
      );
      setState(() {
        _error = userFacingError(UserErrorContext.webView, error);
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _startFeedbackAttempt();
    try {
      await _controller?.reload();
    } catch (error) {
      if (!mounted) return;
      logUserFacingError(
        UserErrorContext.webView,
        error,
        operation: 'manual',
        feedbackAttempt: _feedbackAttempt,
      );
      setState(() {
        _loading = false;
        _error = '页面刷新失败，请重试。';
      });
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
    }
    await _updateNavigationState();
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
    }
    await _updateNavigationState();
  }

  Future<void> _updateNavigationState() async {
    // 隐藏底栏时仍同步 _canGoBack，供系统返回手势优先回退 WebView 历史。
    if (_disposed || !mounted) return;
    final controller = _controller;
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
      await _controller?.setSettings(settings: _settings());
      await _controller?.reload();
    } catch (_) {
      // 首屏尚未加载完成时切换 UA，重载失败可忽略，后续加载使用新 UA。
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

  Future<ServerTrustAuthResponse?> _onServerTrustAuth(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async {
    final host = challenge.protectionSpace.host;
    if (shouldUseSystemCertificateValidation(host)) {
      AppLogger.event(
        level: 'INFO',
        code: 'webview.manual.tls.system_validation',
        message: '手动登录 WebView 服务器证书使用系统校验',
      );
      return null;
    }
    AppLogger.event(
      level: 'WARN',
      code: 'webview.manual.tls.compatibility_validation',
      message: '手动登录 WebView 服务器证书使用校园兼容校验',
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
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
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
    return SafeArea(
      // 隐藏底栏时隔离系统导航栏（手势白条），避免 WebView 内容与之混叠。
      top: false,
      bottom: !widget.showBottomBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_error case final error?)
            WebViewErrorView(message: error, onRetry: _reload)
          else
            InAppWebView(
              initialSettings: _settings(),
              initialUserScripts: widget.initialUserScripts,
              onWebViewCreated: _onWebViewCreated,
              shouldOverrideUrlLoading:
                  (controller, navigationAction) =>
                      WebViewExternalNavigationCapability.handle(
                        context,
                        navigationAction,
                      ),
              onPermissionRequest:
                  (controller, request) =>
                      _webViewPermissions.handlePermissionRequest(request),
              onGeolocationPermissionsShowPrompt:
                  (controller, origin) => _webViewPermissions
                      .handleGeolocationPermissionsShowPrompt(origin),
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
                if (!mounted || request.isForMainFrame != true) return;
                logUserFacingError(
                  UserErrorContext.webView,
                  error,
                  operation: 'manual',
                  feedbackAttempt: _feedbackAttempt,
                );
                setState(() {
                  _error = userFacingError(UserErrorContext.webView, error);
                  _loading = false;
                });
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                if (!mounted || request.isForMainFrame != true) return;
                final statusCode = errorResponse.statusCode;
                if (statusCode == 401 || statusCode == 403) return;
                final error = StateError('Manual login WebView HTTP error');
                logUserFacingError(
                  UserErrorContext.webView,
                  error,
                  operation: 'manual',
                  statusCode: statusCode,
                  feedbackAttempt: _feedbackAttempt,
                );
                setState(() {
                  _error = userFacingError(UserErrorContext.webView, error);
                  _loading = false;
                });
              },
              onRenderProcessGone: (controller, detail) {
                if (!mounted) return;
                if (_feedbackAttempt?.completed != false) {
                  _startFeedbackAttempt();
                }
                logUserFacingError(
                  UserErrorContext.webView,
                  StateError('Manual login WebView renderer exited'),
                  operationId: UserOperationId.manualWebView,
                  renderProcessCrashed: detail.didCrash,
                  feedbackAttempt: _feedbackAttempt,
                );
                setState(() {
                  _error =
                      detail.didCrash ? '页面渲染进程异常，请点击重试。' : '页面渲染进程已退出，请点击重试。';
                  _loading = false;
                });
              },
              onReceivedServerTrustAuthRequest: _onServerTrustAuth,
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
