import 'package:flutter/material.dart';

import '../app.dart';
import 'shuwei_webview_page.dart';

/// 教务系统：直接打开教务系统网页版（树维 GET 代理 + Cookie 同步）。
final academicWebApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.academic.web',
    name: '教务系统',
    description: '教务系统网页版',
    iconCodePoint: Icons.dashboard_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const ShuweiWebViewPage(),
);
