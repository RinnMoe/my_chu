import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../capabilities/web_view_rendering_policy.dart';

/// 承载邮件 HTML 文档的 WebView。
///
/// 只负责显示与拦截导航：文档内容由 `MailHtmlDocument` 生成，页面里的链接
/// 不会在 WebView 内跳转，而是回到原生确认或交给自定义动作处理。
class MailHtmlView extends StatefulWidget {
  final String document;

  /// 正文里的 http/https/mailto 链接。
  final ValueChanged<Uri>? onOpenLink;

  /// 文档内的 `mychu://` 动作，例如附件、回复、回复全部、转发、显示图片。
  final ValueChanged<Uri>? onAction;

  const MailHtmlView({
    super.key,
    required this.document,
    this.onOpenLink,
    this.onAction,
  });

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView> {
  InAppWebViewController? _controller;
  String? _loaded;

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    if (document != _loaded) {
      _loaded = document;
      if (_controller != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
      }
    }

    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: document,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: _settings(),
      onWebViewCreated: (controller) => _controller = controller,
      shouldOverrideUrlLoading: (_, action) => _handleNavigation(action),
    );
  }

  InAppWebViewSettings _settings() => WebViewRenderingPolicy.visible(
    InAppWebViewSettings(
      // 邮件文档不含脚本，也不需要脚本；页面交互全部走导航拦截。
      javaScriptEnabled: false,
      transparentBackground: true,
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,
      overScrollMode: OverScrollMode.NEVER,
      supportZoom: false,
      builtInZoomControls: false,
      displayZoomControls: false,
      useShouldOverrideUrlLoading: true,
      useOnDownloadStart: false,
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
      geolocationEnabled: false,
      thirdPartyCookiesEnabled: false,
      domStorageEnabled: false,
      databaseEnabled: false,
      cacheEnabled: false,
      clearCache: true,
      incognito: true,
      mediaPlaybackRequiresUserGesture: true,
      useWideViewPort: false,
      loadWithOverviewMode: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      safeBrowsingEnabled: true,
      allowsLinkPreview: false,
      isInspectable: false,
    ),
  );

  Future<void> _reload() async {
    final controller = _controller;
    if (!mounted || controller == null) return;
    try {
      await controller.loadData(
        data: widget.document,
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
    } on Object {
      // 重新加载失败时保留当前内容。
    }
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.CANCEL;
    final parsed = Uri.tryParse(uri.toString());
    if (parsed == null) return NavigationActionPolicy.CANCEL;

    if (parsed.scheme == 'mychu') {
      widget.onAction?.call(parsed);
      return NavigationActionPolicy.CANCEL;
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https' || scheme == 'mailto') {
      widget.onOpenLink?.call(parsed);
    }
    return NavigationActionPolicy.CANCEL;
  }
}
