import 'package:flutter/material.dart';

import '../app.dart';
import 'fitness_test_page.dart';

/// 体测计算器：按《国家学生体质健康标准（2014 年修订）》大学阶段的
/// 评分表估算单项得分、标准分、附加分与等级。
///
/// 全部计算在设备本地完成，不请求校园服务，因此不要求登录。
final fitnessTestApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: 'feature.fitness.calculator',
    name: '体测计算器',
    description: '按 2014 年修订标准估算体测总分与等级。',
    iconCodePoint: Icons.monitor_weight_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const FitnessTestPage(),
);
