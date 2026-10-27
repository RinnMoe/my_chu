import 'package:flutter/material.dart';

import '../app.dart';
import 'charging_pile_page.dart';

final chargingPileApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: 'feature.charging.pile',
    name: '共享充电桩',
    description: '查看渭水校区充电桩实时空位',
    iconCodePoint: Icons.ev_station_outlined.codePoint,
    category: AppCategory.life,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const ChargingPilePage(),
);
