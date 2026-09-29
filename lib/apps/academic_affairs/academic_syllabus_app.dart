import 'package:flutter/material.dart';

import '../app.dart';
import 'academic_syllabus_page.dart';

final academicSyllabusApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.academic.syllabus',
    name: '全校排课查询',
    description: '按学期查询全校课程与排课安排',
    iconCodePoint: Icons.calendar_view_week_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const AcademicSyllabusPage(),
);
