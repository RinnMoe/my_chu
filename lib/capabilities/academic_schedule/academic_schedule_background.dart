import 'dart:io';
import 'package:flutter/material.dart';
import 'academic_schedule_background_store.dart';

/// Shared canvas for the actual timetable and its appearance preview.
class AcademicScheduleBackground extends StatelessWidget {
  const AcademicScheduleBackground({
    super.key,
    required this.color,
    required this.image,
    required this.child,
  });
  final Color color;
  final String? image;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: color),
      if (image != null)
        FutureBuilder<File>(
          future: AcademicScheduleBackgroundStore.file(image!),
          builder:
              (context, snapshot) =>
                  snapshot.hasData
                      ? Image.file(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        cacheWidth: 1536,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      )
                      : const SizedBox.shrink(),
        ),
      if (image != null) ColoredBox(color: color.withValues(alpha: .35)),
      child,
    ],
  );
}
