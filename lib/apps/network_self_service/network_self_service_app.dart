import 'package:flutter/material.dart';

import '../app.dart';
import 'network_self_service_page.dart';

final networkSelfServiceApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.network.self_service',
    name: '网络自服',
    description: '校园网套餐信息与在线设备状态。',
    iconCodePoint: Icons.wifi_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const NetworkSelfServicePage(),
);
