import '../fenfa/fenfa_models.dart';
import '../fenfa/fenfa_service.dart';
import 'app_feedback.dart';

/// 用户反馈写入数据源。
///
/// 反馈是写操作：调用方必须固定单一目标，不得在结果不确定时改投另一个后端。
abstract interface class FeedbackRepository {
  /// [requestId] 是调用方生成的幂等键；不支持幂等的后端可以忽略它。
  Future<void> submitFeedback(
    AppFeedbackDraft draft, {
    required String requestId,
  });
}

/// Fenfa 匿名反馈数据源（迁移前的既有实现）。
///
/// 直接复用既有服务：产品/变体/版本上下文、诊断信息合并和长度复检都保持
/// 原行为，不在迁移中重写。
class FenfaFeedbackRepository implements FeedbackRepository {
  FenfaFeedbackRepository({FenfaService? service})
    : _service = service ?? FenfaService.shared;

  final FenfaService _service;

  @override
  Future<void> submitFeedback(
    AppFeedbackDraft draft, {
    required String requestId,
  }) {
    return _service.submitFeedback(
      FenfaFeedbackDraft(
        category: switch (draft.category) {
          AppFeedbackCategory.bug => FenfaFeedbackCategory.bug,
          AppFeedbackCategory.suggestion => FenfaFeedbackCategory.suggestion,
          AppFeedbackCategory.other => FenfaFeedbackCategory.other,
        },
        content: draft.content,
        contact: draft.contact,
        diagnosticLog: draft.diagnosticLog,
      ),
    );
  }
}
