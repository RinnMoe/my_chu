import 'package:flutter/material.dart';

import '../app.dart';
import 'portal_personal_page.dart';

/// 个人数据：个人状态、任务中心与课程待办。
final portalPersonalApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.portal.personal',
    name: '个人数据',
    description: '校园卡、邮箱、图书、任务中心与课程待办。',
    iconCodePoint: Icons.account_balance_wallet_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
    removable: false,
    defaultPinned: true,
  ),
  builder: (_) => const PortalPersonalPage(),
);
