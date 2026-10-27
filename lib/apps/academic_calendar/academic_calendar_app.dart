import 'package:flutter/material.dart';

import '../app.dart';
import 'academic_calendar_page.dart';

final academicCalendarApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.academic.calendar',
    name: '校历',
    description: '查看教学周、节假日与校历安排。',
    iconCodePoint: Icons.date_range_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const AcademicCalendarPage(),
);
