import 'package:flutter/material.dart';

import '../app.dart';
import 'library_page.dart';

/// 图书馆服务：馆藏图书检索、图书借阅。
///
/// 站点已接入统一身份认证，通过底层凭证层免登录访问。
final libraryApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.library.opac',
    name: '图书馆服务',
    description: '馆藏图书检索、图书借阅',
    iconCodePoint: Icons.local_library_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const LibraryPage(),
);
