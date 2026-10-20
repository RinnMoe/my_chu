import 'dart:async';
import '../../services/course_live_activity_service.dart';
import '../../services/time_reminder_service.dart';
import '../../services/platform_compatibility_service.dart';
import '../east8_time.dart';
import 'recent_schedule_loader.dart';
import 'recent_schedule.dart';
import 'recent_schedule_repository.dart';

void scheduleAcademicCourseAlerts(String accountKey) {
  unawaited(refreshRecentCourseAlerts(accountKey));
}

Future<void> refreshRecentCourseAlerts(String accountKey, {
  RecentScheduleRepository? repository,
  Future<bool> Function()? isCurrent,
}) async {
  if (isCurrent != null && !await isCurrent()) return;
  if (PlatformCompatibilityService.isAndroid) {
    await CourseLiveActivityService.refresh(accountKey, force: true);
  } else {
    // Preserve existing Apple local reminders; this change only introduces Android live routing.
    await _ordinaryCourses(accountKey, repository: repository, isCurrent: isCurrent);
  }
}

Future<void> _ordinaryCourses(
  String accountKey, {
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
