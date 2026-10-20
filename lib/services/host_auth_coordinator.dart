import 'identity_silent_login_service.dart';
import 'auth_lifecycle_service.dart';
import 'auth_service.dart';
import 'global_preferences_migration.dart';
import 'host_auth_state.dart';
import 'legacy_session_migration_executor.dart';

class HostAuthCoordinator {
  static Future<void>? _check;
  static Future<void>? _initialization;
  static int _generation = 0;
  static DateTime? _checkedAt;
  static int? _checkedRevision;
  static DateTime? _attemptedAt;
  static int? _attemptedRevision;

  static Future<void> initialize() =>
      _initialization ??= _initialize().whenComplete(
        () => _initialization = null,
      );

  static Future<void> _initialize() async {
    final generation = ++_generation;
    try {
      final migration = await SessionMigrationBootstrap.ensure();
      if (!migration.isSuccessful) throw StateError('Session migration failed');
      final account = await AuthService.getCurrentAccount();
      await GlobalPreferencesMigration.ensure(account?.accountKey);
      if (generation != _generation) return;
      HostAuthState.update(
        account == null ? HostAuthStatus.guest : HostAuthStatus.checking,
        accountKey: account?.accountKey,
      );
    } catch (_) {
      if (generation == _generation) {
        HostAuthState.update(HostAuthStatus.storageError);
      }
    }
  }

  static Future<void> check({bool force = false}) {
    if (!force &&
        HostAuthState.snapshot.value.status == HostAuthStatus.unavailable &&
        _attemptedRevision == AuthService.sessionRevision &&
        _attemptedAt != null &&
        DateTime.now().difference(_attemptedAt!) <
            const Duration(seconds: 15)) {
      return Future<void>.value();
    }
    if (!force &&
        HostAuthState.snapshot.value.status == HostAuthStatus.available &&
        _checkedRevision == AuthService.sessionRevision &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < const Duration(minutes: 3)) {
      return Future<void>.value();
    }
    return _check ??= _runCheck().whenComplete(() => _check = null);
  }

  static Future<void> _runCheck() async {
    if (HostAuthState.snapshot.value.status == HostAuthStatus.storageError) {
      return;
    }
    final generation = _generation;
    final revision = AuthService.sessionRevision;
    final owner = HostAuthState.snapshot.value.accountKey;
    if (owner == null) return;
    _attemptedAt = DateTime.now();
    _attemptedRevision = revision;
    HostAuthState.update(HostAuthStatus.checking, accountKey: owner);
    try {
      final result = await AuthLifecycleService.restoreForResume();
      if (generation != _generation ||
          revision != AuthService.sessionRevision &&
              result.recoveryOutcome != IdentityRecoveryOutcome.success) {
        return;
      }
      final current = await AuthService.getCurrentAccount();
      if (generation != _generation) return;
      if (current == null) {
        signedOut();
        return;
      }
      if (current.accountKey != owner) return;
      final status = switch (result.status) {
        AuthLifecycleStatus.authenticated => HostAuthStatus.available,
        AuthLifecycleStatus.manualLoginRequired => HostAuthStatus.loginRequired,
        AuthLifecycleStatus.retryableFailure => HostAuthStatus.unavailable,
        AuthLifecycleStatus.noAccount => HostAuthStatus.guest,
      };
      HostAuthState.update(status, accountKey: owner);
      if (status == HostAuthStatus.available) {
        _checkedAt = DateTime.now();
        _checkedRevision = AuthService.sessionRevision;
        AuthLifecycleService.warmUpPersistedAccount(owner);
      }
    } catch (_) {
      if (generation == _generation &&
          HostAuthState.snapshot.value.accountKey == owner) {
        HostAuthState.update(HostAuthStatus.unavailable, accountKey: owner);
      }
    }
  }

  static void requireLogin() {
    _checkedAt = null;
    final owner = HostAuthState.snapshot.value.accountKey;
    if (HostAuthState.snapshot.value.status != HostAuthStatus.storageError) {
      HostAuthState.update(
        owner == null ? HostAuthStatus.guest : HostAuthStatus.loginRequired,
        accountKey: owner,
      );
    }
  }

  static Future<void> accountInstalled() async {
    _checkedAt = null;
    final generation = ++_generation;
    final account = await AuthService.getCurrentAccount();
    if (generation != _generation) return;
    HostAuthState.update(
      account == null ? HostAuthStatus.guest : HostAuthStatus.available,
      accountKey: account?.accountKey,
      contentChanged: true,
    );
  }

  static void signedOut() {
    _checkedAt = null;
    ++_generation;
    HostAuthState.update(HostAuthStatus.guest, contentChanged: true);
  }

  static Future<void> retry() async {
    if (HostAuthState.snapshot.value.status == HostAuthStatus.storageError) {
      await initialize();
    }
    await check(force: true);
  }
}
