import 'dart:async';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../services/time_reminder_service.dart';
import '../east8_time.dart';
import 'recent_schedule_loader.dart';
import 'recent_schedule.dart';
import 'recent_schedule_repository.dart';

void scheduleAcademicCourseAlerts(
  String accountKey,
  AcademicPersonalSchedule schedule,
) {
  unawaited(_schedule(accountKey, schedule));
}

Future<void> refreshRecentCourseAlerts(
  String accountKey, {
  RecentScheduleRepository? repository,
  Future<bool> Function()? isCurrent,
}) => _schedule(accountKey, null, repository: repository, isCurrent: isCurrent);

Future<void> _schedule(
  String accountKey,
  AcademicPersonalSchedule? schedule, {
  RecentScheduleRepository? repository,
  Future<bool> Function()? isCurrent,
}) {
  final covered = <int>[];
  return TimeReminderService.replaceEvents(
    accountKey,
    TimeReminderCategory.course,
    () async {
      final now = east8Now();
      final today = DateTime(now.year, now.month, now.day);
      final dates = List.generate(
        15,
        (offset) => today.add(Duration(days: offset)),
      );
      final days = await loadRecentScheduleDays(
        accountKey,
        dates,
        readSchedule: schedule == null ? null : (_) async => schedule,
        repository: repository,
      );
      if (isCurrent != null && !await isCurrent()) return null;
      for (var i = 0; i < days.length; i++) {
        if (days[i].source != RecentScheduleSource.unavailable) {
          covered.add(
            east8WallClockToUtcInstant(dates[i]).millisecondsSinceEpoch,
          );
        }
      }
      if (covered.isEmpty) return null;
      return [
        for (final day in days)
          for (final course in day.courses)
            TimeReminderEvent(
              id: course.id,
              at: east8WallClockToUtcInstant(course.start),
              title: '即将上课：${course.name}',
              body: [
                '${course.start.hour.toString().padLeft(2, '0')}:${course.start.minute.toString().padLeft(2, '0')}',
                if (course.location.trim().isNotEmpty) course.location.trim(),
              ].join(' · '),
            ),
      ];
    },
    coveredDays: () => covered,
  );
}
