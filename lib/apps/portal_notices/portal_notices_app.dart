import 'package:flutter/material.dart';

import '../app.dart';
import '../../pages/notifications_page.dart';

/// 通知公告：校园通知与公告，支持关键词搜索、栏目与类型筛选。
final portalNoticesApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.portal.notices',
    name: '通知公告',
    description: '校园通知与公告，支持搜索和筛选。',
    iconCodePoint: Icons.campaign_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
    removable: false,
  ),
  builder: (_) => const NotificationsPage(initialTabIndex: 1),
);
