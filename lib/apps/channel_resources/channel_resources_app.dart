import 'package:flutter/material.dart';

import '../app.dart';
import 'channel_resources_page.dart';

/// 频道资料站：原生校园资料与账号服务。
final channelResourcesApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.channel.resources',
    name: '频道资料站',
    description: '校园学习资料与频道服务',
    iconCodePoint: Icons.folder_open_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const ChannelResourcesPage(),
);
