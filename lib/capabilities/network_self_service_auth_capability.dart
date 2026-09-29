import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/campus_service_id.dart';
import '../services/campus_service_session_service.dart';
import '../services/network_self_service_auth_service.dart';

/// Feature-facing handle for the network self-service login flow.
///
/// This capability exposes only typed readiness/challenge states. The shared
/// session broker retains the temporary cookie jar, CSRF token and encrypted
/// password while it processes each challenge.
class NetworkSelfServiceAuthCapability {
  NetworkSelfServiceAuthCapability._();

  /// Test seam for widget states; production callers leave this unset.
  @visibleForTesting
  static Future<NetworkSelfServiceAuthState> Function()? debugPrepare;

  /// Test seam for the captcha challenge refresh path.
  @visibleForTesting
  static Future<NetworkSelfServiceAuthState> Function(String challengeId)?
  debugRefreshCaptcha;

  /// Test seam for returning a deterministic captcha result from submission.
  @visibleForTesting
  static Future<NetworkSelfServiceAuthState> Function(
    String challengeId,
    String code,
  )?
  debugSubmitCaptcha;

  /// Test seam for returning a deterministic SMS result from submission.
  @visibleForTesting
  static Future<NetworkSelfServiceAuthState> Function(
    String challengeId,
    String code,
  )?
  debugSubmitSms;

  static Future<NetworkSelfServiceAuthState> prepare() async {
    final override = debugPrepare;
    if (override != null) return override();
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      return const NetworkSelfServiceAuthState(
        NetworkSelfServiceAuthStatus.networkError,
        message: '请先登录 MyCHU。',
      );
    }
    try {
      final session = await CampusSessionService.get(
        CampusServices.networkSelfService,
      );
      if (session != null) {
        return const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.ready,
        );
      }
    } catch (_) {
      return const NetworkSelfServiceAuthState(
        NetworkSelfServiceAuthStatus.networkError,
        message: '网络自服暂时无法连接，请稍后重试。',
      );
    }
    return NetworkSelfServiceAuthService.stateFor(account.accountKey);
  }

  static Future<NetworkSelfServiceAuthState> submitCaptcha(
    String challengeId,
    String code,
  ) async {
    final override = debugSubmitCaptcha;
    if (override != null) return override(challengeId, code);
    final account = await AuthService.getCurrentAccount();
    if (account == null) return _noAccountState;
    if (!NetworkSelfServiceAuthService.provideCaptcha(
      account.accountKey,
      challengeId,
      code,
    )) {
      return NetworkSelfServiceAuthService.stateFor(account.accountKey);
    }
    await _resume(account.accountKey);
    return NetworkSelfServiceAuthService.stateFor(account.accountKey);
  }

  static Future<NetworkSelfServiceAuthState> submitSms(
    String challengeId,
    String code,
  ) async {
    final override = debugSubmitSms;
    if (override != null) return override(challengeId, code);
    final account = await AuthService.getCurrentAccount();
    if (account == null) return _noAccountState;
    if (!NetworkSelfServiceAuthService.provideSms(
      account.accountKey,
      challengeId,
      code,
    )) {
      return NetworkSelfServiceAuthService.stateFor(account.accountKey);
    }
    await _resume(account.accountKey);
    return NetworkSelfServiceAuthService.stateFor(account.accountKey);
  }

  static Future<NetworkSelfServiceAuthState> refreshCaptcha(
    String challengeId,
  ) async {
    final override = debugRefreshCaptcha;
    if (override != null) return override(challengeId);
    final account = await AuthService.getCurrentAccount();
    if (account == null) return _noAccountState;
    return NetworkSelfServiceAuthService.refreshCaptcha(
      account.accountKey,
      challengeId,
    );
  }

  static Future<void> _resume(String accountKey) async {
    try {
      await CampusSessionService.get(
        CampusServices.networkSelfService,
        forceRefresh: true,
      );
    } catch (_) {
      // The typed state is returned below; the UI should not display a raw
      // exception from the credential layer.
    }
  }

  static const _noAccountState = NetworkSelfServiceAuthState(
    NetworkSelfServiceAuthStatus.networkError,
    message: '请先登录 MyCHU。',
  );
}
