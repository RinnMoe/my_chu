import 'package:flutter/material.dart';

import 'page_preferences/bottom_bar_section.dart';
import 'page_preferences/focus_section.dart';

/// 底栏与页面偏好：底栏设置与焦点页内容的统一设置入口。
///
/// 单列 Inset Grouped Settings List：每个分组由外置标题与独立圆角卡片组成，
/// 不再提供左右子 Tab 或平板双栏菜单。底栏的启用、排序与应用首页是同一个
/// 分组，不再单独列一遍底栏。
class PagePreferencesPage extends StatelessWidget {
  const PagePreferencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('底栏与页面偏好')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          BottomBarSection(),
          SizedBox(height: 24),
          FocusSection(),
        ],
      ),
    );
  }
}
