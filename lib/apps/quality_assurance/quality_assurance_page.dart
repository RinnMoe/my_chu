import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../services/service_endpoints.dart';

/// 评教系统（商鼎）应用页：由认证 WebView 打开底层换票得到的会话入口。
///
/// 页面不持有任何凭证字符串；登录态（带 `userToken` 的 caslogin 会话 URL 与 Cookie
/// 播种）全部由 `AuthenticatedWebViewCapability` 与底层凭证层完成，商鼎 SPA
/// 自行换取并使用 `Authorization: Bearer<token>`。
class QualityAssurancePage extends StatelessWidget {
  const QualityAssurancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWebViewCapability.pageSessionForService(
      title: '评教系统',
      serviceId: CampusServices.qualityAssurance,
      showBottomBar: false,
    );
  }
}
