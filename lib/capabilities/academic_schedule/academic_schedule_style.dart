import 'package:flutter/material.dart';

enum ScheduleInk { axis, course, border }

@immutable
class AcademicScheduleStyle {
  const AcademicScheduleStyle({
    this.showGrid = false,
    this.showPeriodTime = true,
    this.showSaturday,
    this.showSunday,
    this.showNonCurrent,
    this.tintCourseText = false,
    this.borderUsesCourseColor = true,
    this.headerFontSize = 11,
    this.cellHeight = 68,
    this.cornerRadius = 8,
    this.cellOpacity = 1,
    this.nonCurrentOpacity = 1,
    this.courseFontSize = 12,
    this.inks = const {},
  });

  final bool showGrid;
  final bool showPeriodTime;
  final bool? showSaturday;
  final bool? showSunday;
  final bool? showNonCurrent;
  final bool tintCourseText;
  final bool borderUsesCourseColor;
  final double headerFontSize;
  final double cellHeight;
  final double cornerRadius;
  final double cellOpacity;
  final double nonCurrentOpacity;
  final double courseFontSize;
  final Map<String, Color> inks;

  Color? ink(ScheduleInk role, bool dark) =>
      inks['${role.name}.${dark ? "dark" : "light"}'];

  AcademicScheduleStyle withInk(ScheduleInk role, Color? color, bool dark) {
    final updated = Map<String, Color>.of(inks);
    final key = '${role.name}.${dark ? "dark" : "light"}';
    if (color == null) {
      updated.remove(key);
    } else {
      updated[key] = color;
    }
    return copyWith(inks: Map.unmodifiable(updated));
  }

  /// Reset only the requested preference. Visibility explicitly returns to on,
  /// so an old pre-appearance preference cannot override a user's reset.
  AcademicScheduleStyle reset(String field) {
    final json = Map<String, Object?>.of(toJson())..remove(field);
    if (const {
      'showSaturday',
      'showSunday',
      'showNonCurrent',
    }.contains(field)) {
      json[field] = true;
    }
    return AcademicScheduleStyle.fromJson(json);
  }

  AcademicScheduleStyle copyWith({
    bool? showGrid,
    bool? showPeriodTime,
    bool? showSaturday,
    bool? showSunday,
    bool? showNonCurrent,
    bool? tintCourseText,
    bool? borderUsesCourseColor,
    double? headerFontSize,
    double? cellHeight,
    double? cornerRadius,
    double? cellOpacity,
    double? nonCurrentOpacity,
    double? courseFontSize,
    Map<String, Color>? inks,
  }) => AcademicScheduleStyle(
    showGrid: showGrid ?? this.showGrid,
    showPeriodTime: showPeriodTime ?? this.showPeriodTime,
    showSaturday: showSaturday ?? this.showSaturday,
    showSunday: showSunday ?? this.showSunday,
    showNonCurrent: showNonCurrent ?? this.showNonCurrent,
    tintCourseText: tintCourseText ?? this.tintCourseText,
    borderUsesCourseColor: borderUsesCourseColor ?? this.borderUsesCourseColor,
    headerFontSize: headerFontSize ?? this.headerFontSize,
    cellHeight: cellHeight ?? this.cellHeight,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    cellOpacity: cellOpacity ?? this.cellOpacity,
    nonCurrentOpacity: nonCurrentOpacity ?? this.nonCurrentOpacity,
    courseFontSize: courseFontSize ?? this.courseFontSize,
    inks: inks ?? this.inks,
  );

  Map<String, Object?> toJson() => {
    'showGrid': showGrid,
    'showPeriodTime': showPeriodTime,
    'showSaturday': showSaturday,
    'showSunday': showSunday,
    'showNonCurrent': showNonCurrent,
    'tintCourseText': tintCourseText,
    'borderUsesCourseColor': borderUsesCourseColor,
    'headerFontSize': headerFontSize,
    'cellHeight': cellHeight,
    'cornerRadius': cornerRadius,
    'cellOpacity': cellOpacity,
    'nonCurrentOpacity': nonCurrentOpacity,
    'courseFontSize': courseFontSize,
    'inks': {for (final e in inks.entries) e.key: e.value.toARGB32()},
  };

  factory AcademicScheduleStyle.fromJson(Object? raw) {
    if (raw is! Map) return const AcademicScheduleStyle();
    double number(String key, double fallback, double min, double max) {
      final value = raw[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final inks = <String, Color>{};
    final values = raw['inks'];
    if (values is Map) {
      for (final role in ScheduleInk.values) {
        for (final mode in ['light', 'dark']) {
          final key = '${role.name}.$mode';
          final value = values[key];
          if (value is int && value >= 0 && value <= 0xffffffff) {
            inks[key] = Color(value);
          }
        }
      }
    }
    return AcademicScheduleStyle(
      showGrid: raw['showGrid'] is bool ? raw['showGrid'] as bool : false,
      showPeriodTime:
          raw['showPeriodTime'] is bool ? raw['showPeriodTime'] as bool : true,
      showSaturday:
          raw['showSaturday'] is bool ? raw['showSaturday'] as bool : null,
      showSunday: raw['showSunday'] is bool ? raw['showSunday'] as bool : null,
      showNonCurrent:
          raw['showNonCurrent'] is bool ? raw['showNonCurrent'] as bool : null,
      tintCourseText:
          raw['tintCourseText'] is bool ? raw['tintCourseText'] as bool : false,
      borderUsesCourseColor:
          raw['borderUsesCourseColor'] is bool
              ? raw['borderUsesCourseColor'] as bool
              : true,
      headerFontSize: number('headerFontSize', 11, 9, 18),
      cellHeight: number('cellHeight', 68, 40, 100),
      cornerRadius: number('cornerRadius', 8, 0, 20),
      cellOpacity: number('cellOpacity', 1, 0, 1),
      nonCurrentOpacity: number('nonCurrentOpacity', 1, 0, 1),
      courseFontSize: number('courseFontSize', 12, 9, 18),
      inks: Map.unmodifiable(inks),
    );
  }
}
