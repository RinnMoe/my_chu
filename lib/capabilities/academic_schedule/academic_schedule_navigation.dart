import 'package:flutter/widgets.dart';

import '../../services/root_navigation_service.dart';

const academicScheduleRootTabId = 'feature.academic.schedule';

Future<void> openAcademicSchedule(BuildContext context) async {
  if (!context.mounted) return;
  RootNavigationService.selectTab(academicScheduleRootTabId);
  // Focus/notification pages can themselves be pushed routes.  Return to the
  // shell so the selected root tab is immediately visible instead of leaving
  // a second timetable page with a back button on top.
  Navigator.of(context).popUntil((route) => route.isFirst);
}
