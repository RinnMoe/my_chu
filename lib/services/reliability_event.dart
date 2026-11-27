import 'failure_details.dart';

enum UserOperationId {
  mapLoad('map.load'),
  authenticatedWebView('webview.authenticated'),
  informationPortalWebView('webview.information_portal'),
  tronclassMobileWebView('webview.tronclass_mobile'),
  qualityAssuranceWebView('webview.quality_assurance'),
  libraryWebView('webview.library'),
  commuterBusWebView('webview.commuter_bus'),
  wozaichangdaWebView('webview.wozaichangda'),
  academicWebView('webview.academic'),
  manualWebView('webview.manual'),
  classroomRecording('webview.classroom_recording'),
  sportsWebView('webview.sports'),
  portalNotices('portal.notices'),
  portalNoticeDetail('portal.notice.detail'),
  portalPersonal('portal.personal'),
  portalTodos('portal.todos'),
  networkSelfService('network.self_service'),
  wozaichangdaApps('wozaichangda.apps'),
  tronclassCourses('tronclass.courses'),
  tronclassRollcallLoad('tronclass.rollcall.load'),
  tronclassRollcallAnswer('tronclass.rollcall.answer'),
  tronclassCourseware('tronclass.courseware'),
  tronclassCoursewareDownload('tronclass.courseware.download'),
  academicCalendar('academic.calendar'),
  academicSchedule('academic.schedule'),
  academicExams('academic.exams'),
  academicGrades('academic.grades'),
  academicSyllabus('academic.syllabus'),
  classroomUsage('classroom.usage'),
  mailConnect('mail.connect'),
  mailSync('mail.sync'),
  mailRead('mail.read'),
  mailAttachment('mail.attachment'),
  mailSend('mail.send');

  const UserOperationId(this.key);

  final String key;
}

UserOperationId operationForAuthenticatedService(String serviceId) {
  return switch (serviceId) {
    'information-portal' => UserOperationId.informationPortalWebView,
    'tronclass-mobile' => UserOperationId.tronclassMobileWebView,
    'quality-assurance' => UserOperationId.qualityAssuranceWebView,
    'library-opac' => UserOperationId.libraryWebView,
    'commuter-bus' => UserOperationId.commuterBusWebView,
    'academic-affairs' => UserOperationId.academicWebView,
    'graduate-academic-affairs' => UserOperationId.academicWebView,
    'classroom-recording' => UserOperationId.classroomRecording,
    'sports-portal' => UserOperationId.sportsWebView,
    'campus-app' => UserOperationId.wozaichangdaWebView,
    _ => UserOperationId.authenticatedWebView,
  };
}

/// Fixed analytics payloads are independent of raw diagnostic records.
class ReliabilityEvent {
  const ReliabilityEvent._(this.name, this.properties);
  final String name;
  final Map<String, String> properties;
  bool get isCompleteOperation =>
      name == 'operation_finished' && properties['coverage'] == 'complete';
  String get signature => '$name:${properties.values.join(':')}';
  bool get shouldThrottle =>
      name == 'runtime_fault' ||
      (name == 'recovery_finished' &&
          properties['source'] == 'webview_proxy') ||
      (name == 'operation_finished' && !isCompleteOperation);

  static ReliabilityEvent? operation(
    UserOperationId operation, {
    required String result,
    FailureReason? reason,
    FailureStage stage = FailureStage.operation,
    Duration? duration,
    bool complete = false,
  }) {
    if (operation == UserOperationId.manualWebView) return null;
    final succeeded = result == 'success';
    return ReliabilityEvent._('operation_finished', {
      'schema_version': '2',
      'operation': operation.key,
      'result': result,
      'failure_kind': succeeded ? 'none' : reason?.kind ?? 'unexpected',
      if (!succeeded) 'failure_reason': reason?.key ?? 'unexpected',
      if (!succeeded) 'failure_stage': stage.key,
      'coverage': complete ? 'complete' : 'failure_only',
      if (complete)
        'duration_bucket': _durationBucket(duration?.inMilliseconds),
    });
  }

  static ReliabilityEvent runtime(String source, FailureReason reason) =>
      ReliabilityEvent._('runtime_fault', {
        'schema_version': '2',
        'source': source,
        'failure_reason': reason.key,
        'failure_stage': 'runtime',
        'failure_kind': reason.kind,
      });

  static ReliabilityEvent recovery({
    required String source,
    required String result,
    FailureReason? reason,
    String? failureKind,
    UserOperationId? operation,
    FailureStage stage = FailureStage.sessionRecovery,
  }) {
    final kind = failureKind ?? reason?.kind ?? 'none';
    return ReliabilityEvent._('recovery_finished', {
      'schema_version': '2',
      'source': source,
      'result':
          result == 'failed' &&
                  (reason == FailureReason.cancelled ||
                      reason == FailureReason.sessionStale)
              ? 'cancelled'
              : result,
      'failure_kind': kind,
      if (kind != 'none') 'failure_reason': reason?.key ?? kind,
      if (kind != 'none') 'failure_stage': stage.key,
      if ((source == 'webview' || source == 'webview_proxy') &&
          operation != null)
        'operation': operation.key,
    });
  }

  static String _durationBucket(int? value) {
    if (value == null || value < 0) return 'unknown';
    if (value < 1000) return 'under_1s';
    if (value < 3000) return '1_to_3s';
    if (value < 10000) return '3_to_10s';
    return 'over_10s';
  }
}
