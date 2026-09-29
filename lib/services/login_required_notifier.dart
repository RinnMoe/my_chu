/// 统一身份会话过期且静默重登无法完成时，通知宿主 UI 引导用户手动重新登录。
///
/// 底层会话层 / 静默重登服务在没有
/// `BuildContext` 的情况下发布请求；`AppShell` 注册监听并负责弹窗与跳转。
/// 通知自带去重：同一时间只有一个待处理提示，且提示后进入冷却。
class LoginRequiredNotifier {
  LoginRequiredNotifier._();

  static final List<void Function(String reason)> _listeners = [];
  static bool _promptActive = false;
  static DateTime? _lastPromptAt;
  static const _promptCooldown = Duration(minutes: 5);

  static void addListener(void Function(String reason) listener) {
    _listeners.add(listener);
  }

  static void removeListener(void Function(String reason) listener) {
    _listeners.remove(listener);
  }

  /// 请求引导用户重新登录。冷却期内或已有待处理提示时直接忽略。
  static void requestRelogin(String reason) {
    if (_listeners.isEmpty) return;
    if (_promptActive) return;
    final last = _lastPromptAt;
    if (last != null && DateTime.now().difference(last) < _promptCooldown) {
      return;
    }
    _promptActive = true;
    _lastPromptAt = DateTime.now();
    for (final listener in List.of(_listeners)) {
      listener(reason);
    }
  }

  /// 宿主完成提示流程（无论用户是否选择重新登录）后调用，允许后续再次提示。
  static void markPromptDismissed() {
    _promptActive = false;
  }

  /// 登录成功后重置冷却，确保下一次过期仍能正常提示。
  static void resetAfterLogin() {
    _promptActive = false;
    _lastPromptAt = null;
  }

  /// 测试辅助：重置静态状态。
  static void debugReset() {
    _listeners.clear();
    _promptActive = false;
    _lastPromptAt = null;
  }
}
