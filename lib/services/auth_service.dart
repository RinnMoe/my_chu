import 'time_reminder_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../capabilities/account_scoped_cache.dart';
import '../capabilities/persistent_summary_cache.dart';
import '../models/account.dart';
import '../services/account_network_session_service.dart';
import '../services/logger_service.dart';
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
  static int _identityRevision = 0;

  /// Monotonic in-memory generation for the active account/root session.
  /// Background credential work captures it and must discard results from an
  /// older generation, even when the local account key remains unchanged.
  static int get sessionRevision => _sessionRevision;

  /// Monotonic in-memory generation for the active *identity*.
  ///
  /// It advances only when the account itself changes: a manual login, an
  /// account switch, a hard interactive reset or a logout. A same-account root
  /// refresh advances [sessionRevision] but keeps this value, because the
  /// persisted service sessions derived from the identity remain usable.
  /// Cache reuse decisions key on this value; [sessionRevision] keeps fencing
  /// in-flight exchanges and background batches.
  ///
  /// Unlike [CampusSessionStore.identityEpoch], this counter is process-local
  /// and does not decide whether persisted credentials belong to the identity;
  /// it only keeps in-process cache decisions coherent.
  static int get identityRevision => _identityRevision;

  static void _advanceSessionRevision() {
    _sessionRevision++;
    sessionRevisionNotifier.value = _sessionRevision;
  }

  static void _advanceIdentityRevision() {
    _identityRevision++;
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
      _advanceIdentityRevision();
      NetworkSelfServiceAuthService.clearAll();
      await TimeReminderService.clearAll();
      AccountNetworkSessionService.discardAll();
      AccountCacheRegistry.invalidateAll();
      await PersistentCacheRegistry.clearAll();

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

  /// Replaces the root unified-identity session.
  ///
  /// By default only the root cookies are refreshed: the account key and the
  /// identity epoch stay stable, and every service session derived from the
  /// previous CAS login remains usable. This mirrors a browser, where signing
  /// in to CAS again does not log the user out of sites that already issued
  /// their own session cookies.
  ///
  /// Pass [resetDerivedSessions] when the caller deliberately wants a hard
  /// reset (interactive login) and every derived service credential must be
  /// dropped.
  static Future<Account?> replaceIdentityCookies(
    String accountKey,
    String authCookies, {
    bool resetDerivedSessions = false,
  }) async {
    if (authCookies.isEmpty) return null;
    // A pending captcha/SMS transaction belongs to the previous identity
    // challenge and must not survive any root refresh.
    NetworkSelfServiceAuthService.clearAll();
    // Every root refresh advances the runtime revision so in-flight work
    // re-fences against the new credentials. Unlike [resetDerivedSessions],
    // this does not drop the persisted service sessions.
    _advanceSessionRevision();
    final current = await getCurrentAccount();
    if (current == null || current.accountKey != accountKey) return null;
    if (resetDerivedSessions) {
      // A hard reset starts a new identity generation before any derived state
      // is touched, so cache reuse cannot observe the previous identity while
      // the reset is still in flight.
      _advanceIdentityRevision();
    }
    final sessionStore = await CampusSessionStore.open(accountKey: accountKey);
    if (!resetDerivedSessions) {
      await sessionStore.replaceRootCookies(authCookies);
      // ScopedCookieJar.seed merges by name, so a removed root cookie would
      // otherwise survive in the in-memory transport. Clear only the root
      // identity scopes; derived service sessions remain reusable.
      AccountNetworkSessionService.clearRootIdentity(accountKey);
      // The refreshed root identity proves the previous failure was
      // environmental; let callers retry now instead of waiting out the
      // account-scoped failure cooldown.
      AccountCacheRegistry.clearFailures();
      return current;
    }
    await sessionStore.replaceRootIdentity();
    await sessionStore.seedRootIdentityCookies(authCookies);
    // Discard the shared transport after replacing the root epoch so old
    // service cookies cannot survive the identity replacement.
    AccountNetworkSessionService.discard(accountKey);
    AccountCacheRegistry.clearFailures();
    return current;
  }

  static Future<void> clearAll() async {
    // Advance before entering the serialized persistence queue. A sign-out
    // caller can then start the platform-cookie reset immediately without a
    // window in which an older session fence still appears current.
    _advanceSessionRevision();
    _advanceIdentityRevision();
    await _serializeWrite(() async {
      await TimeReminderService.clearAll();
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
