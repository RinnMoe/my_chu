import 'package:flutter/material.dart';

import '../app.dart';
import 'experiment_course_selection_page.dart';

final experimentCourseSelectionApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.experiment.course.selection',
    name: '实验选课',
    description: '实验选课与实验课表。',
    iconCodePoint: Icons.event_available_outlined.codePoint,
    category: AppCategory.academic,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const ExperimentCourseSelectionPage(),
);
