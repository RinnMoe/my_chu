import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../services/service_endpoints.dart';

/// 通勤车应用页：由宿主认证 WebView 打开本次换票的短时登录 URL。
class CommuterBusPage extends StatelessWidget {
  const CommuterBusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWebViewCapability.pageForService(
      title: '通勤车',
      url: CampusServiceEndpoints.commuterBusSelectUri.toString(),
      serviceId: CampusServices.commuterBus,
      showBottomBar: false,
    );
  }
}
