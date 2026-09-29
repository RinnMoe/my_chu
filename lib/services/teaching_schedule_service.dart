import 'package:flutter/foundation.dart';

/// The bell schedule used when turning an academic period into a wall-clock
/// range.  The first entry matches 渭水校区 (the 北校区 table supplied by the
/// university) and is intentionally the default for existing installations.
enum TeachingScheduleMode {
  weishui,
  southCampus;

  String get label => switch (this) {
    TeachingScheduleMode.weishui => '渭水校区',
    TeachingScheduleMode.southCampus => '南校区',
  };
}

@immutable
class TeachingPeriodTime {
  final int period;
  final int startMinute;
  final int endMinute;

  const TeachingPeriodTime({
    required this.period,
    required this.startMinute,
    required this.endMinute,
  }) : assert(period >= 1 && period <= 11),
       assert(startMinute >= 0 && startMinute < 24 * 60),
       assert(endMinute > startMinute && endMinute <= 24 * 60);

  String get startText => _formatMinute(startMinute);
  String get endText => _formatMinute(endMinute);
  String get rangeText => '$startText–$endText';

  DateTime startAt(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
    startMinute ~/ 60,
    startMinute % 60,
  );

  DateTime endAt(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
    endMinute ~/ 60,
    endMinute % 60,
  );

  Map<String, dynamic> toJson() => {
    'period': period,
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  static String _formatMinute(int minute) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(minute ~/ 60)}:${two(minute % 60)}';
  }
}

@immutable
class TeachingSchedule {
  final TeachingScheduleMode mode;
  final List<TeachingPeriodTime> periods;

  const TeachingSchedule({required this.mode, required this.periods});

  TeachingPeriodTime? period(int number) {
    if (number < 1 || number > periods.length) return null;
    return periods[number - 1];
  }

  TeachingPeriodTime? range(int startPeriod, int endPeriod) {
    final start = period(startPeriod);
    final end = period(endPeriod);
    if (start == null || end == null || endPeriod < startPeriod) return null;
    return TeachingPeriodTime(
      period: start.period,
      startMinute: start.startMinute,
      endMinute: end.endMinute,
    );
  }
}

const TeachingSchedule _weishuiSchedule = TeachingSchedule(
  mode: TeachingScheduleMode.weishui,
  periods: [
    TeachingPeriodTime(period: 1, startMinute: 8 * 60 + 30, endMinute: 9 * 60 + 15),
    TeachingPeriodTime(period: 2, startMinute: 9 * 60 + 20, endMinute: 10 * 60 + 5),
    TeachingPeriodTime(period: 3, startMinute: 10 * 60 + 25, endMinute: 11 * 60 + 10),
    TeachingPeriodTime(period: 4, startMinute: 11 * 60 + 15, endMinute: 12 * 60),
    TeachingPeriodTime(period: 5, startMinute: 14 * 60, endMinute: 14 * 60 + 45),
    TeachingPeriodTime(period: 6, startMinute: 14 * 60 + 50, endMinute: 15 * 60 + 35),
    TeachingPeriodTime(period: 7, startMinute: 15 * 60 + 55, endMinute: 16 * 60 + 40),
    TeachingPeriodTime(period: 8, startMinute: 16 * 60 + 45, endMinute: 17 * 60 + 30),
    TeachingPeriodTime(period: 9, startMinute: 19 * 60, endMinute: 19 * 60 + 45),
    TeachingPeriodTime(period: 10, startMinute: 19 * 60 + 50, endMinute: 20 * 60 + 35),
    TeachingPeriodTime(period: 11, startMinute: 20 * 60 + 40, endMinute: 21 * 60 + 25),
  ],
);

const TeachingSchedule _southCampusSchedule = TeachingSchedule(
  mode: TeachingScheduleMode.southCampus,
  periods: [
    TeachingPeriodTime(period: 1, startMinute: 8 * 60, endMinute: 8 * 60 + 45),
    TeachingPeriodTime(period: 2, startMinute: 8 * 60 + 55, endMinute: 9 * 60 + 40),
    TeachingPeriodTime(period: 3, startMinute: 10 * 60 + 10, endMinute: 10 * 60 + 55),
    TeachingPeriodTime(period: 4, startMinute: 11 * 60 + 5, endMinute: 11 * 60 + 50),
    TeachingPeriodTime(period: 5, startMinute: 14 * 60, endMinute: 14 * 60 + 45),
    TeachingPeriodTime(period: 6, startMinute: 14 * 60 + 55, endMinute: 15 * 60 + 40),
    TeachingPeriodTime(period: 7, startMinute: 16 * 60, endMinute: 16 * 60 + 45),
    TeachingPeriodTime(period: 8, startMinute: 16 * 60 + 55, endMinute: 17 * 60 + 40),
    TeachingPeriodTime(period: 9, startMinute: 19 * 60, endMinute: 19 * 60 + 45),
    TeachingPeriodTime(period: 10, startMinute: 19 * 60 + 55, endMinute: 20 * 60 + 40),
    TeachingPeriodTime(period: 11, startMinute: 20 * 60 + 50, endMinute: 21 * 60 + 35),
  ],
);

TeachingSchedule teachingScheduleFor(TeachingScheduleMode mode) {
  return switch (mode) {
    TeachingScheduleMode.weishui => _weishuiSchedule,
    TeachingScheduleMode.southCampus => _southCampusSchedule,
  };
}
