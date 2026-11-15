import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/logging/logger.dart';

/// Receives page failures without changing the page's own error handling.
class WebViewErrorReporting {
  static const handlerName = 'mychuJavaScriptError';
  static const source = r'''
(function() {
  if (window.__mychuErrorReporting) return;
  window.__mychuErrorReporting = true;
  const pending = [];
  function deliver(content) {
    const bridge = window.flutter_inappwebview;
    if (!bridge || typeof bridge.callHandler !== 'function') {
      pending.push(content);
      if (pending.length > 300) pending.shift();
      return;
    }
    bridge.callHandler('mychuJavaScriptError', content).catch(() => {});
  }
  window.addEventListener('flutterInAppWebViewPlatformReady', function() {
    pending.splice(0).forEach(deliver);
  });
  window.addEventListener('error', function(event) {
    // Resource load failures are received through the WebView host callbacks.
    if (!event.message) return;
    const error = event.error;
    deliver([
      event.message,
      event.filename + ':' + event.lineno + ':' + event.colno,
      error && error.stack ? String(error.stack) : ''
    ].join('\n'));
  });
  window.addEventListener('unhandledrejection', function(event) {
    const reason = event.reason;
    deliver('Unhandled promise rejection\n' + String(reason) +
      (reason && reason.stack ? '\n' + String(reason.stack) : ''));
  });
})();
''';

  static UserScript get script => UserScript(
    source: source,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );

  static void attach(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (arguments) {
        if (arguments.isNotEmpty) {
          AppLogger.error(
            arguments.first.toString(),
            context: 'WebView JavaScript',
          );
        }
        return null;
      },
    );
  }
}
