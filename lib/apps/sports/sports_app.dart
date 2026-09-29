import 'package:flutter/material.dart';

import '../app.dart';
import 'sports_page.dart';

/// 长大体育：场馆预约、体测成绩查询、体育选课。
///
/// 页面使用宿主统一身份认证 WebView，站点自身负责完成 OAuth 跳转。
final sportsApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.sports.portal',
    name: '长大体育',
    description: '场馆预约、体测成绩查询、体育选课',
    iconCodePoint: Icons.fitness_center_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const SportsPage(),
);
