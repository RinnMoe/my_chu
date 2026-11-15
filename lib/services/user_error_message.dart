import 'failure_classifier.dart';
import 'failure_details.dart';
import 'usage_analytics_service.dart';
import 'reliability_event.dart';
import 'logging/logger.dart';

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

/// Records a handled failure at its user-visible boundary.
void logUserFacingError(
  UserErrorContext context,
  Object error, {
  UserOperationId? operationId,
  int? statusCode,
  bool? renderProcessCrashed,
  AnalyticsOperation? feedbackAttempt,
  FailureStage? stage,
  StackTrace? stackTrace,
  String? details,
}) {
  final failureStage =
      stage ??
      (context == UserErrorContext.webView
          ? FailureStage.mainFrame
          : FailureStage.request);
  AppLogger.error(
    error,
    stackTrace: stackTrace,
    context: [
      (operationId ?? feedbackAttempt?.operation)?.key ?? context.name,
      if (details != null) details,
      if (statusCode != null) 'HTTP $statusCode',
      if (renderProcessCrashed != null)
        'renderProcessCrashed=$renderProcessCrashed',
    ].join('\n'),
  );
  if (feedbackAttempt != null) {
    feedbackAttempt.fail(
      error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      stage: failureStage,
    );
  } else if (operationId != null) {
    final reason = classifyFailure(
      error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
    );
    UsageAnalyticsService.recordOperation(
      operationId,
      result:
          reason == FailureReason.cancelled ||
                  reason == FailureReason.sessionStale
              ? 'cancelled'
              : 'failed',
      reason: reason,
      stage: failureStage,
    );
  }
}
