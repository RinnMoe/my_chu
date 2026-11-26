import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 通过同源 clear.html 清理 chat-demo 的 IndexedDB、localStorage 和缓存。
///
/// 使用独立的 Headless WebView，因此可以从原生设置页调用，不需要 AI 页面
/// 保持打开；不会读取或修改 API Key。
abstract final class ChatDemoStorageService {
  static const _origin = 'https://appassets.androidplatform.net';
  static const _clearUrl =
      '$_origin/assets/flutter_assets/assets/chat_demo/clear.html';

  static Future<void> clearHistory() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Chat history clearing is Android-only');
    }

    final completer = Completer<void>();
    var settled = false;
    HeadlessInAppWebView? webView;

    void completeError(Object error) {
      if (!settled) {
        settled = true;
        completer.completeError(error);
      }
    }

    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_clearUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        webViewAssetLoader: WebViewAssetLoader(
          domain: 'appassets.androidplatform.net',
          pathHandlers: [AssetsPathHandler(path: '/assets/')],
        ),
      ),
      onLoadStop: (controller, url) async {
        if (settled) return;
        try {
          final result = await controller.callAsyncJavaScript(
            functionBody: 'return await window.clearMyChuChatDemo();',
          );
          final value = result?.value;
          if (value is Map && value['database'] == 'deleted') {
            settled = true;
            completer.complete();
          } else {
            completeError(
              StateError(
                'Chat storage cleanup failed: ${result?.error ?? value}',
              ),
            );
          }
        } on Object catch (diagnosticError) {
          completeError(diagnosticError);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true) {
          completeError(
            StateError(
              'Chat storage cleanup page failed: ${error.description}',
            ),
          );
        }
      },
    );

    try {
      await webView.run();
      await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      try {
        await webView.dispose();
      } on Object {
        // Headless WebView may already be torn down by a page failure.
      }
    }
  }
}
