/// 用户反馈的统一领域模型与提交结果语义。
///
/// 长度上限与 Fenfa 公开接口一致；Supabase 迁移不改变用户可见的输入约束。
const kFeedbackMaxContentLength = 4000;
const kFeedbackWithDiagnosticsMaxContentLength = 2700;
const kFeedbackMaxDiagnosticLength = 1200;
const kFeedbackMaxContactLength = 255;

/// 反馈分类；对应两种后端的 `category` 字段。
enum AppFeedbackCategory { bug, suggestion, other }

extension AppFeedbackCategoryValue on AppFeedbackCategory {
  String get apiValue => switch (this) {
    AppFeedbackCategory.bug => 'bug',
    AppFeedbackCategory.suggestion => 'suggestion',
    AppFeedbackCategory.other => 'other',
  };
}

/// 反馈草稿；不包含账号、Cookie、学号或其他凭据。
class AppFeedbackDraft {
  const AppFeedbackDraft({
    required this.category,
    required this.content,
    this.contact = '',
    this.diagnosticLog = '',
  });

  final AppFeedbackCategory category;
  final String content;
  final String contact;
  final String diagnosticLog;

  bool get hasDiagnostics => diagnosticLog.trim().isNotEmpty;

  /// 提交内容长度上限：附带诊断信息时正文上限更小。
  int get contentLengthLimit =>
      hasDiagnostics
          ? kFeedbackWithDiagnosticsMaxContentLength
          : kFeedbackMaxContentLength;
}

/// 提交结果不确定：请求可能已经在服务端写入，只是客户端没有收到响应。
///
/// 调用方不得因此自动重试或改投其他后端；只有用户主动再次提交时才复用同一
/// 幂等请求 ID 重发，由服务端去重。
class FeedbackSubmissionUnknownException implements Exception {
  const FeedbackSubmissionUnknownException([this.cause]);

  /// 原始异常类型仅用于本地诊断，不进入用户可见文案。
  final Object? cause;

  static const String userMessage = '网络中断，提交结果未知。请稍后重试，重复提交会自动去重。';

  @override
  String toString() => 'FeedbackSubmissionUnknownException';
}
