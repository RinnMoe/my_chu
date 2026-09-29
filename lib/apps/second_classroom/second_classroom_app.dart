import 'package:flutter/material.dart';

import '../app.dart';
import 'second_classroom_page.dart';

/// 第二课堂：课外活动报名与成长记录。
///
/// 站点未接入统一身份认证，使用手动登录 WebView；登录凭据由平台 WebView
/// 本机持久化，下次打开无需重复登录。
final secondClassroomApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.second.classroom',
    name: '第二课堂',
    description: '活动报名',
    iconCodePoint: Icons.volunteer_activism_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const SecondClassroomPage(),
);
