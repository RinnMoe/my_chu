import 'package:flutter/material.dart';
import '../../capabilities/dorm_electricity.dart';
import '../app.dart';
import 'dorm_electricity_page.dart';

final dormElectricityApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: dormElectricityFeatureId,
    name: '宿舍电费',
    description: '查询宿舍电表余额与用电账单',
    iconCodePoint: Icons.bolt_outlined.codePoint,
    category: AppCategory.life,
    developmentFlag: DevelopmentFlag.none,
    showInNavigation: true,
    navigationLabel: '电费',
  ),
  builder: (_) => const DormElectricityPage(),
);
