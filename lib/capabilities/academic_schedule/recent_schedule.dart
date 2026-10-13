import 'dart:convert';

import '../east8_time.dart';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../services/teaching_schedule_service.dart';
import 'academic_schedule_utils.dart';

String recentScheduleDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

enum RecentScheduleSource { roomis, roomisCache, academic, unavailable }

/// A dated occurrence, independent of the editable semester timetable.
class RecentCourse {
  final String id;
  final String name;
  final String location;
  final DateTime start;
  final DateTime end;
  final int? startPeriod;
  final int? endPeriod;
  final String? academicEntryKey;

  const RecentCourse({
    required this.id,
    required this.name,
    required this.location,
    required this.start,
    required this.end,
    this.startPeriod,
    this.endPeriod,
    this.academicEntryKey,
  });

  String get timeLabel => '${_time(start)}–${_time(end)}';
  String get periodLabel =>
      startPeriod == null
          ? ''
          : startPeriod == endPeriod
          ? '第$startPeriod节'
          : '第$startPeriod–$endPeriod节';
  bool get isFirstPeriod => startPeriod == 1;
  String get earlyClassKey => academicEntryKey ?? id;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': location,
    'start': east8WallClockToUtcInstant(start).toIso8601String(),
    'end': east8WallClockToUtcInstant(end).toIso8601String(),
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
  };

  factory RecentCourse.fromJson(Map<String, dynamic> json) {
    final start = parseEast8(json['start'] as String?);
    final end = parseEast8(json['end'] as String?);
    final id = json['id'];
    final name = json['name'];
    final location = json['location'];
    final begin = json['startPeriod'];
    final finish = json['endPeriod'];
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        location is! String ||
        (begin != null && (begin is! int || begin < 1)) ||
        (finish != null &&
            (finish is! int || begin == null || finish < begin)) ||
        ((begin == null) != (finish == null))) {
      throw const FormatException('近期课程数据无效');
    }
    return RecentCourse(
      id: id,
      name: name.trim(),
      location: location,
      start: start,
      end: end,
      startPeriod: begin as int?,
      endPeriod: finish as int?,
    );
  }
}

/// Group adjacent periods for compact presentation, without modifying the
/// independently cached occurrences used by reminders and live activities.
List<RecentCourse> groupRecentCourseRows(Iterable<RecentCourse> courses) {
  final sorted = courses.toList()..sort((a, b) => a.start.compareTo(b.start));
  final rows = <RecentCourse>[];
  for (final course in sorted) {
    final previous = rows.lastOrNull;
    final gap = previous == null ? null : course.start.difference(previous.end);
    if (previous != null &&
        previous.name == course.name &&
        previous.location == course.location &&
        recentScheduleDate(previous.start) ==
            recentScheduleDate(course.start) &&
        previous.endPeriod != null &&
        course.startPeriod == previous.endPeriod! + 1 &&
        gap! >= Duration.zero &&
        gap <= const Duration(minutes: 30)) {
      rows[rows.length - 1] = RecentCourse(
        id: previous.id,
        name: previous.name,
        location: previous.location,
        start: previous.start,
        end: course.end,
        startPeriod: previous.startPeriod,
        endPeriod: course.endPeriod,
        academicEntryKey: previous.academicEntryKey,
      );
    } else {
      rows.add(course);
    }
  }
  return List.unmodifiable(rows);
}

String _time(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class RecentScheduleWindow {
  final String startDate;
  final String endDate;
  final DateTime fetchedAt;
  final List<RecentCourse> courses;

  RecentScheduleWindow({
    required this.startDate,
    required this.endDate,
    required this.fetchedAt,
    required List<RecentCourse> courses,
  }) : courses = List.unmodifiable(courses);

  bool covers(DateTime date) {
    final key = recentScheduleDate(date);
    return key.compareTo(startDate) >= 0 && key.compareTo(endDate) <= 0;
  }

  Map<String, dynamic> toJson() => {
    'startDate': startDate,
    'endDate': endDate,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'courses': courses.map((course) => course.toJson()).toList(),
  };

  factory RecentScheduleWindow.fromJson(Map<String, dynamic> json) {
    final start = json['startDate'] as String;
    final end = json['endDate'] as String;
    final first = DateTime.parse(start);
    final last = DateTime.parse(end);
    if (recentScheduleDate(first) != start ||
        recentScheduleDate(last) != end ||
        last.difference(first).inDays != 6) {
      throw const FormatException('近期排程日期范围无效');
    }
    final courses =
        (json['courses'] as List)
            .map(
              (raw) =>
                  RecentCourse.fromJson(Map<String, dynamic>.from(raw as Map)),
            )
            .toList();
    if (courses.any(
      (course) =>
          recentScheduleDate(course.start).compareTo(start) < 0 ||
          recentScheduleDate(course.start).compareTo(end) > 0,
    )) {
      throw const FormatException('近期课程超出日期范围');
    }
    return RecentScheduleWindow(
      startDate: start,
      endDate: end,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String).toUtc(),
      courses: courses,
    );
  }
}

RecentScheduleWindow parseRoomisSchedule(
  String body,
  DateTime today, {
  required DateTime fetchedAt,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! List) throw const FormatException('ROOMIS 排程响应无效');
  final courses = <RecentCourse>[];
  final ids = <String>{};
  for (final raw in decoded) {
    if (raw is! Map) throw const FormatException('ROOMIS 排程条目无效');
    if (raw['eventType'] != 'TIMETABLE') {
      if (raw['eventType'] is! String) {
        throw const FormatException('ROOMIS 排程类型缺失');
      }
      continue;
    }
    final start = parseEast8(raw['start'] as String?);
    final end = parseEast8(raw['end'] as String?);
    final title = raw['title'];
    final id = raw['id'];
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        title is! String ||
        title.trim().isEmpty ||
        (id is! String && id is! int) ||
        raw['date'] != recentScheduleDate(start)) {
      throw const FormatException('ROOMIS 课程字段无效');
    }
    final begin = raw['beginSlot'];
    final finish = raw['endSlot'];
    final validPeriods =
        begin is int && finish is int && begin > 0 && finish >= begin;
    final displayRoom = raw['spaceDisplayName'];
    final room =
        displayRoom is String && displayRoom.trim().isNotEmpty
            ? displayRoom
            : raw['spaceName'] ?? '';
    final places = <String>[];
    var place = raw['location'];
    for (var depth = 0; depth < 8 && place is Map; depth++) {
      if (place['name'] is String) places.add(place['name'] as String);
      place = place['parent'];
    }
    final location = [
      if (room is String) room,
      ...places,
    ].where((part) => part.trim().isNotEmpty).toSet().join(' · ');
    if (room is! String) throw const FormatException('ROOMIS 教室字段无效');
    final key = 'roomis:$id:${recentScheduleDate(start)}';
    if (!ids.add(key)) continue;
    courses.add(
      RecentCourse(
        id: key,
        name: title.trim(),
        location: location,
        start: start,
        end: end,
        startPeriod: validPeriods ? begin : null,
        endPeriod: validPeriods ? finish : null,
      ),
    );
  }
  courses.sort((a, b) => a.start.compareTo(b.start));
  return RecentScheduleWindow.fromJson(
    RecentScheduleWindow(
      startDate: recentScheduleDate(today),
      endDate: recentScheduleDate(today.add(const Duration(days: 6))),
      fetchedAt: fetchedAt,
      courses: courses,
    ).toJson(),
  );
}

class RecentScheduleDay {
  final RecentScheduleSource source;
  final List<RecentCourse> courses;
  final DateTime? fetchedAt;
  const RecentScheduleDay(this.source, this.courses, {this.fetchedAt});
  bool get available => source != RecentScheduleSource.unavailable;
  String get sourceLabel => switch (source) {
    RecentScheduleSource.roomis => '',
    RecentScheduleSource.roomisCache => '课程待更新',
    RecentScheduleSource.academic => '课程可能未反映调休',
    RecentScheduleSource.unavailable => '课程暂不可用',
  };
}

/// Empty covered days are authoritative; the two datasets are never merged.
RecentScheduleDay resolveRecentScheduleDay({
  required DateTime date,
  RecentScheduleWindow? window,
  bool fresh = false,
  AcademicPersonalSchedule? academic,
  CurrentTeachingWeek? teachingWeek,
  TeachingSchedule? teaching,
  bool holiday = false,
}) {
  if (window != null && window.covers(date)) {
    final courses =
        window.courses
            .where(
              (course) =>
                  recentScheduleDate(course.start) == recentScheduleDate(date),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return RecentScheduleDay(
      fresh ? RecentScheduleSource.roomis : RecentScheduleSource.roomisCache,
      courses,
      fetchedAt: window.fetchedAt,
    );
  }
  if (academic == null || teachingWeek == null || teaching == null) {
    return const RecentScheduleDay(RecentScheduleSource.unavailable, []);
  }
  final week = scheduleWeekForDate(academic, teachingWeek, date);
  if (week == null) {
    return const RecentScheduleDay(RecentScheduleSource.academic, []);
  }
  final courses = <RecentCourse>[];
  if (!holiday) {
    for (final entry in filterScheduleEntriesForDay(
      academic.entries,
      weekday: date.weekday,
      week: week,
    )) {
      final time = teaching.range(entry.startPeriod, entry.endPeriod);
      if (time == null) continue;
      courses.add(
        RecentCourse(
          id:
              '${entry.courseSequence}:$week:${entry.weekday}:${entry.startPeriod}',
          name: entry.displayName,
          location: entry.location,
          start: time.startAt(date),
          end: time.endAt(date),
          startPeriod: entry.startPeriod,
          endPeriod: entry.endPeriod,
          academicEntryKey: academicScheduleEntryKey(entry),
        ),
      );
    }
  }
  courses.sort((a, b) => a.start.compareTo(b.start));
  return RecentScheduleDay(RecentScheduleSource.academic, courses);
}
