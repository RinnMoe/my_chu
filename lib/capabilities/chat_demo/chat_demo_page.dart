import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/deepseek_api_settings_service.dart';
import '../../services/logging/logger.dart';
import '../../widgets/adaptive_feedback.dart';
import '../../pages/deepseek_api_settings_page.dart';
import '../../services/host_permission_service.dart';
import 'chat_demo_brand.dart';
import 'chat_demo_bridge.dart';
import 'chat_demo_storage.dart';
import 'chat_demo_theme.dart';

const String aiAssistantFeatureId = 'feature.ai.assistant';
const String chatDemoAssetOrigin = 'https://appassets.androidplatform.net';
const String chatDemoAssetPath =
    '/assets/flutter_assets/assets/chat_demo/index.html';
const String chatDemoAssetUrl = '$chatDemoAssetOrigin$chatDemoAssetPath';
const int chatDemoBridgeProtocol = 1;

/// 仅承载 chat-demo 静态 Web 应用；Key、校园工具和文件桥由宿主提供。
class ChatDemoPage extends StatefulWidget {
  const ChatDemoPage({super.key});

  @override
  State<ChatDemoPage> createState() => _ChatDemoPageState();
}

class _ChatDemoPageState extends State<ChatDemoPage> {
  final _settingsService = DeepSeekApiSettingsService.instance;
  String? _apiKey;
  String? _loadError;
  String _bridgeMode = 'degraded';
  ChatDemoBridge? _bridge;
  InAppWebViewController? _controller;
  bool _loadingKey = true;
  bool _pageLoading = true;
  bool _disposed = false;
  int _webViewGeneration = 0;
  Brightness? _lastBrightness;

  @override
  void initState() {
    super.initState();
    _settingsService.revision.addListener(_onKeyRevision);
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final previous = _lastBrightness;
    _lastBrightness = brightness;
    if (previous != null && previous != brightness && _apiKey != null) {
      _bridge?.dispose();
      _bridge = null;
      _controller = null;
      setState(() {
        _pageLoading = true;
        _loadError = null;
        _webViewGeneration++;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _bridge?.dispose();
    _settingsService.revision.removeListener(_onKeyRevision);
    super.dispose();
  }

  Future<void> _initialize() async {
    final mode = await _detectBridgeMode();
    String? key;
    try {
      key = await _settingsService.read();
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
    if (!mounted) return;
    setState(() {
      _bridgeMode = mode;
      _apiKey = key;
      _loadingKey = false;
      _pageLoading = true;
      _loadError = null;
      _webViewGeneration++;
    });
  }

  Future<String> _detectBridgeMode() async {
    if (!Platform.isAndroid) return 'degraded';
    try {
      final supported = await WebViewFeature.isFeatureSupported(
        WebViewFeature.WEB_MESSAGE_LISTENER,
      );
      return supported ? 'full' : 'degraded';
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return 'degraded';
    }
  }

  Future<void> _loadKey() async {
    String? key;
    try {
      key = await _settingsService.read();
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
    if (!mounted) return;
    _bridge?.dispose();
    _bridge = null;
    _controller = null;
    setState(() {
      _apiKey = key;
      _pageLoading = true;
      _loadError = null;
      _webViewGeneration++;
    });
  }

  void _onKeyRevision() {
    if (_disposed) return;
    unawaited(_loadKey());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DeepSeekApiSettingsPage()),
    );
    if (!mounted) return;
    await _loadKey();
  }

  String _hostConfigScript({required bool showBack}) {
    final theme = Theme.of(context);
    final config = <String, Object?>{
      'embedded': true,
      'bridgeMode': _bridgeMode,
      'bridgeProtocol': chatDemoBridgeProtocol,
      'apiKey': _apiKey,
      'showBack': showBack,
      'platform': Platform.isAndroid ? 'android' : 'other',
      'theme': theme.brightness == Brightness.dark ? 'dark' : 'light',
      'themeCss': buildChatDemoThemeCss(theme.colorScheme),
    };
    return 'window.__MYCHU__ = ${jsonEncode(config)};';
  }

  InAppWebViewSettings _webViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      // 页面加载前的 WebView 默认白底会在深色主题下闪现；透明后露出 Scaffold 主题底色。
      transparentBackground: true,
      supportMultipleWindows: false,
      javaScriptCanOpenWindowsAutomatically: false,
      thirdPartyCookiesEnabled: false,
      mediaPlaybackRequiresUserGesture: true,
      useOnDownloadStart: true,
      useOnRenderProcessGone: true,
      useShouldOverrideUrlLoading: true,
      webViewAssetLoader: WebViewAssetLoader(
        domain: 'appassets.androidplatform.net',
        pathHandlers: [AssetsPathHandler(path: '/assets/')],
      ),
    );
  }

  Future<void> _bootstrap(InAppWebViewController controller) async {
    if (_bridgeMode == 'full') {
      await _attachBridge(controller);
    }
    if (!mounted || _disposed) return;
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(chatDemoAssetUrl)),
    );
  }

  Future<void> _attachBridge(InAppWebViewController controller) async {
    if (_bridgeMode != 'full' || _disposed) return;
    final bridge = ChatDemoBridge(
      controller: controller,
      origin: chatDemoAssetOrigin,
      onClose: _closePage,
      onOpenSettings: _openSettingsFromBridge,
    );
    final attached = await bridge.attach();
    if (!mounted || _disposed) {
      bridge.dispose();
      return;
    }
    if (!attached) {
      bridge.dispose();
      setState(() => _bridgeMode = 'degraded');
      return;
    }
    _bridge?.dispose();
    _bridge = bridge;
  }

  Future<bool> _closePage() async {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return false;
    navigator.pop();
    return true;
  }

  bool _openSettingsFromBridge() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder:
              (_) =>
                  DeepSeekApiSettingsPage(onClearHistory: _clearLoadedHistory),
        ),
      ),
    );
    return true;
  }

  Future<void> _clearLoadedHistory() async {
    if (_apiKey == null) {
      await ChatDemoStorageService.clearHistory();
      return;
    }
    final controller = _controller;
    if (controller == null || _pageLoading) {
      throw StateError('Chat page is not ready');
    }
    final result = await controller.callAsyncJavaScript(
      functionBody: '''
if (location.origin !== '$chatDemoAssetOrigin' ||
    location.pathname !== '$chatDemoAssetPath') return false;
return await window.__MYCHU_SETTINGS__?.clearHistory();
''',
    );
    if (result?.value != true) {
      throw StateError('Could not clear the active chat history');
    }
  }

  Future<NavigationActionPolicy> _handleNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url == null) return NavigationActionPolicy.CANCEL;
    final value = url.toString();
    if (value.startsWith('$chatDemoAssetOrigin$chatDemoAssetPath')) {
      return NavigationActionPolicy.ALLOW;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
    return NavigationActionPolicy.CANCEL;
  }

  Widget _systemUi(Widget child) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Theme.of(context).colorScheme.surface,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingKey) {
      return _systemUi(
        Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: const AdaptiveLoadingState(),
        ),
      );
    }
    if (_apiKey == null) {
      return _systemUi(_MissingKeyView(onOpenSettings: _openSettings));
    }

    final showBack = ModalRoute.of(context)?.isFirst != true;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return _systemUi(
      Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Stack(
              children: [
                InAppWebView(
                  key: ValueKey(_webViewGeneration),
                  initialSettings: _webViewSettings(),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: _hostConfigScript(showBack: showBack),
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: true,
                      allowedOriginRules: {chatDemoAssetOrigin},
                    ),
                  ]),
                  shouldOverrideUrlLoading: _handleNavigation,
                  onPermissionRequest: (controller, request) async {
                    final source = request.origin.toString().replaceFirst(
                      RegExp(r'/$'),
                      '',
                    );
                    if (source != chatDemoAssetOrigin ||
                        !request.resources.contains(
                          PermissionResourceType.MICROPHONE,
                        )) {
                      return PermissionResponse(
                        action: PermissionResponseAction.DENY,
                      );
                    }
                    final result =
                        await HostPermissionService()
                            .requestMicrophonePermission();
                    return PermissionResponse(
                      resources: request.resources,
                      action:
                          result.granted
                              ? PermissionResponseAction.GRANT
                              : PermissionResponseAction.DENY,
                    );
                  },
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    unawaited(_bootstrap(controller));
                  },
                  onLoadStart: (controller, url) {
                    if (mounted) setState(() => _pageLoading = true);
                  },
                  onLoadStop: (controller, url) {
                    if (mounted) setState(() => _pageLoading = false);
                  },
                  onReceivedError: (controller, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(() {
                        _pageLoading = false;
                        _loadError = '$askYuiName 加载失败，请重试。';
                      });
                    }
                  },
                  onReceivedHttpError: (controller, request, response) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(() {
                        _pageLoading = false;
                        _loadError =
                            '$askYuiName 加载失败（${response.statusCode}）。';
                      });
                    }
                  },
                  onRenderProcessGone: (controller, detail) {
                    _bridge?.dispose();
                    _bridge = null;
                    if (identical(_controller, controller)) _controller = null;
                    if (mounted) {
                      setState(() {
                        _pageLoading = false;
                        _loadError = '$askYuiName 页面已退出，请重试。';
                      });
                    }
                  },
                ),
                if (_pageLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.transparent,
                      child: AdaptiveLoadingState(),
                    ),
                  ),
                if (_loadError != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: AdaptiveErrorState(
                        title: askYuiName,
                        message: _loadError,
                        onRetry: () {
                          _bridge?.dispose();
                          _bridge = null;
                          _controller = null;
                          setState(() {
                            _loadError = null;
                            _pageLoading = true;
                            _webViewGeneration++;
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingKeyView extends StatelessWidget {
  const _MissingKeyView({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(askYuiName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '还没有配置 DeepSeek API Key',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'DeepSeek API Key 是 MyCHU 的应用级配置，不要求登录校园账号。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('配置 DeepSeek API'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
