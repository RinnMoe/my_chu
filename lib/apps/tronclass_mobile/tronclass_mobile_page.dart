import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../services/service_endpoints.dart';

/// 畅课移动端页面：宿主先注入根身份，再由静态 SPA 完成认证跳转。
class TronclassMobilePage extends StatelessWidget {
  const TronclassMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWebViewCapability.pageForService(
      title: '畅课',
      url: CampusServiceEndpoints.tronclassMobileHomeUri.toString(),
      serviceId: CampusServices.tronclassMobile,
      showBottomBar: false,
    );
  }
}
