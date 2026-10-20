import 'package:flutter/material.dart';

import '../../services/teaching_schedule_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_palette.dart';
import 'academic_schedule_appearance.dart';
import 'academic_schedule_background.dart';
import 'academic_schedule_cell_colors.dart';
import 'academic_schedule_style.dart';

/// Fictional courses only: appearance editing never loads a campus timetable.
class AcademicScheduleAppearancePreview extends StatelessWidget {
  const AcademicScheduleAppearancePreview({
    super.key,
    required this.appearance,
    required this.dark,
    this.showSaturday = true,
    this.showSunday = true,
    this.showNonCurrent = true,
  });

  final AcademicScheduleAppearance appearance;
  final bool dark, showSaturday, showSunday, showNonCurrent;

  @override
  Widget build(BuildContext context) {
    final style = appearance.style;
    final days = [
      1,
      2,
      3,
      4,
      5,
      if (style.showSaturday ?? showSaturday) 6,
      if (style.showSunday ?? showSunday) 7,
    ];
    final brightness = dark ? Brightness.dark : Brightness.light;
    final currentScheme = Theme.of(context).colorScheme;
    final scheme =
        currentScheme.brightness == brightness
            ? currentScheme
            : resolveAppColorScheme(
              brightness,
              seedColor: themePreferencesNotifier.value.seedColor,
              pureBlack: themePreferencesNotifier.value.pureBlackEnabled,
            );
    final canvas = appearance.canvas(scheme);
    final axis =
        style.ink(ScheduleInk.axis, dark) ?? readableScheduleForeground(canvas);
    final times = teachingScheduleFor(TeachingScheduleMode.weishui);
    const left = 38.0;
    Widget label(String text, {double? size}) => Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: axis,
        fontSize: size ?? style.headerFontSize,
        height: 1.3,
      ),
    );
    return AcademicScheduleBackground(
      image: appearance.backgroundImage(dark),
      key: const ValueKey('schedule-appearance-preview'),
      color: canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - left) / days.length;
          return Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    SizedBox(
                      width: left,
                      child: label('10月', size: style.headerFontSize - 2),
                    ),
                    for (final day in days)
                      SizedBox(
                        width: width,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: label(
                            '周${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}\n${day + 11}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  child: SizedBox(
                    height: style.cellHeight * 5,
                    child: Stack(
                      children: [
                        if (style.showGrid)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _PreviewGrid(
                                  color: axis.withValues(alpha: axis.a * .18),
                                  left: left,
                                  width: width,
                                  height: style.cellHeight,
                                  days: days.length,
                                ),
                              ),
                            ),
                          ),
                        for (var p = 1; p <= 5; p++)
                          Positioned(
                            left: 0,
                            top: (p - 1) * style.cellHeight,
                            width: left,
                            height: style.cellHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  label('$p'),
                                  if (style.showPeriodTime) ...[
                                    label(
                                      times.period(p)!.startText,
                                      size: style.headerFontSize - 3,
                                    ),
                                    label(
                                      times.period(p)!.endText,
                                      size: style.headerFontSize - 3,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        for (final sample in const [
                          (0, 1, 1, 2, '高等数学', 'WH1201', false),
                          (1, 2, 2, 2, '大学英语', 'WH2303', true),
                          (2, 3, 1, 3, '程序设计', 'WH1102', false),
                          (3, 4, 2, 2, '大学物理', 'WH3405', false),
                          (4, 7, 1, 2, '理论力学', 'WH1202', false),
                        ])
                          if (days.contains(sample.$2) &&
                              (!sample.$7 ||
                                  (style.showNonCurrent ?? showNonCurrent)))
                            Positioned(
                              left: left + days.indexOf(sample.$2) * width + 2,
                              top: (sample.$3 - 1) * style.cellHeight + 2,
                              width: (width - 4).clamp(0, double.infinity),
                              height: sample.$4 * style.cellHeight - 4,
                              child: Builder(
                                builder: (context) {
                                  final colors = academicScheduleCellColors(
                                    sample.$1,
                                    dark: dark,
                                    nonCurrent: sample.$7,
                                    appearance: appearance,
                                  );
                                  return Material(
                                    color: colors.background,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        style.cornerRadius,
                                      ),
                                      side: BorderSide(color: colors.border),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 4,
                                      ),
                                      child: ClipRect(
                                        child: Column(
                                          children: [
                                            if (sample.$7)
                                              Text(
                                                '非本周',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: colors.foreground,
                                                  fontSize:
                                                      style.courseFontSize *
                                                      .75,
                                                ),
                                              ),
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  sample.$5,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: colors.foreground,
                                                    fontSize:
                                                        style.courseFontSize,
                                                    height: 1.15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Text(
                                              sample.$6,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colors.foreground,
                                                fontSize:
                                                    style.courseFontSize * .75,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewGrid extends CustomPainter {
  const _PreviewGrid({
    required this.color,
    required this.left,
    required this.width,
    required this.height,
    required this.days,
  });
  final Color color;
  final double left, width, height;
  final int days;
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = .5;
    for (var d = 0; d <= days; d++) {
      final x = left + width * d;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var p = 0; p <= 5; p++) {
      final y = height * p;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_PreviewGrid old) =>
      color != old.color ||
      left != old.left ||
      width != old.width ||
      height != old.height ||
      days != old.days;
}
