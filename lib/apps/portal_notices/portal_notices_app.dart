import 'package:flutter/material.dart';

import '../app.dart';
import 'portal_notices_page.dart';
import '../../widgets/apple_window_controls.dart';

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
  builder:
      (_) => Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: const Text('校园公告')),
        ),
        body: const PortalNoticesPanel(),
      ),
);
