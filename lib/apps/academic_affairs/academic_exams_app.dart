import 'package:flutter/material.dart';

import '../app.dart';
import 'academic_exams_page.dart';

/// 考试安排：考试安排与日程。
final academicExamsApp = AppDefinition(
  retainsGuestShell: true,
  metadata: AppMetadata(
    id: 'feature.academic.exams',
    name: '考试安排',
    description: '查询考试时间、考场与座位。',
    iconCodePoint: Icons.event_available_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
    defaultPinned: true,
  ),
  builder: (_) => const AcademicExamsPage(),
);
