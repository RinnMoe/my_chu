import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../services/service_endpoints.dart';

/// 图书馆服务应用页：优先由认证 WebView 打开 OPAC，统一身份免登录。
///
/// OPAC 根入口同时提供公开检索页面；统一身份会话暂不可用时仍回退到该公共
/// 入口。页面不持有任何凭证字符串，会话换票、Cookie 播种与持久化全部由底层
/// 凭证层与 `AuthenticatedWebViewCapability` 完成。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWebViewCapability.pageForService(
      title: '图书馆服务',
      url: CampusServiceEndpoints.opacHomeUri.toString(),
      serviceId: CampusServices.libraryOpac,
      allowPublicEntryFallback: true,
    );
  }
}
