import 'package:flutter/material.dart';
import '../pages/login_page.dart';
import '../services/auth_lifecycle_service.dart';
import '../services/host_auth_state.dart';
import '../services/privacy_agreement_service.dart';

/// Single host route; cancellation keeps the caller and its state alive.
class HostLogin {
  @visibleForTesting
  static Widget Function(BuildContext, VoidCallback)? debugLoginBuilder;
  @visibleForTesting
  static Future<void> Function()? debugPrepare;
  static Future<bool>? _pending;
  static Future<bool> open(BuildContext context) =>
      _pending ??= _open(context).whenComplete(() => _pending = null);

  static Future<bool> _open(BuildContext context) async {
    if (!await PrivacyAgreementService.isAccepted() ||
        !context.mounted ||
        HostAuthState.snapshot.value.status == HostAuthStatus.storageError) {
      return false;
    }
    await (debugPrepare ?? AuthLifecycleService.prepareInteractiveLogin)();
    if (!context.mounted) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (loginContext) {
          void completed() => Navigator.of(loginContext).pop(true);
          return debugLoginBuilder?.call(loginContext, completed) ??
              LoginPage(onLoginSuccess: completed);
        },
      ),
    );
    return result == true;
  }
}
