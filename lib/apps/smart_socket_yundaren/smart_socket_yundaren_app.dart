import 'package:flutter/material.dart';

import '../app.dart';
import 'smart_socket_yundaren_page.dart';

final smartSocketYundarenApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: 'feature.smart_socket.yundaren',
    name: '云达人',
    description: '扫码启动宿舍插座，无需安装云达人。',
    iconCodePoint: Icons.power_outlined.codePoint,
    category: AppCategory.life,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const SmartSocketYundarenPage(),
);
