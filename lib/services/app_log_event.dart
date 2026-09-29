import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Stable identifiers for foreground operations that can present a retryable
/// error to the user.
enum UserOperationId {
  mapLoad('map.load', '地图'),
  authenticatedWebView('webview.authenticated', '校园页面'),
  informationPortalWebView('webview.information_portal', '校园门户页面'),
  tronclassMobileWebView('webview.tronclass_mobile', '畅课页面'),
  qualityAssuranceWebView('webview.quality_assurance', '评教页面'),
  libraryWebView('webview.library', '图书馆页面'),
  commuterBusWebView('webview.commuter_bus', '通勤车页面'),
  wozaichangdaWebView('webview.wozaichangda', '我在长大页面'),
  academicWebView('webview.academic', '教务页面'),
  manualWebView('webview.manual', '登录页面'),
  classroomRecording('webview.classroom_recording', '课堂实录'),
  sportsWebView('webview.sports', '长大体育页面'),
  portalNotices('portal.notices', '校园公告'),
  portalNoticeDetail('portal.notice.detail', '公告详情'),
  portalPersonal('portal.personal', '个人信息'),
  portalTodos('portal.todos', '待办事项'),
  networkSelfService('network.self_service', '网络自服'),
  wozaichangdaApps('wozaichangda.apps', '应用列表'),
  tronclassCourses('tronclass.courses', '畅课课程'),
  tronclassCourseware('tronclass.courseware', '畅课课件'),
  tronclassCoursewareDownload('tronclass.courseware.download', '课件下载'),
  academicCalendar('academic.calendar', '校历'),
  academicSchedule('academic.schedule', '课表'),
  academicExams('academic.exams', '考试'),
  academicGrades('academic.grades', '成绩'),
  academicSyllabus('academic.syllabus', '教学大纲'),
  classroomUsage('classroom.usage', '教室使用情况');

  const UserOperationId(this.key, this.label);

  final String key;
  final String label;
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

/// A single safe runtime event shared by the Debug log and public diagnostics.
///
/// [message] and [fields] are sanitized at construction time. The model does
/// not carry a URL, account identifier, cookie, ticket, token, response body,
/// or raw exception message.
@immutable
class AppLogEvent {
  AppLogEvent({
    required this.timestamp,
    required String level,
    required String code,
    required String message,
    Map<String, Object?> fields = const {},
    this.operation,
    String? domain,
    String? exceptionType,
    this.statusCode,
    this.renderProcessCrashed,
    this.attempt,
  }) : level = _safeLevel(level),
       code = _safeCode(code),
       message = sanitizeLogText(message),
       domain = _safeDomain(
         domain ?? operation?.key.split('.').first ?? code.split('.').first,
       ),
       exceptionType =
           exceptionType == null ? null : _safeExceptionType(exceptionType),
       fields = UnmodifiableMapView<String, Object?>(_safeFields(fields));

  final DateTime timestamp;
  final String level;
  final String code;
  final String message;
  final String domain;
  final UnmodifiableMapView<String, Object?> fields;
  final UserOperationId? operation;
  final String? exceptionType;
  final int? statusCode;
  final bool? renderProcessCrashed;
  final int? attempt;

  String get businessDomain => domain;

  String toSafeLine() {
    final local = timestamp;
    final time = [
      local.hour.toString().padLeft(2, '0'),
      local.minute.toString().padLeft(2, '0'),
      local.second.toString().padLeft(2, '0'),
    ].join(':');
    final details = <String>[
      if (operation != null) operation!.key,
      if (domain.isNotEmpty) 'domain=$domain',
      code,
      message,
      if (exceptionType != null) 'exception=${_safeValue(exceptionType!)}',
      if (statusCode != null) 'status=$statusCode',
      if (renderProcessCrashed != null)
        'renderer=${renderProcessCrashed! ? 'crashed' : 'exited'}',
      if (attempt != null) 'attempt=$attempt',
      for (final entry in fields.entries)
        '${_safeKey(entry.key)}=${_safeValue(entry.value)}',
    ];
    return '$time [$level] ${details.join(' | ')}';
  }

  String get operationKey => operation?.key ?? code;

  static Map<String, Object?> _safeFields(Map<String, Object?> fields) {
    const allowedKeys = <String>{
      'automatic',
      'count',
      'durationms',
      'failure',
      'format',
      'granted',
      'leftloginpage',
      'login',
      'personcenter',
      'phase',
      'reason',
      'result',
      'retry',
      'service',
      'source',
      'stage',
      'status',
      'supported',
    };
    final safe = <String, Object?>{};
    for (final entry in fields.entries) {
      final key = _safeKey(entry.key);
      if (key.isEmpty) continue;
      if (!allowedKeys.contains(key.toLowerCase())) continue;
      final value = entry.value;
      if (value == null || value is num || value is bool) {
        safe[key] = value;
      } else {
        safe[key] = sanitizeLogText('$value');
      }
    }
    return safe;
  }
}

/// Backwards-compatible name used by the old Debug log page.
typedef LogEntry = AppLogEvent;

/// Compatibility event constructor for error-feedback tests and integrations.
class DiagnosticLogEvent extends AppLogEvent {
  DiagnosticLogEvent({
    required super.timestamp,
    required UserOperationId operation,
    required String exceptionType,
    super.statusCode,
    super.renderProcessCrashed,
    super.attempt,
  }) : super(
         level: 'ERROR',
         code: operation.key,
         message: operation.label,
         operation: operation,
         exceptionType: exceptionType,
       );
}

/// In-memory bounded event source used by both public diagnostics and Debug.
class AppLogBuffer {
  AppLogBuffer({this.maxEntries = 500});

  final int maxEntries;
  final List<AppLogEvent> _events = <AppLogEvent>[];
  final List<VoidCallback> _listeners = <VoidCallback>[];

  List<AppLogEvent> get entries => List.unmodifiable(_events);

  void add(AppLogEvent event) {
    if (maxEntries <= 0) return;
    _events.add(event);
    while (_events.length > maxEntries) {
      _events.removeAt(0);
    }
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  List<AppLogEvent> snapshot({int? maxEntries}) {
    final limit = maxEntries ?? this.maxEntries;
    if (limit <= 0 || _events.isEmpty) return const <AppLogEvent>[];
    final start = _events.length > limit ? _events.length - limit : 0;
    return List<AppLogEvent>.unmodifiable(_events.sublist(start));
  }

  void clear() {
    _events.clear();
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void removeWhere(bool Function(AppLogEvent event) test) {
    _events.removeWhere(test);
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

final AppLogBuffer sharedAppLogBuffer = AppLogBuffer();

String sanitizeLogText(String value) {
  var text = value.trim();
  if (text.isEmpty) return '未提供';
  text = text
      .replaceAll(RegExp(r'https?://[^\s)]+', caseSensitive: false), '[已隐藏地址]')
      .replaceAll(
        RegExp(
          r'(cookie|token|ticket|password|passwd|secret|authorization|url|uri|endpoint|验证码|短信码|captcha(?:Code|_code)?|sms(?:Code|_code)?|学号|账号|姓名|account(?:Id|Key)?|student(?:Id)?|username|user(?:Id|Name)?|phone|mobile|device(?:Id)?|userId|mobile_code|appToken)\s*[:=→]?\s*[^\s,;，；)）]+',
          caseSensitive: false,
        ),
        r'$1=[已隐藏]',
      )
      .replaceAll(
        RegExp(r'host\s*[:=]\s*[^\s,;，；)）]+', caseSensitive: false),
        'host=[已隐藏]',
      )
      .replaceAll(
        RegExp(r'[A-Za-z0-9.-]+\.chd\.edu\.cn(?::\d+)?', caseSensitive: false),
        '[校园服务]',
      )
      .replaceAll(RegExp(r'验证码识别成功\s*\d+'), '验证码识别完成')
      .replaceAll(
        RegExp(r'js document\.cookie\s*→\s*\d+\s*字符'),
        'WebView 会话数据已读取',
      );
  if (text.length > 240) text = '${text.substring(0, 237)}…';
  return text;
}

String _safeCode(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'app.unknown';
  if (normalized.contains('://') ||
      normalized.toLowerCase().contains('.chd.edu.cn')) {
    return 'app.unknown';
  }
  final safe = normalized.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return safe.isEmpty ? 'app.unknown' : safe;
}

String _safeLevel(String value) => switch (value.trim().toUpperCase()) {
  'ERROR' => 'ERROR',
  'WARN' || 'WARNING' => 'WARN',
  _ => 'INFO',
};

String _safeDomain(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return 'app';
  if (normalized.contains('://') || normalized.contains('.chd.edu.cn')) {
    return 'app';
  }
  final safe = normalized.replaceAll(RegExp(r'[^a-z0-9_.-]'), '_');
  if (safe.isEmpty) return 'app';
  return safe.length > 32 ? safe.substring(0, 32) : safe;
}

String _safeExceptionType(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'UnknownError';
  // Runtime type names are the only accepted exception detail. If a caller
  // accidentally passes `Type: message`, retain the type token and discard
  // everything after it so a response/URL cannot enter the public report.
  final match = RegExp(r'^[A-Za-z_][A-Za-z0-9_.$<>]*').firstMatch(normalized);
  final safe = match?.group(0);
  if (safe == null || safe.isEmpty) return 'UnknownError';
  return safe.length > 96 ? safe.substring(0, 96) : safe;
}

String _safeKey(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return safe.length > 32 ? safe.substring(0, 32) : safe;
}

String _safeValue(Object? value) => sanitizeLogText('$value');
