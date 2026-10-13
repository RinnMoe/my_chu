import '../services/time_reminder_service.dart';
import '../apps/academic_affairs/academic_affairs_service.dart';
import '../apps/tronclass/tronclass_service.dart';
import 'academic_schedule/academic_schedule_alerts.dart';

void registerTimeReminders() {
  TimeReminderService.register(
    TimeReminderCategory.course,
    refreshRecentCourseAlerts,
  );
  TimeReminderService.register(
    TimeReminderCategory.exam,
    (account) => TimeReminderService.replaceEvents(
      account,
      TimeReminderCategory.exam,
      () async => AcademicAffairsService.examReminderEvents(
        await AcademicAffairsService().fetchAllExams(null, false),
      ),
    ),
  );
  TimeReminderService.register(
    TimeReminderCategory.deadline,
    (account) => TimeReminderService.replaceEvents(
      account,
      TimeReminderCategory.deadline,
      () async => TronclassService.todoReminderEvents(
        await TronclassService().fetchTodos(evaluateAlerts: false),
      ),
    ),
  );
}
