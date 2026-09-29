import 'package:flutter/material.dart';

import '../app.dart';
import 'tronclass_page.dart';

/// 畅课课件下载：课程课件下载。
final tronclassApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.tronclass.portal',
    name: '畅课课件下载',
    description: '课程课件下载。',
    iconCodePoint: Icons.folder_open_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
    defaultPinned: true,
  ),
  builder: (_) => const TronclassPage(),
);
