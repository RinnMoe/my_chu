import 'dart:async';

import 'package:flutter/foundation.dart';

import '../capabilities/alert_center.dart';
import '../capabilities/desktop_widgets/desktop_widget_bridge.dart';
import '../models/account.dart';
import '../services/credential_sync_service.dart';
import '../services/identity_silent_login_service.dart';
import '../services/live_update_service.dart';
import '../services/logger_service.dart';
import '../services/login_required_notifier.dart';
import '../services/auth_service.dart';
import '../services/saved_login_credential_service.dart';
import '../services/scheduled_alert_service.dart';
import '../capabilities/web_view_cookie_coordinator.dart';

enum AuthLifecycleStatus {
  noAccount,
  authenticated,
  retryableFailure,
  manualLoginRequired,
}

class AuthLifecycleResult {
  final AuthLifecycleStatus status;
  final IdentityRecoveryOutcome? recoveryOutcome;
  final String message;
  final String? accountKey;

  const AuthLifecycleResult({
    required this.status,
    this.recoveryOutcome,
    this.message = '',
    this.accountKey,
  });

  bool get isAuthenticated => status == AuthLifecycleStatus.authenticated;
}

/// Owns the host-level transition between no account, restored identity,
/// silent recovery and interactive login. Business applications never call it
/// to obtain cookies; they use CampusSession or host capabilities instead.
class AuthLifecycleService {
  /// Test seam for observing that successful restore starts warm-up without
  /// contacting campus services from a unit test.
  @visibleForTesting
  static void Function(String accountKey)? debugWarmup;

  @visibleForTesting
  static void debugReset() {
    debugWarmup = null;
  }

  static Future<AuthLifecycleResult> restore() async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      CredentialSyncService.cancel();
      return const AuthLifecycleResult(status: AuthLifecycleStatus.noAccount);
    }

    final probe = await IdentitySilentLoginService.probeCurrentSession(
      accountKey: account.accountKey,
    );
    switch (probe) {
      case IdentityProbeStatus.authenticated:
        _startCoreWarmup(account.accountKey);
        return AuthLifecycleResult(
          status: AuthLifecycleStatus.authenticated,
          accountKey: account.accountKey,
          message: '统一身份会话已恢复',
        );
      case IdentityProbeStatus.indeterminate:
        return AuthLifecycleResult(
          status: AuthLifecycleStatus.retryableFailure,
          accountKey: account.accountKey,
          message: '暂时无法确认统一身份登录状态，请检查网络后重试。',
        );
      case IdentityProbeStatus.unauthenticated:
        break;
    }

    final recovery = await IdentitySilentLoginService.tryRecover(
      accountKey: account.accountKey,
    );
    if (recovery.isSuccess) {
      final current = await AuthService.getCurrentAccount();
      if (current == null || current.accountKey != account.accountKey) {
        return const AuthLifecycleResult(
          status: AuthLifecycleStatus.retryableFailure,
          message: '账号状态已变化，请重试。',
        );
      }
      _startCoreWarmup(current.accountKey);
      return AuthLifecycleResult(
        status: AuthLifecycleStatus.authenticated,
        accountKey: current.accountKey,
        recoveryOutcome: recovery.outcome,
        message: '统一身份会话已自动恢复',
      );
    }

    switch (recovery.outcome) {
      case IdentityRecoveryOutcome.networkError:
      case IdentityRecoveryOutcome.coolingDown:
        return AuthLifecycleResult(
          status: AuthLifecycleStatus.retryableFailure,
          accountKey: account.accountKey,
          recoveryOutcome: recovery.outcome,
          message: '暂时无法恢复统一身份登录状态，请稍后重试。',
        );
      case IdentityRecoveryOutcome.noSavedCredential:
      case IdentityRecoveryOutcome.captchaRequired:
      case IdentityRecoveryOutcome.invalidCredential:
        await DesktopWidgetSyncService.clearSchedule();
        return AuthLifecycleResult(
          status: AuthLifecycleStatus.manualLoginRequired,
          accountKey: account.accountKey,
          recoveryOutcome: recovery.outcome,
          message: _manualLoginMessage(recovery.outcome),
        );
      case IdentityRecoveryOutcome.success:
        // Handled above; keeping the branch makes future enum additions
        // compiler-visible.
        return AuthLifecycleResult(
          status: AuthLifecycleStatus.retryableFailure,
          accountKey: account.accountKey,
          recoveryOutcome: recovery.outcome,
          message: '账号恢复状态异常，请重试。',
        );
    }
  }

  static Future<AuthLifecycleResult> retryRestore() => restore();

  /// Starts non-blocking account-scoped warm-up after local account restore
  /// and the privacy gate. Requests still validate and recover credentials
  /// through CampusSession when a service is actually used.
  static void warmUpPersistedAccount(String accountKey) {
    _startCoreWarmup(accountKey);
  }

  /// Clears platform WebView cookies before the UI enters interactive login.
  /// A reset failure is logged but must not prevent the user from opening the
  /// manual login page.
  static Future<void> prepareInteractiveLogin() async {
    try {
      await WebViewCookieCoordinator.resetCookies();
    } catch (error) {
      AppLogger.warn('进入手动登录前清理 WebView cookies 失败 (${error.runtimeType})');
    }
  }

  /// Installs a newly confirmed interactive identity and starts only the
  /// account-scoped, non-blocking core warm-up.
  static Future<void> installInteractiveAccount(
    Account account, {
    String? rootIdentityCookies,
  }) async {
    // Remove the previous identity's private schedule before persisting the
    // newly confirmed account.
    await DesktopWidgetSyncService.clearSchedule();
    try {
      await LiveUpdateService.clearAccountData();
    } catch (_) {}
    try {
      await ScheduledAlertService.clearAll();
    } catch (_) {}
    // Saved passwords are host-scoped rather than Account-scoped. Clear the
    // previous user's value before replacing the active account; the login
    // page may save the newly captured password immediately afterwards.
    await SavedLoginCredentialService.clearCredential();
    await AuthService.addAccount(
      account,
      rootIdentityCookies: rootIdentityCookies,
    );
    LoginRequiredNotifier.resetAfterLogin();
    _startCoreWarmup(account.accountKey);
  }

  static void _startCoreWarmup(String accountKey) {
    final warmup = debugWarmup;
    if (warmup != null) {
      warmup(accountKey);
      return;
    }
    unawaited(CredentialSyncService.startForAccount(accountKey));
    unawaited(AlertCenterService.importScheduledReceipts(accountKey));
  }

  static String _manualLoginMessage(IdentityRecoveryOutcome outcome) {
    return switch (outcome) {
      IdentityRecoveryOutcome.captchaRequired => '统一身份认证需要验证码，请手动登录。',
      IdentityRecoveryOutcome.invalidCredential => '保存的登录信息已失效，请手动登录。',
      IdentityRecoveryOutcome.noSavedCredential => '没有可用的自动登录信息，请手动登录。',
      _ => '请手动完成统一身份认证。',
    };
  }

  /// Performs account/session cleanup and the platform WebView boundary in a
  /// single host operation. The low-level AuthService remains usable by tests
  /// and storage callers, but UI sign-out goes through this method.
  static Future<void> signOut() async {
    CredentialSyncService.cancel();
    final clearWidgetFuture = DesktopWidgetSyncService.clearSchedule();
    // The session fence is invalidated synchronously at operation entry. The
    // first platform reset also advances cookieManagerEpoch immediately, but
    // its final barrier is repeated after account persistence cleanup below.
    final clearFuture = AuthService.clearAll();
    final initialResetFuture = WebViewCookieCoordinator.resetCookies();
    try {
      await LiveUpdateService.clearAccountData();
    } catch (_) {}
    try {
      await ScheduledAlertService.clearAll();
    } catch (_) {}
    try {
      await clearFuture;
    } finally {
      await clearWidgetFuture;
      await DesktopWidgetSyncService.clearSchedule();
      try {
        await initialResetFuture;
      } catch (_) {
        // Always attempt the post-clear barrier even if the first reset failed.
      }
      try {
        await WebViewCookieCoordinator.resetCookies(finalBarrier: true);
      } catch (error) {
        AppLogger.warn('退出登录清理 WebView cookies 失败 (${error.runtimeType})');
      }
    }
    LoginRequiredNotifier.markPromptDismissed();
  }
}
