import 'package:flutter/material.dart';

import '../../capabilities/manual_login_web_view_page.dart';
import '../../services/service_endpoints.dart';

/// 学信网：站点未接入统一身份认证，使用手动登录 WebView。
class XuexinPage extends StatelessWidget {
  const XuexinPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ManualLoginWebViewPage(
      title: '学信网',
      url:
          CampusServiceEndpoints.manualServiceDefinitions
              .firstWhere((service) => service.id == 'xuexin')
              .entryUrl,
    );
  }
}
