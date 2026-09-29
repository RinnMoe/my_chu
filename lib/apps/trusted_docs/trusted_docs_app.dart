import 'package:flutter/material.dart';

import '../app.dart';
import 'trusted_docs_page.dart';

/// 可信电子文档：成绩证明等。
///
/// 站点未接入统一身份认证，使用手动登录 WebView；登录凭据由平台 WebView
/// 本机持久化，下次打开无需重复登录。
final trustedDocsApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.trusted.docs',
    name: '可信电子文档',
    description: '成绩证明等',
    iconCodePoint: Icons.verified_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const TrustedDocsPage(),
);
