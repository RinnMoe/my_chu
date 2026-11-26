import 'package:flutter/material.dart';

import '../app.dart';
import '../../capabilities/chat_demo/chat_demo_brand.dart';
import '../../capabilities/chat_demo/chat_demo_page.dart';

/// 问 Yui 的对话界面由随包 chat-demo 提供。
final AppDefinition aiAssistantApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: aiAssistantFeatureId,
    name: askYuiName,
    description: 'ProjectYui 的校园对话入口',
    iconCodePoint: Icons.auto_awesome_outlined.codePoint,
    category: AppCategory.life,
    developmentFlag: DevelopmentFlag.beta,
    defaultPinned: false,
    showInNavigation: true,
    navigationLabel: 'Yui',
  ),
  builder: (_) => const ChatDemoPage(),
);
