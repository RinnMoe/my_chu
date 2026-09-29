import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Rendering policy for WebViews mounted in the visible Flutter tree.
///
/// Android's default Hybrid Composition keeps the native WebView in the
/// Android view hierarchy, which can lag behind Flutter route transitions.
/// Request Texture Layer Hybrid Composition so the WebView participates in
/// Flutter's compositing path. Other platform implementations ignore this
/// Android-only setting.
class WebViewRenderingPolicy {
  const WebViewRenderingPolicy._();

  static const bool useHybridComposition = false;

  /// Applies the visible WebView policy without changing other settings.
  ///
  /// A page can opt back into Hybrid Composition when its rendering depends on
  /// native WebView behavior that is not reliable in the shared texture mode.
  static InAppWebViewSettings visible(
    InAppWebViewSettings settings, {
    bool? useHybridComposition,
  }) {
    settings.useHybridComposition =
        useHybridComposition ?? WebViewRenderingPolicy.useHybridComposition;
    return settings;
  }
}
