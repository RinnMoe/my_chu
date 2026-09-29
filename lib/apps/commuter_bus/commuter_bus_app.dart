import 'package:flutter/material.dart';

import '../app.dart';
import 'commuter_bus_page.dart';

/// 通勤车：通过统一身份认证 WebView 打开通勤车网页。
final commuterBusApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.commuter.bus',
    name: '通勤车',
    description: '通勤车班次查询',
    iconCodePoint: Icons.directions_bus_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const CommuterBusPage(),
);
