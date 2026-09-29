import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../apps/app_service.dart';
import '../capabilities/alert_center.dart';
import '../capabilities/account_scoped_cache.dart';
import '../capabilities/persistent_summary_cache.dart';
import '../models/account.dart';
import '../services/account_network_session_service.dart';
import '../services/logger_service.dart';
import '../services/in_app_notification_service.dart';
import '../services/saved_login_credential_service.dart';
import '../services/network_self_service_auth_service.dart';
import '../services/campus_session_store.dart';
import '../services/current_account_store.dart';
import '../services/session_runtime_fence.dart';
import '../services/session_storage_support.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static Future<void> _writeTail = Future<void>.value();
  static int _sessionRevision = 0;
  static final sessionRevisionNotifier = ValueNotifier<int>(0);

  /// Monotonic in-memory generation for the active account/root session.
  /// Background credential work captures it and must discard results from an
  /// older generation, even when the local account key remains unchanged.
  static int get sessionRevision => _sessionRevision;

  static void _advanceSessionRevision() {
    _sessionRevision++;
    sessionRevisionNotifier.value = _sessionRevision;
  }

  static Future<Account?> getCurrentAccount() =>
      CurrentAccountStore(storage: _storage).read();

  static Future<void> addAccount(
    Account account, {
    String? rootIdentityCookies,
  }) async {
    // MyCHU keeps one active account. A fresh login deliberately replaces the
    // previous account instead of accumulating accounts for later switching.
    await _serializeWrite(() async {
      _advanceSessionRevision();
      NetworkSelfServiceAuthService.clearAll();
      AlertCenterService.resetState();
      AccountNetworkSessionService.discardAll();
      AccountCacheRegistry.invalidateAll();
      await PersistentCacheRegistry.clearAll();
      await InAppNotificationService.clearAll();
      await AlertSubscriptionStore.clearAll();
      await AppService.clearAllRecent();
      await CurrentAccountStore(storage: _storage).write(account);
      final sessionStore = await CampusSessionStore.open(
        accountKey: account.accountKey,
      );
      await sessionStore.replaceRootIdentity();
      if (rootIdentityCookies != null && rootIdentityCookies.isNotEmpty) {
        await sessionStore.seedRootIdentityCookies(rootIdentityCookies);
      }
      AppLogger.info('已保存当前登录账号');
    });
  }

  /// Serializes mutations so concurrent credential refreshes cannot overwrite
  /// one another or invalidate an in-flight shared network session.
  static Future<Account?> patchAccount(
    String accountKey,
    Account Function(Account current) update, {
    int? expectedRevision,
  }) {
    return _serializeWrite(() async {
      if (expectedRevision != null && _sessionRevision != expectedRevision) {
        return null;
      }
      final current = await getCurrentAccount();
      if (current == null || current.accountKey != accountKey) return null;
      final updated = update(current);
      if (updated.accountKey != accountKey) {
        throw StateError('账号本地键不可修改');
      }
      if (expectedRevision != null && _sessionRevision != expectedRevision) {
        return null;
      }
      await CurrentAccountStore(storage: _storage).write(updated);
      return updated;
    });
  }

  /// Replaces the root unified-identity session and drops every credential
  /// derived from the previous root session. The local account key remains
  /// stable so account-scoped caches and UI state do not change owners.
  static Future<Account?> replaceIdentityCookies(
    String accountKey,
    String authCookies,
  ) async {
    if (authCookies.isEmpty) return null;
    _advanceSessionRevision();
    // Replacing the root identity invalidates every derived service challenge;
    // drop the network self-service transaction before the new epoch is
    // persisted so a pending captcha/SMS flow cannot survive the reset.
    NetworkSelfServiceAuthService.clearAll();
    final current = await getCurrentAccount();
    if (current == null || current.accountKey != accountKey) return null;
    final sessionStore = await CampusSessionStore.open(accountKey: accountKey);
    await sessionStore.replaceRootIdentity();
    await sessionStore.seedRootIdentityCookies(authCookies);
    // Discard the shared transport after replacing the root epoch so old
    // service cookies cannot survive the identity replacement.
    AccountNetworkSessionService.discard(accountKey);
    return current;
  }

  static Future<void> clearAll() async {
    // Advance before entering the serialized persistence queue. A sign-out
    // caller can then start the platform-cookie reset immediately without a
    // window in which an older session fence still appears current.
    _advanceSessionRevision();
    await _serializeWrite(() async {
      AlertCenterService.resetState();
      NetworkSelfServiceAuthService.clearAll();
      final account = await getCurrentAccount();
      if (account != null) {
        await CampusSessionStore.open(
          accountKey: account.accountKey,
        ).then((store) => store.clear());
      }
      await AccountSessionStorageQueue.clearAll(storage: _storage);
      // Only remove campus-owned global records here. The secure-storage
      // namespace also contains independent identities (for example the
      // channel-resources refresh credential), so deleteAll() would make a
      // campus logout implicitly sign out those services.
      await CurrentAccountStore(storage: _storage).clear();
      // 退出登录清除已保存的账号密码；“不再询问”偏好在
      // SharedPreferences 中保留，避免丢失用户的持久化选择。
      await SavedLoginCredentialService.clearCredential();
      AccountNetworkSessionService.discardAll();
      AccountCacheRegistry.invalidateAll();
      await PersistentCacheRegistry.clearAll();
      await InAppNotificationService.clearAll();
      await AlertSubscriptionStore.clearAll();
      await AppService.clearAllRecent();
      ServiceGenerationRegistry.clear();
    });
  }

  static Future<bool> hasAccounts() async {
    return await getCurrentAccount() != null;
  }

  static Future<T> _serializeWrite<T>(Future<T> Function() action) {
    final previous = _writeTail;
    final release = Completer<void>();
    _writeTail = release.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    })();
  }
}
