/// 统一提醒能力：提醒类型与严重程度定义。
library;

/// 提醒类型。
enum AlertKind {
  /// 内容变化型：新成绩、新公告、新待办等，按事件指纹提醒。
  event,

  /// 状态条件型：余额低于阈值、存在未读邮件等持续条件；
  /// 条件解除后自动移出注意力，再次满足可重新提醒。
  condition,

  /// 时间窗口型：考试/作业即将截止，进入窗口提醒，窗口结束自动移出注意力。
  deadline,
}

/// 提醒严重程度。
enum AlertSeverity {
  info,
  warning,
  critical,
}
