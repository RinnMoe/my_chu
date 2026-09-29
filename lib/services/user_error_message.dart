import 'logger_service.dart';
import 'error_feedback_service.dart';

/// User-facing operation categories used to keep implementation details out
/// of UI error messages.
enum UserErrorContext { map, webView, academic, network, download }

String userFacingError(UserErrorContext context, Object error) {
  switch (context) {
    case UserErrorContext.map:
      return '地图暂时无法加载，请稍后重试。';
    case UserErrorContext.webView:
      return '页面暂时无法打开，请检查网络后重试。';
    case UserErrorContext.academic:
      return '教务信息暂时无法加载，请稍后重试。';
    case UserErrorContext.network:
      return '网络连接失败，请检查网络后重试。';
    case UserErrorContext.download:
      return '下载失败，请稍后重试。';
  }
}

/// Records only a stable operation label and exception type; never the raw
/// exception text, which may contain paths, URLs, or response details.
void logUserFacingError(
  UserErrorContext context,
  Object error, {
  String? operation,
  UserOperationId? operationId,
  int? statusCode,
  bool? renderProcessCrashed,
  int? attempt,
  ErrorFeedbackAttempt? feedbackAttempt,
  ErrorFeedbackCoordinator? coordinator,
}) {
  // User-facing error handling is also a feature-level boundary. Mark the
  // object before recording the safe operation event so a later Zone or
  // platform fallback does not report the same failure a second time.
  RuntimeErrorReporter.markRecorded(error);
  final trackedOperation = operationId ?? _legacyOperation(context, operation);
  if (trackedOperation != null && !_isAuthenticationFailure(error)) {
    if (feedbackAttempt != null) {
      feedbackAttempt.fail(
        error,
        statusCode: statusCode,
        renderProcessCrashed: renderProcessCrashed,
        attempt: attempt,
      );
    } else {
      (coordinator ?? ErrorFeedbackCoordinator.shared).recordFailure(
        trackedOperation,
        error,
        statusCode: statusCode,
        renderProcessCrashed: renderProcessCrashed,
        attempt: attempt,
      );
    }
    return;
  }
  AppLogger.event(
    level: 'WARN',
    code: 'user.operation.failed',
    message: '用户操作失败',
    domain: trackedOperation?.key.split('.').first ?? context.name,
    operation: trackedOperation,
    exceptionType: error.runtimeType.toString(),
    statusCode: statusCode,
    renderProcessCrashed: renderProcessCrashed,
    attempt: attempt,
  );
}

bool _isAuthenticationFailure(Object error) {
  final typeName = error.runtimeType.toString();
  return typeName == 'AcademicAffairsAuthenticationException' ||
      typeName.endsWith('AuthenticationException') ||
      typeName.endsWith('IdentityException') ||
      typeName == 'LoginExpiredException';
}

UserOperationId? _legacyOperation(UserErrorContext context, String? operation) {
  return switch ((context, operation)) {
    (UserErrorContext.map, 'load') => UserOperationId.mapLoad,
    (UserErrorContext.webView, 'authenticated') =>
      UserOperationId.authenticatedWebView,
    (UserErrorContext.webView, 'academic-web') =>
      UserOperationId.academicWebView,
    (UserErrorContext.webView, 'manual') => UserOperationId.manualWebView,
    (UserErrorContext.network, 'notices') => UserOperationId.portalNotices,
    (UserErrorContext.network, 'notice') => UserOperationId.portalNoticeDetail,
    (UserErrorContext.network, 'personal') => UserOperationId.portalPersonal,
    (UserErrorContext.network, 'todos') => UserOperationId.portalTodos,
    (UserErrorContext.network, 'apps') => UserOperationId.wozaichangdaApps,
    (UserErrorContext.network, 'courses') => UserOperationId.tronclassCourses,
    (UserErrorContext.network, 'courseware') =>
      UserOperationId.tronclassCourseware,
    (UserErrorContext.download, 'courseware') =>
      UserOperationId.tronclassCoursewareDownload,
    (UserErrorContext.network, 'network-self-service') =>
      UserOperationId.networkSelfService,
    _ => null,
  };
}
