/// 内置提醒提供者注册清单。
///
/// 各应用服务的提醒提供者以静态字段形式声明；本文件在应用启动与设置页
/// 打开时被引用，确保注册在评估与订阅展示前完成。
library;

import 'alert_center.dart';
import '../apps/academic_affairs/academic_affairs_service.dart';
import '../apps/information_portal/information_portal_service.dart';
import '../apps/tronclass/tronclass_service.dart';
import 'academic_schedule/academic_schedule_alerts.dart';

/// 注册全部内置提醒提供者。
void ensureBuiltInAlertProvidersRegistered() {
  AlertCenterService.register(AcademicAffairsService.gradeAlertProvider);
  AlertCenterService.register(AcademicAffairsService.examsSoonAlertProvider);
  AlertCenterService.register(academicScheduleAlertProvider);
  AlertCenterService.register(academicScheduleNextDayAlertProvider);
  AlertCenterService.register(PortalApiService.balanceLowAlertProvider);
  AlertCenterService.register(PortalApiService.unreadEmailAlertProvider);
  AlertCenterService.register(TronclassService.newTodosAlertProvider);
  AlertCenterService.register(TronclassService.todoDeadlineAlertProvider);
}
