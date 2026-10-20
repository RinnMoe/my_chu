import 'package:flutter/material.dart';
import '../app.dart';
import 'tronclass_rollcall_page.dart';

const tronclassRollcallAppId = 'feature.tronclass.rollcall';

final tronclassRollcallApp = AppDefinition(
  metadata: AppMetadata(
    id: tronclassRollcallAppId,
    name: '畅课签到',
    description: '查看进行中的点名并手动应答。',
    iconCodePoint: Icons.qr_code_2_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const TronclassRollcallPage(),
);
