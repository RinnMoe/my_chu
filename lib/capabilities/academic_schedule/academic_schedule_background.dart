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

/// Fades the canvas out of the title bar so a background photo continues into
/// the app bar instead of meeting a solid color at a hard horizontal edge.
///
/// It fills the app bar (including the status bar inset) and ends fully
/// transparent at the bottom edge, where the timetable canvas begins.
class AcademicScheduleHeaderFade extends StatelessWidget {
  const AcademicScheduleHeaderFade({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    // AppBar hands its flexible space loose constraints, so the gradient has
    // to claim the full app bar box explicitly.
    child: SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: .92),
              color.withValues(alpha: .58),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .58, 1],
          ),
        ),
      ),
    ),
  );
}
