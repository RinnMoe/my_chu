import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../capabilities/manual_login_web_view_page.dart';
import '../../services/service_endpoints.dart';

/// 第二课堂：手动登录 WebView（站点未接入统一身份认证）。
class SecondClassroomPage extends StatelessWidget {
  const SecondClassroomPage({super.key});

  /// 站点通过 localStorage 保存当前学校；在 document start 阶段预置长安大学
  /// 学校信息，避免首次打开先渲染“请选择学校”页面。仅覆盖学校相关四个字段，
  /// 不清空或改动站点其他 Local Storage 数据（登录状态、业务配置、地图缓存等）。
  static final UnmodifiableListView<UserScript> _presetSchoolScripts =
      UnmodifiableListView([
        UserScript(
          source: r'''
        try {
          localStorage.setItem('schoolId', '10710');
          localStorage.setItem('schoolName', '长安大学');
          localStorage.setItem(
            'schoollogo',
            'https://gytx-2ketang.oss-cn-hangzhou.aliyuncs.com/logo/changandx_logo.jpg'
          );
          localStorage.setItem('fromSchool', '{}');
        } catch (e) {
          console.error('[WebView] preset school failed:', e);
        }
      ''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return ManualLoginWebViewPage(
      title: '第二课堂',
      url:
          CampusServiceEndpoints.manualServiceDefinitions
              .firstWhere((service) => service.id == 'second.classroom')
              .entryUrl,
      showBottomBar: false,
      initialUserScripts: _presetSchoolScripts,
    );
  }
}
