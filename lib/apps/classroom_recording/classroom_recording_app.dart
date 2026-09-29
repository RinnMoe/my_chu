import 'package:flutter/material.dart';

import '../app.dart';
import 'classroom_recording_page.dart';

/// 课堂实录：课堂直播和回放。
final classroomRecordingApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.classroom.recording',
    name: '课堂实录',
    description: '课堂直播和回放',
    iconCodePoint: Icons.video_library_outlined.codePoint,
    category: AppCategory.learning,
    developmentFlag: DevelopmentFlag.none,
  ),
  builder: (_) => const ClassroomRecordingPage(),
);
