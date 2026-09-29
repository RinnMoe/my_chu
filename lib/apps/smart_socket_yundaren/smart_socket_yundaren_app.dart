import 'package:flutter/material.dart';

import '../app.dart';
import 'smart_socket_yundaren_page.dart';

final smartSocketYundarenApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.smart_socket.yundaren',
    name: '云达人',
    description: '无需云达人使用插座',
    iconCodePoint: Icons.power_outlined.codePoint,
    category: AppCategory.life,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const SmartSocketYundarenPage(),
);
