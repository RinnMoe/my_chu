import 'package:flutter/material.dart';

import '../../capabilities/manual_login_web_view_page.dart';
import '../../services/service_endpoints.dart';

/// 可信电子文档：手动登录 WebView（站点未接入统一身份认证）。
class TrustedDocsPage extends StatelessWidget {
  const TrustedDocsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ManualLoginWebViewPage(
      title: '可信电子文档',
      url:
          CampusServiceEndpoints.manualServiceDefinitions
              .firstWhere((service) => service.id == 'trusted.docs')
              .entryUrl,
    );
  }
}
