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
  Future<TeachingScheduleMode> Function(String)? readMode,
  RecentScheduleRepository? repository,
  void Function(Object)? onAcademicFailure,
}) async {
  final store = repository ?? RecentScheduleRepository.instance;
  final window = await store.read(accountKey);
  AcademicPersonalSchedule? academic;
  CurrentTeachingWeek? week;
  TeachingSchedule? teaching;
  var holiday = false;
  if (dates.any((date) => window?.covers(date) != true)) {
    try {
      academic = await (readSchedule ??
          AcademicScheduleStore().readCachedCurrentSchedule)(accountKey);
      if (academic != null) {
        if (readTeachingWeek != null) {
          week = await readTeachingWeek(accountKey);
        } else {
          final calendar =
              await AcademicCalendarService().fetchCurrentCalendarState();
          week = calendar.teachingWeek;
          holiday = calendar.isHoliday;
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
        holiday: holiday,
      ),
  ];
}
