import 'package:flutter/material.dart';

import '../app.dart';
import 'tronclass_mobile_page.dart';

/// 畅课 APP：通过统一身份认证打开移动端畅课页面。
final tronclassMobileApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.tronclass.mobile',
    name: '畅课',
    description: '畅课APP',
    iconCodePoint: Icons.play_circle_outline.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const TronclassMobilePage(),
);
