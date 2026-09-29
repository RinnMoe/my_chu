import 'dart:async';

import '../alert_center.dart';
import '../alert_models.dart';
import '../east8_time.dart';
import '../../services/campus_settings_service.dart';
import '../../services/teaching_schedule_service.dart';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import 'academic_schedule_store.dart';
import 'academic_schedule_utils.dart';

const academicScheduleAlertProviderId = 'academic.schedule.before_class';
const academicScheduleNextDayAlertProviderId =
    'academic.schedule.next_day_first_class';

final academicScheduleAlertProvider = AlertProvider(
  id: academicScheduleAlertProviderId,
  source: '我的课表',
  title: '课前提醒',
  kind: AlertKind.deadline,
  severity: AlertSeverity.warning,
  defaultEnabled: false,
  refreshScheduled: _refreshBeforeClassAlerts,
  params: const [
    AlertParamSpec(
      key: 'leadTimeMinutes',
      label: '提前提醒',
      type: AlertParamType.minutes,
      defaultValue: 30,
      min: 10,
      max: 120,
      unit: '分钟',
    ),
  ],
  evaluate: (_, __) => const [],
);

final academicScheduleNextDayAlertProvider = AlertProvider(
  id: academicScheduleNextDayAlertProviderId,
  source: '我的课表',
  title: '明日早八提醒',
  kind: AlertKind.deadline,
  severity: AlertSeverity.warning,
  defaultEnabled: true,
  params: const [
    AlertParamSpec(
      key: 'reminderHour',
      label: '提醒时间',
      type: AlertParamType.number,
      defaultValue: 21,
      min: 18,
      max: 23,
      unit: '点',
    ),
  ],
  refreshScheduled: _refreshNextDayFirstClassAlerts,
  evaluate: (_, __) => const [],
);

void scheduleAcademicCourseAlerts(
  String accountKey,
  AcademicPersonalSchedule schedule,
) {
  unawaited(_schedule(accountKey, schedule));
  unawaited(_scheduleNextDayFirstClass(accountKey, schedule));
}

Future<void> _refreshBeforeClassAlerts(String accountKey) async {
  final schedule = await AcademicScheduleStore().readCachedCurrentSchedule(
    accountKey,
  );
  if (schedule == null) {
    await AlertCenterService.clearScheduled(
      accountKey,
      academicScheduleAlertProviderId,
    );
    return;
  }
  await _schedule(accountKey, schedule);
}

Future<void> _refreshNextDayFirstClassAlerts(String accountKey) async {
  final schedule = await AcademicScheduleStore().readCachedCurrentSchedule(
    accountKey,
  );
  if (schedule == null) {
    await AlertCenterService.clearScheduled(
      accountKey,
      academicScheduleNextDayAlertProviderId,
    );
    return;
  }
  await _scheduleNextDayFirstClass(accountKey, schedule);
}

Future<void> _schedule(
  String accountKey,
  AcademicPersonalSchedule schedule,
) async {
  try {
    await AlertCenterService.rebuildScheduled(
      accountKey,
      academicScheduleAlertProviderId,
      (params) async {
        final state = await AcademicCalendarService()
            .fetchCurrentCalendarState();
        final current = state.teachingWeek;
        final termStart = current?.termStartDate;
        if (current == null ||
            termStart == null ||
            scheduleWeekForTeachingWeek(schedule, current) == null) {
          return null;
        }
        final minutes = (params['leadTimeMinutes'] as num?)?.round() ?? 30;
        final lead = Duration(minutes: minutes.clamp(10, 120));
        final now = east8Now();
        final today = DateTime(now.year, now.month, now.day);
        final teaching = teachingScheduleFor(
          await campusSettingsService.scheduleModeFor(accountKey),
        );
        final drafts = <ScheduledAlertDraft>[];
        for (var offset = 0; offset < 14; offset++) {
          final date = today.add(Duration(days: offset));
          final week = scheduleWeekForDate(schedule, current, date);
          if (week == null) continue;
          for (final entry in filterScheduleEntriesForDay(
            schedule.entries,
            weekday: date.weekday,
            week: week,
          )) {
            final range = teaching.range(entry.startPeriod, entry.endPeriod);
            if (range == null) continue;
            final start = range.startAt(date);
            drafts.add(
              ScheduledAlertDraft(
                eventId:
                    '${entry.courseSequence}:$week:${entry.weekday}:${entry.startPeriod}',
                triggerAt: east8WallClockToUtcInstant(start.subtract(lead)),
                title: '即将上课：${entry.displayName}',
                body: [
                  if (entry.location.trim().isNotEmpty) entry.location.trim(),
                  '${_two(start.hour)}:${_two(start.minute)}',
                ].join(' · '),
                deeplinkAppId: 'feature.academic.schedule',
                validUntil: east8WallClockToUtcInstant(start),
              ),
            );
          }
        }
        return drafts;
      },
    );
  } catch (_) {
    // Scheduling is best-effort and never blocks timetable persistence.
  }
}

Future<void> _scheduleNextDayFirstClass(
  String accountKey,
  AcademicPersonalSchedule schedule,
) async {
  try {
    final provider = academicScheduleNextDayAlertProvider;
    await AlertCenterService.rebuildScheduled(accountKey, provider.id, (
      params,
    ) async {
      final state = await AcademicCalendarService().fetchCurrentCalendarState();
      final current = state.teachingWeek;
      final termStart = current?.termStartDate;
      if (current == null ||
          termStart == null ||
          scheduleWeekForTeachingWeek(schedule, current) == null) {
        return const [];
      }
      final hour = ((params['reminderHour'] as num?)?.round() ?? 21).clamp(
        18,
        23,
      );
      final now = east8Now();
      final today = DateTime(now.year, now.month, now.day);
      final teaching = teachingScheduleFor(
        await campusSettingsService.scheduleModeFor(accountKey),
      );
      final drafts = <ScheduledAlertDraft>[];
      for (var offset = 1; offset <= 14; offset++) {
        final date = today.add(Duration(days: offset));
        final week = scheduleWeekForDate(schedule, current, date);
        if (week == null) continue;
        final entry = filterScheduleEntriesForDay(
          schedule.entries,
          weekday: date.weekday,
          week: week,
        ).firstOrNull;
        // The “明日早八” provider is intentionally limited to a first-period
        // class. A later class is not an early-eight alert.
        if (entry == null || entry.startPeriod != 1) continue;
        final range = teaching.range(entry.startPeriod, entry.endPeriod);
        if (range == null) continue;
        final start = range.startAt(date);
        final triggerAt = east8WallClockToUtcInstant(
          DateTime(date.year, date.month, date.day - 1, hour),
        );
        final expiresAt = east8WallClockToUtcInstant(
          DateTime(date.year, date.month, date.day),
        );
        drafts.add(
          ScheduledAlertDraft(
            eventId:
                'early-class:${_dateKey(date)}:${academicScheduleEntryKey(entry)}',
            triggerAt: triggerAt,
            title: '明日早八：${entry.displayName}',
            body: [
              '第${entry.startPeriod}-${entry.endPeriod}节',
              '${_two(start.hour)}:${_two(start.minute)}',
              if (entry.location.trim().isNotEmpty) entry.location.trim(),
            ].join(' · '),
            deeplinkAppId: 'feature.academic.schedule',
            validUntil: expiresAt,
          ),
        );
      }
      return drafts;
    });
  } catch (_) {
    // Scheduling is best-effort and never blocks timetable persistence.
  }
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _two(int value) => value.toString().padLeft(2, '0');
