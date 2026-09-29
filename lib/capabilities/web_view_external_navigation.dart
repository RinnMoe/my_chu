import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/logger_service.dart';

const _externalPaymentSchemes = {
  'weixin',
  'alipay',
  'alipays',
  'alipayqr',
  'alipayhd',
};

/// Shared external navigation handling for built-in WebViews.
class WebViewExternalNavigationCapability {
  const WebViewExternalNavigationCapability._();

  static bool isExternalPaymentUri(Uri uri) =>
      _externalPaymentSchemes.contains(uri.scheme.toLowerCase());

  static Future<NavigationActionPolicy> handle(
    BuildContext context,
    NavigationAction navigationAction,
  ) async {
    final uri = navigationAction.request.url;
    if (uri == null || !isExternalPaymentUri(uri)) {
      return NavigationActionPolicy.ALLOW;
    }

    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(uri.toString()),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      AppLogger.warn('支付应用调起失败 (${error.runtimeType})');
    }
    if (!launched && context.mounted) {
      await presentExternalPaymentFailure(context);
    }
    return NavigationActionPolicy.CANCEL;
  }
}

/// Presents the failure state without assuming that the host page owns a
/// Material [Scaffold]. WebViews can be hosted by either root presentation.
Future<void> presentExternalPaymentFailure(BuildContext context) async {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('未找到可用的支付应用，请检查微信或支付宝是否已安装。')));
}
