import 'package:flutter/material.dart';

import '../app.dart';
import 'classroom_usage_page.dart';

/// 空教室查询：只读查询各时段空教室，凭证由统一身份层提供。
final classroomUsageApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.classroom.usage',
    name: '空教室查询',
    description: '查询各时段可用的空教室。',
    iconCodePoint: Icons.meeting_room_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const ClassroomUsagePage(),
);
