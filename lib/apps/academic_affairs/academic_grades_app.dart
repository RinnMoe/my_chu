import 'package:flutter/material.dart';

import '../app.dart';
import 'academic_grades_page.dart';

/// 成绩查询：成绩、绩点与学分。
final academicGradesApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.academic.grades',
    name: '成绩',
    description: '成绩、绩点与学分',
    iconCodePoint: Icons.grade_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const AcademicGradesPage(),
);
