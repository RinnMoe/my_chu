import 'package:flutter/material.dart';
import 'wozaichangda/wozaichangda_page.dart';
import 'app.dart';
import 'academic_affairs/academic_exams_app.dart';
import 'channel_resources/channel_resources_app.dart';
import 'network_self_service/network_self_service_app.dart';
import 'academic_affairs/academic_grades_app.dart';
import 'academic_calendar/academic_calendar_app.dart';
import 'academic_affairs/academic_syllabus_app.dart';
import 'academic_web/academic_web_app.dart';
import 'classroom_usage/classroom_usage_app.dart';
import 'smart_socket_yundaren/smart_socket_yundaren_app.dart';
import 'classroom_recording/classroom_recording_app.dart';
import 'commuter_bus/commuter_bus_app.dart';
import 'library/library_app.dart';
import 'parcel_identity_code/parcel_identity_code_app.dart';
import 'portal_notices/portal_notices_app.dart';
import 'portal_personal/portal_personal_app.dart';
import 'quality_assurance/quality_assurance_app.dart';
import 'second_classroom/second_classroom_app.dart';
import 'sports/sports_app.dart';
import 'tronclass/tronclass_app.dart';
import 'tronclass_mobile/tronclass_mobile_app.dart';
import 'trusted_docs/trusted_docs_app.dart';
import 'xuexin/xuexin_app.dart';

class AppRegistry {
  static final List<AppDefinition> builtIns = [
    AppDefinition(
      metadata: AppMetadata(
        id: 'feature.wozaichangda',
        name: '我在长大',
        description: '学工服务与日常事务。',
        iconCodePoint: Icons.school_outlined.codePoint,
        category: AppCategory.campus,
        developmentFlag: DevelopmentFlag.none,
        defaultPinned: true,
      ),
      builder: (_) => const WozaichangdaPage(),
    ),
    academicExamsApp,
    academicGradesApp,
    academicCalendarApp,
    academicSyllabusApp,
    classroomUsageApp,
    classroomRecordingApp,
    commuterBusApp,
    libraryApp,
    academicWebApp,
    qualityAssuranceApp,
    portalPersonalApp,
    portalNoticesApp,
    sportsApp,
    secondClassroomApp,
    tronclassApp,
    tronclassMobileApp,
    trustedDocsApp,
    xuexinApp,
    channelResourcesApp,
    networkSelfServiceApp,
    parcelIdentityCodeApp,
    smartSocketYundarenApp,
  ];

  static AppDefinition? builtInById(String id) {
    for (final plugin in builtIns) {
      if (plugin.metadata.id == id) return plugin;
    }
    return null;
  }

  /// 查找内置应用。
  static AppDefinition? publishedById(String id) {
    final plugin = builtInById(id);
    if (plugin != null) return plugin;

    // Saved todo notifications can outlive the build that wrote them: history
    // is retained per account, and records without expiresAt do not expire.
    // Keep old links opening the current personal-data app.
    if (id == 'feature.tronclass') {
      return builtInById('feature.portal.personal');
    }
    return null;
  }
}
