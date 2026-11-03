import 'app_feedback.dart';

/// 用户反馈写入数据源。
///
/// 反馈是写操作：调用方必须固定单一目标，结果不确定时不得自动重试。
abstract interface class FeedbackRepository {
  /// [requestId] 是调用方生成的幂等键；实现必须原样提交，不得改写或丢弃。
  Future<void> submitFeedback(
    AppFeedbackDraft draft, {
    required String requestId,
  });
}
