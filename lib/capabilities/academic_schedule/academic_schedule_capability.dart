import '../../widgets/campus_auth_prompt.dart';
import 'package:flutter/material.dart';

import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../apps/academic_web/shuwei_schedule_importer.dart';
import '../public_holidays/public_holidays.dart';
import 'academic_schedule_home_module.dart';
import 'academic_schedule_navigation.dart';
import 'academic_schedule_page.dart';
import '../../widgets/campus_auth_boundary.dart';

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

  Widget createPage() => CampusAuthBoundary(
    title: '课表',
    retainGuestShell: true,
    builder: (_) => const AcademicSchedulePage(),
  );

  Widget createHomeModule({
    PublicHolidayProvider? publicHolidayProvider,
    AcademicCalendarState? calendarState,
    bool calendarStateLoading = false,
    Future<void> Function()? onRetryCalendarState,
  }) => CampusAuthBoundary(
    title: '今日课表',
    inline: true,
    guestBuilder:
        (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日课表', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const CampusAuthPrompt(
              title: '今日课表',
              icon: Icons.calendar_today_outlined,
              compact: true,
            ),
          ],
        ),
    builder:
        (_) => AcademicScheduleHomeModule(
          publicHolidayProvider: publicHolidayProvider,
          useSharedCalendarState:
              calendarState != null ||
              calendarStateLoading ||
              onRetryCalendarState != null,
          calendarState: calendarState,
          calendarStateLoading: calendarStateLoading,
          onRetryCalendarState: onRetryCalendarState,
        ),
  );

  void handleAppLifecycleState(AppLifecycleState state) {
    ShuweiScheduleImporter.handleAppLifecycleState(state);
  }

  Future<void> open(BuildContext context) => openAcademicSchedule(context);
}

const academicScheduleCapability = AcademicScheduleCapability();
