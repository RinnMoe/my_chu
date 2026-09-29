import 'dart:convert';

import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../services/teaching_schedule_service.dart';
import '../east8_time.dart';
import 'academic_schedule_utils.dart';

class AcademicScheduleExportDateMappingException implements Exception {
  final String message;

  const AcademicScheduleExportDateMappingException([
    this.message = '导出范围内的校历日期尚未加载，ICS 导出暂不可用。',
  ]);

  @override
  String toString() => message;
}

/// Pure timetable formatters used by the academic schedule export actions.
/// Calendar output is intentionally a file export rather than a
/// CalendarContract integration, so no calendar permission is needed.
class AcademicScheduleExportService {
  static const _wakeUpColors = <String>[
    '#ffff1744',
    '#fffa6278',
    '#ff2979ff',
    '#ff1de9b6',
    '#ffa375ff',
    '#ffff9100',
    '#ffff3d00',
    '#ff2196f3',
  ];

  static String buildIcs({
    required AcademicPersonalSchedule schedule,
    required TeachingSchedule teachingSchedule,
    required Map<int, DateTime> weekStartDates,
    DateTime? generatedAt,
  }) {
    final stamp = (generatedAt ?? DateTime.now()).toUtc();
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//MyCHU//Academic Schedule//CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escape(schedule.semesterLabel.isEmpty ? '我的课表' : schedule.semesterLabel)}',
    ];
    final maxWeek = schedule.maxWeek;
    for (var week = 1; week <= maxWeek; week++) {
      final weekStart = weekStartDates[week];
      if (weekStart == null) {
        throw const AcademicScheduleExportDateMappingException();
      }
      final date = _dateOnly(weekStart);
      for (final entry in schedule.entries) {
        if (!entry.isVisibleInWeek(week) ||
            entry.weekday < 1 ||
            entry.weekday > 7) {
          continue;
        }
        final range = teachingSchedule.range(
          entry.startPeriod,
          entry.endPeriod,
        );
        if (range == null) continue;
        final occurrenceDate = date.add(Duration(days: entry.weekday - 1));
        final start = range.startAt(occurrenceDate);
        final end = range.endAt(occurrenceDate);
        final key = academicScheduleEntryKey(entry).replaceAll('=', '_');
        final uid =
            '${schedule.semesterId}-$week-${entry.weekday}-${entry.startPeriod}-$key@mychu';
        final summary = entry.displayName.trim().isEmpty
            ? '课程'
            : entry.displayName.trim();
        final description = [
          if (entry.teacher.trim().isNotEmpty) '教师：${entry.teacher.trim()}',
          if (entry.location.trim().isNotEmpty) '地点：${entry.location.trim()}',
          '第$week周 · 第${entry.startPeriod}-${entry.endPeriod}节',
        ].join('；');
        lines.addAll([
          'BEGIN:VEVENT',
          'UID:${_escape(uid)}',
          'DTSTAMP:${_formatUtc(stamp)}',
          'DTSTART:${_formatUtc(east8WallClockToUtcInstant(start))}',
          'DTEND:${_formatUtc(east8WallClockToUtcInstant(end))}',
          'SUMMARY:${_escape(summary)}',
          if (description.isNotEmpty) 'DESCRIPTION:${_escape(description)}',
          if (entry.location.trim().isNotEmpty)
            'LOCATION:${_escape(entry.location.trim())}',
          'END:VEVENT',
        ]);
      }
    }
    lines.add('END:VCALENDAR');
    return '${_foldIcsLines(lines).join('\r\n')}\r\n';
  }

  /// Builds WakeUp's five-line backup format used by `.wakeup_schedule`.
  ///
  /// Sleepy uses the same WakeUp course fields for its shareable JSON, but
  /// the official WakeUp file importer consumes its native backup structure:
  /// time-table settings, period settings, table settings, course bases, and
  /// course details, one JSON value per line.
  static String buildWakeUpSchedule({
    required AcademicPersonalSchedule schedule,
    required TeachingSchedule teachingSchedule,
    required DateTime firstWeekMonday,
  }) {
    final maxWeek = schedule.maxWeek;
    final validEntries = schedule.entries
        .where(
          (entry) =>
              entry.weekday >= 1 &&
              entry.weekday <= 7 &&
              entry.startPeriod >= 1 &&
              entry.endPeriod >= entry.startPeriod &&
              teachingSchedule.range(entry.startPeriod, entry.endPeriod) !=
                  null,
        )
        .toList(growable: false);
    final courseNames = <String, String>{};
    final courseSequences = <String, String>{};
    for (final entry in validEntries) {
      final key = _wakeUpCourseKey(entry);
      courseNames.putIfAbsent(key, () => _wakeUpCourseName(entry));
      courseSequences.putIfAbsent(key, () => entry.courseSequence.trim());
    }
    final courseIds = <String, int>{
      for (var index = 0; index < courseNames.length; index++)
        courseNames.keys.elementAt(index): index,
    };
    const timeTableId = 1;
    const tableId = 1;
    final courseDetails = <Map<String, Object?>>[];
    for (final entry in validEntries) {
      final courseKey = _wakeUpCourseKey(entry);
      final weeks = <int>{
        ...entry.weeks,
        ...entry.practiceWeeks,
      }.where((week) => week >= 1 && week <= maxWeek).toList()..sort();
      if (weeks.isEmpty) {
        weeks.addAll(List<int>.generate(maxWeek, (index) => index + 1));
      }
      for (final range in _continuousRanges(weeks)) {
        courseDetails.add({
          'day': entry.weekday,
          'endTime': '',
          'endWeek': range.$2,
          'id': courseIds[courseKey]!,
          'level': 0,
          'ownTime': false,
          'room': entry.location.trim(),
          'startNode': entry.startPeriod,
          'startTime': '',
          'startWeek': range.$1,
          'step': entry.endPeriod - entry.startPeriod + 1,
          'tableId': tableId,
          'teacher': entry.teacher.trim(),
          'type': 0,
        });
      }
    }

    final name = schedule.semesterLabel.trim().isEmpty
        ? 'MyCHU 课表'
        : schedule.semesterLabel.trim();
    final date = _dateOnly(firstWeekMonday);
    final startDate =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final timeTable = {
      'id': timeTableId,
      'name': name,
      'sameLen': false,
      'courseLen': 50,
      'sameBreakLen': false,
      'theBreakLen': 10,
    };
    final timeDetails = [
      for (final period in teachingSchedule.periods)
        {
          'node': period.period,
          'startTime': period.startText,
          'endTime': period.endText,
          'timeTable': timeTableId,
        },
    ];
    final table = {
      'id': tableId,
      'tableName': name,
      'nodes': teachingSchedule.periods.length,
      'background': '',
      'timeTable': timeTableId,
      'startDate': startDate,
      'maxWeek': maxWeek,
      'itemHeight': 64,
      'itemAlpha': 50,
      'itemTextSize': 12,
      'widgetItemHeight': 0,
      'widgetItemAlpha': 0,
      'widgetItemTextSize': 0,
      'strokeColor': -2130706433,
      'widgetStrokeColor': 0,
      'textColor': -16777216,
      'widgetTextColor': 0,
      'courseTextColor': -1,
      'widgetCourseTextColor': 0,
      'showSat': true,
      'showSun': true,
      'sundayFirst': false,
      'showOtherWeekCourse': true,
      'showTime': false,
      'type': 0,
    };
    final courseBases = [
      for (var index = 0; index < courseNames.length; index++)
        {
          'id': index,
          'courseName': courseNames.values.elementAt(index),
          'color':
              _wakeUpColors[stableCourseColorIndex(
                courseSequences.values.elementAt(index).isEmpty
                    ? courseNames.keys.elementAt(index)
                    : courseSequences.values.elementAt(index),
                colorCount: _wakeUpColors.length,
              )],
          'tableId': tableId,
          'note': '',
          'credit': 0.0,
        },
    ];

    return [
      jsonEncode(timeTable),
      jsonEncode(timeDetails),
      jsonEncode(table),
      jsonEncode(courseBases),
      jsonEncode(courseDetails),
    ].join('\n');
  }

  static List<(int, int)> _continuousRanges(List<int> weeks) {
    if (weeks.isEmpty) return const [];
    final result = <(int, int)>[];
    var start = weeks.first;
    var end = start;
    for (final week in weeks.skip(1)) {
      if (week == end + 1) {
        end = week;
      } else {
        result.add((start, end));
        start = end = week;
      }
    }
    result.add((start, end));
    return result;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _formatUtc(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}T${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}${value.second.toString().padLeft(2, '0')}Z';

  static String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\n');

  /// Folds content lines according to RFC 5545's 75-octet line limit.
  ///
  /// The limit is measured in UTF-8 bytes, not Dart UTF-16 code units.  A
  /// continuation line starts with one space, so it has one fewer byte for
  /// its content.  Iterating by runes keeps surrogate pairs and other
  /// multi-byte characters intact.
  static List<String> _foldIcsLines(Iterable<String> lines) {
    final folded = <String>[];
    for (final line in lines) {
      var remaining = line;
      var firstLine = true;
      if (remaining.isEmpty) {
        folded.add('');
        continue;
      }
      while (remaining.isNotEmpty) {
        final contentLimit = firstLine ? 75 : 74;
        final codeUnitLength = _utf8PrefixCodeUnitLength(
          remaining,
          contentLimit,
        );
        final segment = remaining.substring(0, codeUnitLength);
        folded.add('${firstLine ? '' : ' '}$segment');
        remaining = remaining.substring(codeUnitLength);
        firstLine = false;
      }
    }
    return folded;
  }

  static int _utf8PrefixCodeUnitLength(String value, int maxBytes) {
    var consumedBytes = 0;
    var consumedCodeUnits = 0;
    for (final rune in value.runes) {
      final runeLength = utf8.encode(String.fromCharCode(rune)).length;
      if (consumedBytes + runeLength > maxBytes) break;
      consumedBytes += runeLength;
      consumedCodeUnits += rune > 0xffff ? 2 : 1;
    }
    // Every configured limit is larger than a single UTF-8 code point, but
    // keep the helper total if that assumption ever changes.
    return consumedCodeUnits == 0 ? 1 : consumedCodeUnits;
  }
}

String _wakeUpCourseKey(AcademicPersonalScheduleEntry entry) => jsonEncode([
  entry.courseSequence.trim(),
  entry.courseCode.trim(),
  _wakeUpCourseName(entry),
]);

String _wakeUpCourseName(AcademicPersonalScheduleEntry entry) {
  final name = entry.displayName.trim();
  return name.isEmpty ? '课程' : name;
}
