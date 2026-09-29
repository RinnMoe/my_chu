import 'package:flutter/material.dart';

import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../apps/academic_web/shuwei_schedule_importer.dart';
import '../live_update.dart';
import '../public_holidays/public_holidays.dart';
import 'academic_schedule_home_module.dart';
import 'academic_schedule_live_update.dart';
import 'academic_schedule_navigation.dart';
import 'academic_schedule_page.dart';

/// Host-owned timetable capability.
///
/// Unlike a built-in app, this capability is always available to the host and
/// is not installable, pinnable, or listed in the app catalog.
class AcademicScheduleCapability {
  const AcademicScheduleCapability();

  static const String targetId = 'feature.academic.schedule';

  String get id => targetId;
  String get navigationLabel => '课表';
  IconData get icon => Icons.calendar_month_outlined;

  Widget createPage() => const AcademicSchedulePage();

  Widget createHomeModule({
    PublicHolidayProvider? publicHolidayProvider,
    AcademicCalendarState? calendarState,
    bool calendarStateLoading = false,
    Future<void> Function()? onRetryCalendarState,
  }) => AcademicScheduleHomeModule(
    publicHolidayProvider: publicHolidayProvider,
    useSharedCalendarState:
        calendarState != null ||
        calendarStateLoading ||
        onRetryCalendarState != null,
    calendarState: calendarState,
    calendarStateLoading: calendarStateLoading,
    onRetryCalendarState: onRetryCalendarState,
  );

  void handleAppLifecycleState(AppLifecycleState state) {
    ShuweiScheduleImporter.handleAppLifecycleState(state);
  }

  List<SystemLiveActivityDefinition> get systemLiveActivityDefinitions =>
      const [academicScheduleLiveUpdateDefinition];

  Future<void> open(BuildContext context) => openAcademicSchedule(context);
}

const academicScheduleCapability = AcademicScheduleCapability();
