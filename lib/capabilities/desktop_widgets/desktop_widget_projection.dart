import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import '../../capabilities/academic_schedule/academic_schedule_store.dart';
import '../../capabilities/east8_time.dart';
import '../../services/auth_service.dart';
import '../../services/campus_settings_service.dart';
import '../../services/teaching_schedule_service.dart';
import 'desktop_widget_models.dart';

String desktopWidgetDateForInstant(DateTime instant) {
  final east8 = instant.toUtc().add(east8Offset);
  return _formatDate(east8);
}

int? desktopWidgetTeachingWeekForInstant(
  DateTime instant,
  DateTime? termStartDate,
) {
  if (termStartDate == null) return null;
  final east8 = instant.toUtc().add(east8Offset);
  final currentDate = DateTime.utc(east8.year, east8.month, east8.day);
  final firstWeekStart = DateTime.utc(
    termStartDate.year,
    termStartDate.month,
    termStartDate.day,
  );
  final daysSinceTermStart = currentDate.difference(firstWeekStart).inDays;
  if (daysSinceTermStart < 0) return null;
  return daysSinceTermStart ~/ DateTime.daysPerWeek + 1;
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

DesktopWidgetScheduleV1 projectDesktopWidgetSchedule({
  required bool signedIn,
  required AcademicPersonalSchedule? schedule,
  required DateTime? termStartDate,
  required TeachingSchedule teachingSchedule,
  int? currentWeek,
}) {
  if (!signedIn) {
    return DesktopWidgetScheduleV1(
      status: DesktopWidgetScheduleStatus.signedOut,
    );
  }
  if (schedule == null ||
      schedule.semesterId.trim().isEmpty ||
      schedule.semesterLabel.trim().isEmpty) {
    return DesktopWidgetScheduleV1(
      status: DesktopWidgetScheduleStatus.noSchedule,
    );
  }
  if (termStartDate == null) {
    return DesktopWidgetScheduleV1(
      status: DesktopWidgetScheduleStatus.calendarUnavailable,
    );
  }

  final firstWeekStart = DateTime.utc(
    termStartDate.year,
    termStartDate.month,
    termStartDate.day,
  );
  final occurrences = <DesktopWidgetOccurrenceV1>[];
  for (var week = 1; week <= schedule.maxWeek; week++) {
    for (
      var entryIndex = 0;
      entryIndex < schedule.entries.length;
      entryIndex++
    ) {
      final entry = schedule.entries[entryIndex];
      if (entry.weekday < DateTime.monday ||
          entry.weekday > DateTime.sunday ||
          entry.startPeriod < 1 ||
          entry.endPeriod < entry.startPeriod ||
          !entry.isVisibleInWeek(week)) {
        continue;
      }
      final courseName =
          entry.courseName.trim().isNotEmpty
              ? entry.courseName.trim()
              : entry.courseSequence.trim();
      if (courseName.isEmpty) continue;
      final date = firstWeekStart.add(
        Duration(days: (week - 1) * DateTime.daysPerWeek + entry.weekday - 1),
      );
      final dateText = _formatDate(date);
      final time = teachingSchedule.range(entry.startPeriod, entry.endPeriod);
      occurrences.add(
        DesktopWidgetOccurrenceV1(
          id: '$dateText|$entryIndex',
          date: dateText,
          courseName: courseName,
          location: entry.location.trim(),
          startPeriod: entry.startPeriod,
          endPeriod: entry.endPeriod,
          periodLabel: _periodLabel(entry.startPeriod, entry.endPeriod),
          startTime: time?.startText,
          endTime: time?.endText,
        ),
      );
    }
  }
  occurrences.sort((left, right) {
    var result = left.date.compareTo(right.date);
    if (result != 0) return result;
    result = left.startPeriod.compareTo(right.startPeriod);
    if (result != 0) return result;
    result = left.endPeriod.compareTo(right.endPeriod);
    if (result != 0) return result;
    result = left.courseName.compareTo(right.courseName);
    if (result != 0) return result;
    return left.id.compareTo(right.id);
  });
  return DesktopWidgetScheduleV1(
    status: DesktopWidgetScheduleStatus.ready,
    semesterId: schedule.semesterId.trim(),
    currentWeek: currentWeek,
    occurrences: occurrences,
  );
}

String _periodLabel(int startPeriod, int endPeriod) {
  if (startPeriod == endPeriod) return '第$startPeriod节';
  return '第$startPeriod–$endPeriod节';
}

typedef DesktopWidgetAccountKeyReader = Future<String?> Function();
typedef DesktopWidgetScheduleReader =
    Future<AcademicPersonalSchedule?> Function(String accountKey);
typedef DesktopWidgetTermStartReader =
    Future<DateTime?> Function(String accountKey, String semesterLabel);
typedef DesktopWidgetScheduleModeReader =
    Future<TeachingScheduleMode> Function(String accountKey);

class DesktopWidgetProjectionService {
  final DesktopWidgetAccountKeyReader _readAccountKey;
  final DesktopWidgetScheduleReader _readSchedule;
  final DesktopWidgetTermStartReader _readTermStartDate;
  final DesktopWidgetScheduleModeReader _readScheduleMode;
  final DateTime Function() _clock;

  DesktopWidgetProjectionService({
    required DesktopWidgetAccountKeyReader readAccountKey,
    required DesktopWidgetScheduleReader readSchedule,
    required DesktopWidgetTermStartReader readTermStartDate,
    required DesktopWidgetScheduleModeReader readScheduleMode,
    DateTime Function()? clock,
  }) : _readAccountKey = readAccountKey,
       _readSchedule = readSchedule,
       _readTermStartDate = readTermStartDate,
       _readScheduleMode = readScheduleMode,
       _clock = clock ?? DateTime.now;

  factory DesktopWidgetProjectionService.forHost() {
    final scheduleStore = AcademicScheduleStore();
    final calendarService = AcademicCalendarService();
    final campusSettings = CampusSettingsService();
    return DesktopWidgetProjectionService(
      readAccountKey:
          () async => (await AuthService.getCurrentAccount())?.accountKey,
      readSchedule: scheduleStore.readCachedCurrentSchedule,
      readTermStartDate: calendarService.readCachedTermStartDateForSemester,
      readScheduleMode: campusSettings.scheduleModeFor,
    );
  }

  Future<DesktopWidgetSnapshotV1> build() async {
    final now = _clock();
    final accountKey = (await _readAccountKey())?.trim();
    DesktopWidgetScheduleV1 scheduleProjection;
    if (accountKey == null || accountKey.isEmpty) {
      scheduleProjection = projectDesktopWidgetSchedule(
        signedIn: false,
        schedule: null,
        termStartDate: null,
        teachingSchedule: teachingScheduleFor(TeachingScheduleMode.weishui),
      );
    } else {
      final schedule = await _readSchedule(accountKey);
      if (schedule == null) {
        scheduleProjection = projectDesktopWidgetSchedule(
          signedIn: true,
          schedule: null,
          termStartDate: null,
          teachingSchedule: teachingScheduleFor(TeachingScheduleMode.weishui),
        );
      } else {
        final termStartDate = await _readTermStartDate(
          accountKey,
          schedule.semesterLabel,
        );
        if (termStartDate == null) {
          scheduleProjection = projectDesktopWidgetSchedule(
            signedIn: true,
            schedule: schedule,
            termStartDate: null,
            teachingSchedule: teachingScheduleFor(TeachingScheduleMode.weishui),
          );
        } else {
          final mode = await _readScheduleMode(accountKey);
          scheduleProjection = projectDesktopWidgetSchedule(
            signedIn: true,
            schedule: schedule,
            termStartDate: termStartDate,
            teachingSchedule: teachingScheduleFor(mode),
            currentWeek: desktopWidgetTeachingWeekForInstant(
              now,
              termStartDate,
            ),
          );
        }
      }
    }
    return DesktopWidgetSnapshotV1(
      generatedAt: now.toUtc(),
      schedule: scheduleProjection,
    );
  }
}
