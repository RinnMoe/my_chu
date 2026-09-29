import 'package:flutter/material.dart';

import '../app.dart';
import 'quality_assurance_page.dart';

/// 质保系统（商鼎）：WebView 打开教学质量管理平台（教学质量评价、问卷、
/// 学业预警等），凭证与换票全部由底层统一身份层完成。
final qualityAssuranceApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.quality.assurance',
    name: '评教系统',
    description: '教学质量评价',
    iconCodePoint: Icons.fact_check_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const QualityAssurancePage(),
);
