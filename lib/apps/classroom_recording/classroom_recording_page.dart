import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../services/service_endpoints.dart';

/// 课堂实录页面：宿主先注入根身份，再由静态 SPA 完成认证跳转。
class ClassroomRecordingPage extends StatelessWidget {
  const ClassroomRecordingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWebViewCapability.pageForService(
      title: '课堂实录',
      url: CampusServiceEndpoints.classroomRecordingLiveListUri.toString(),
      serviceId: CampusServices.classroomRecording,
      showBottomBar: false,
      // 课堂实录包含视频/原生 WebView 内容，使用 Hybrid Composition 避免
      // Texture Layer 路径在 Android WebView renderer 异常后留下空白页面。
      useHybridComposition: true,
    );
  }
}
