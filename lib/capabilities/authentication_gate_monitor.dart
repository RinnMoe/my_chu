import 'dart:async';

/// Bounds the time a visible authentication page can be hidden by its host.
class AuthenticationGateMonitor {
  AuthenticationGateMonitor({
    required Future<void> Function() checkReady,
    required void Function() onTimeout,
  }) {
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_checking) return;
      _checking = true;
      try {
        await checkReady();
      } finally {
        _checking = false;
      }
    });
    // Separate from polling: a stalled platform call must not stall fallback.
    _deadline = Timer(const Duration(seconds: 20), () {
      cancel();
      onTimeout();
    });
  }

  late final Timer _poll;
  late final Timer _deadline;
  bool _checking = false;

  void cancel() {
    _poll.cancel();
    _deadline.cancel();
  }
}
