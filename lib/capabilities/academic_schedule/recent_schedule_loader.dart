import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import '../../services/campus_settings_service.dart';
import '../../services/teaching_schedule_service.dart';
import 'academic_schedule_store.dart';
import 'recent_schedule.dart';
import 'recent_schedule_repository.dart';

/// All dated consumers share this precedence. Academic dependencies are lazy:
/// a covered ROOMIS day works even when the semester/calendar is unavailable.
Future<List<RecentScheduleDay>> loadRecentScheduleDays(
  String accountKey,
  List<DateTime> dates, {
  Future<AcademicPersonalSchedule?> Function(String)? readSchedule,
  Future<CurrentTeachingWeek?> Function(String)? readTeachingWeek,
  Future<DateTime?> Function(String, String)? readTermStartDate,
  Future<TeachingScheduleMode> Function(String)? readMode,
  RecentScheduleRepository? repository,
  void Function(Object)? onAcademicFailure,
}) async {
  final store = repository ?? RecentScheduleRepository.instance;
  final window = await store.read(accountKey);
  AcademicPersonalSchedule? academic;
  CurrentTeachingWeek? week;
  TeachingSchedule? teaching;
  AcademicCalendarData? cachedCalendar;
  var holiday = false;
  if (dates.isNotEmpty) {
    try {
      academic = await (readSchedule ??
          AcademicScheduleStore().readCachedCurrentSchedule)(accountKey);
      if (academic != null) {
        final hasUncoveredDate = dates.any(
          (date) => window?.covers(date) != true,
        );
        if (hasUncoveredDate && readTeachingWeek != null) {
          week = await readTeachingWeek(accountKey);
        } else {
          final calendarService = AcademicCalendarService();
          if (hasUncoveredDate) {
            final calendar = await calendarService.fetchCurrentCalendarState();
            week = calendar.teachingWeek;
            holiday = calendar.isHoliday;
          }
          try {
            cachedCalendar = await calendarService
                .readCachedCalendarForSemester(
                  accountKey,
                  academic.semesterLabel,
                );
          } catch (_) {
            // A missing local calendar must not discard a valid dated window.
          }
          if (!hasUncoveredDate) {
            final termStart =
                cachedCalendar?.term.startDate ??
                await (readTermStartDate ??
                    calendarService.readCachedTermStartDateForSemester)(
                  accountKey,
                  academic.semesterLabel,
                );
            if (termStart != null) {
              week = CurrentTeachingWeek(
                term: academic.semesterLabel,
                week: 1,
                termStartDate: termStart,
              );
            }
          }
        }
        teaching = teachingScheduleFor(
          await (readMode ?? (_) => campusSettingsService.scheduleModeFor())(
            accountKey,
          ),
        );
      }
    } catch (error) {
      onAcademicFailure?.call(error);
      // An unavailable academic fallback must not hide covered ROOMIS days.
    }
  }
  return [
    for (final date in dates)
      resolveRecentScheduleDay(
        date: date,
        window: window,
        fresh: window != null && store.isFresh(accountKey, window),
        academic: academic,
        teachingWeek: week,
        teaching: teaching,
        holiday: cachedCalendar?.weekFor(date)?.isHoliday ?? holiday,
      ),
  ];
}
