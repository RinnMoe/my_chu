import 'package:flutter/material.dart';

import '../app.dart';
import 'xuexin_page.dart';

/// 学信网：通过手动登录 WebView 使用学信网网页服务。
final xuexinApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: 'feature.xuexin',
    name: '学信网',
    description: '查询学信网学籍与学历（需学信网账号）。',
    iconCodePoint: Icons.school_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const XuexinPage(),
);
