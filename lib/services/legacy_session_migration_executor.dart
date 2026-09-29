import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/account.dart';
import 'campus_session_store.dart';
import 'current_account_store.dart';
import 'persistent_campus_cookie_jar.dart';
import 'session_storage_support.dart';

List<T> _dedupeLatestByAccountKey<T>(
  Iterable<T> source, {
  required String Function(T) accountKeyOf,
  required DateTime Function(T) loginTimeOf,
}) {
  final byAccountKey = <String, T>{};
  for (final account in source) {
    final accountKey = accountKeyOf(account);
    final existing = byAccountKey[accountKey];
    if (existing == null ||
        loginTimeOf(account).isAfter(loginTimeOf(existing))) {
      byAccountKey[accountKey] = account;
    }
  }
  return byAccountKey.values.toList()
    ..sort((a, b) => loginTimeOf(a).compareTo(loginTimeOf(b)));
}

/// Parser-only representation of the pre-v2 account JSON. Only profile data
/// and the root identity cookie are carried into the v2 stores.
class LegacyAccountSessionRecord {
  const LegacyAccountSessionRecord({
    required this.accountKey,
    required this.uid,
    required this.identity,
    required this.name,
    required this.cookies,
    required this.authCookies,
    required this.mobileCampusUuId,
    required this.mobileCampusUserId,
    required this.loginTime,
  });

  final String accountKey;
  final String? uid;
  final String? identity;
  final String name;
  final String cookies;
  final String? authCookies;
  final String? mobileCampusUuId;
  final String? mobileCampusUserId;
  final DateTime loginTime;

  Account toProfileAccount() => Account(
    id: accountKey,
    uid: uid,
    identity: identity,
    name: name,
    mobileCampusUuId: mobileCampusUuId,
    mobileCampusUserId: mobileCampusUserId,
    loginTime: loginTime,
  );

  String get rootIdentityCookies =>
      authCookies?.isNotEmpty == true ? authCookies! : cookies;
}

/// Reads the selected pre-v2 account and copies only its profile and root
/// identity into the v2 stores. Derived service cookies, path sessions and
/// token artifacts are deliberately ignored.
class LegacySessionMigrationExecutor {
  LegacySessionMigrationExecutor({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const legacyAccountsKey = 'accounts';
  static const legacyCurrentAccountIdKey = 'current_account_id';

  final FlutterSecureStorage _storage;

  Future<LegacyAccountSessionRecord?> loadCurrentAccount() async {
    final rawAccounts = await _storage.read(key: legacyAccountsKey);
    final currentAccountId = await _storage.read(
      key: legacyCurrentAccountIdKey,
    );
    final noLegacySource = rawAccounts == null && currentAccountId == null;
    if (noLegacySource) return null;
    if (rawAccounts == null ||
        rawAccounts.isEmpty ||
        currentAccountId == null ||
        currentAccountId.trim().isEmpty) {
      throw const FormatException('legacy account storage is incomplete');
    }

    final deduped = _parseLegacyAccounts(rawAccounts);
    for (final account in deduped) {
      if (account.accountKey == currentAccountId) return account;
    }
    throw const FormatException('legacy current account cannot be resolved');
  }

  Future<Set<String>> loadKnownAccountKeys() async {
    final rawAccounts = await _storage.read(key: legacyAccountsKey);
    if (rawAccounts == null) return const <String>{};
    return _parseLegacyAccounts(
      rawAccounts,
    ).map((account) => account.accountKey).toSet();
  }

  static List<LegacyAccountSessionRecord> _parseLegacyAccounts(
    String rawAccounts,
  ) {
    if (rawAccounts.isEmpty) {
      throw const FormatException('legacy account storage is incomplete');
    }
    final decoded = jsonDecode(rawAccounts);
    if (decoded is! List) {
      throw const FormatException('legacy accounts must be a JSON list');
    }

    final accounts = <LegacyAccountSessionRecord>[];
    for (final item in decoded) {
      if (item is! Map) {
        throw const FormatException('legacy account must be an object');
      }
      final map = Map<String, dynamic>.from(item);
      accounts.add(_legacyAccountFromJson(map));
    }
    return _dedupeLatestByAccountKey(
      accounts,
      accountKeyOf: (account) => account.accountKey,
      loginTimeOf: (account) => account.loginTime,
    );
  }

  Future<void> writeSession(LegacyAccountSessionRecord account) async {
    final store = await CampusSessionStore.open(
      accountKey: account.accountKey,
      storage: _storage,
    );
    // Clear any partial/derived records before retrying the root-only copy.
    await store.replaceRootIdentity();
    if (account.rootIdentityCookies.isNotEmpty) {
      await store.seedRootIdentityCookies(account.rootIdentityCookies);
    }
  }

  Future<bool> verifySession(LegacyAccountSessionRecord account) async {
    final root = account.rootIdentityCookies;
    if (root.isEmpty) return true;
    final store = await CampusSessionStore.open(
      accountKey: account.accountKey,
      storage: _storage,
    );
    final actual = await store.rootCookieHeader();
    return _containsCookies(actual, root);
  }

  Future<void> writeAccountProfile(LegacyAccountSessionRecord account) =>
      CurrentAccountStore(storage: _storage).write(account.toProfileAccount());

  Future<bool> verifyAccountProfile(LegacyAccountSessionRecord account) =>
      CurrentAccountStore(
        storage: _storage,
      ).matches(account.toProfileAccount());

  static String? _legacyAccountKey(Map<String, dynamic> json) {
    final value = json['accountKey'] ?? json['id'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  static LegacyAccountSessionRecord _legacyAccountFromJson(
    Map<String, dynamic> json,
  ) {
    final accountKey = _legacyAccountKey(json);
    final loginTime = DateTime.tryParse(_string(json['loginTime']) ?? '');
    if (accountKey == null || loginTime == null) {
      throw const FormatException('invalid legacy account profile');
    }
    return LegacyAccountSessionRecord(
      accountKey: accountKey,
      uid:
          _string(json['uid']) ??
          (_looksLikeUid(accountKey) ? accountKey : null),
      identity: _string(json['identity']),
      name: _string(json['name']) ?? 'CHUer',
      cookies: _string(json['cookies']) ?? '',
      authCookies: _string(json['authCookies']),
      mobileCampusUuId: _string(json['mobileCampusUuId']),
      mobileCampusUserId: _string(json['mobileCampusUserId']),
      loginTime: loginTime,
    );
  }

  static String? _string(Object? value) => value is String ? value : null;

  static bool _looksLikeUid(String value) =>
      RegExp(r'^\d{6,}$').hasMatch(value);

  static bool _containsCookies(String actual, String expected) {
    final actualMap = PersistentCampusCookieJar.parseCookieHeader(actual);
    final expectedMap = PersistentCampusCookieJar.parseCookieHeader(expected);
    return expectedMap.entries.every(
      (entry) => actualMap[entry.key] == entry.value,
    );
  }
}

enum SessionMigrationOutcome { ready, retryableFailure }

class SessionMigrationResult {
  const SessionMigrationResult({required this.outcome, this.errorType});

  final SessionMigrationOutcome outcome;
  final String? errorType;

  bool get isSuccessful => outcome == SessionMigrationOutcome.ready;
}

/// Startup-only, single-flight migration gate for the v2 account schema.
class SessionMigrationBootstrap {
  SessionMigrationBootstrap._();

  static const currentSchemaVersion = 2;
  static const sessionSchemaVersionKey = 'session_schema_version';
  static const migrationStateKey = 'migration_state';
  static const migrationSourceHashKey = 'migration_source_hash';
  static const currentAccountIdV2Key = 'current_account_id.v2';

  static Future<SessionMigrationResult>? _pending;

  static Future<SessionMigrationResult> ensure() {
    final pending = _pending;
    if (pending != null) return pending;
    final future = _run();
    _pending = future;
    future.whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
    return future;
  }

  static Future<SessionMigrationResult> _run() async {
    const storage = FlutterSecureStorage();
    try {
      final schemaVersion = await storage.read(key: sessionSchemaVersionKey);
      if (schemaVersion != null &&
          schemaVersion != currentSchemaVersion.toString()) {
        throw const FormatException('unsupported session schema version');
      }

      final executor = LegacySessionMigrationExecutor(storage: storage);
      if (schemaVersion == currentSchemaVersion.toString()) {
        await _normalizeV2(storage);
      } else {
        final legacy = await executor.loadCurrentAccount();
        final v2Raw = await storage.read(key: CurrentAccountStore.accountsKey);
        final v2CurrentId = await storage.read(key: currentAccountIdV2Key);
        if (legacy != null) {
          final legacyAccountKeys = await executor.loadKnownAccountKeys();
          await _clearOrphanedCampusSessions(
            storage: storage,
            historicalAccountKeys: legacyAccountKeys,
            currentAccountKey: legacy.accountKey,
          );
          await executor.writeSession(legacy);
          var sessionVerified = await executor.verifySession(legacy);
          if (!sessionVerified) {
            await executor.writeSession(legacy);
            sessionVerified = await executor.verifySession(legacy);
          }
          if (!sessionVerified) {
            throw StateError('root session read-back verification failed');
          }

          await executor.writeAccountProfile(legacy);
          var profileVerified = await executor.verifyAccountProfile(legacy);
          if (!profileVerified) {
            await executor.writeAccountProfile(legacy);
            profileVerified = await executor.verifyAccountProfile(legacy);
          }
          if (!profileVerified) {
            throw StateError('account profile read-back verification failed');
          }
        } else if (v2Raw != null || v2CurrentId != null) {
          // Recover a v2 write that completed before its formal marker.
          await _normalizeV2(storage);
        } else {
          await storage.write(
            key: CurrentAccountStore.accountsKey,
            value: jsonEncode(const <Object?>[]),
          );
        }
        // This is the only durable completion marker. It is written after all
        // new-side data has been read back successfully.
        await storage.write(
          key: sessionSchemaVersionKey,
          value: currentSchemaVersion.toString(),
        );
      }

      // Cleanup is intentionally after the formal marker. If it fails, the
      // next startup sees schema v2 and retries cleanup without re-migrating.
      await _cleanupObsoleteKeys(storage);
      return const SessionMigrationResult(
        outcome: SessionMigrationOutcome.ready,
      );
    } catch (error) {
      return SessionMigrationResult(
        outcome: SessionMigrationOutcome.retryableFailure,
        errorType: error.runtimeType.toString(),
      );
    }
  }

  static Future<void> _normalizeV2(FlutterSecureStorage storage) async {
    final raw = await storage.read(key: CurrentAccountStore.accountsKey);
    final currentId = await storage.read(key: currentAccountIdV2Key);
    if (raw == null) {
      if (currentId != null && currentId.trim().isNotEmpty) {
        throw const FormatException('v2 current account cannot be resolved');
      }
      return;
    }
    if (raw.isEmpty) {
      throw const FormatException('v2 account storage is empty');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('v2 accounts must be a JSON list');
    }
    if (decoded.isEmpty) {
      if (currentId != null && currentId.trim().isNotEmpty) {
        throw const FormatException('v2 current account cannot be resolved');
      }
      return;
    }

    final accounts = <Account>[
      for (final item in decoded)
        if (item is Map)
          Account.fromProfileJson(Map<String, dynamic>.from(item))
        else
          throw const FormatException('v2 account profile must be an object'),
    ];
    final deduped = _dedupeLatestByAccountKey(
      accounts,
      accountKeyOf: (account) => account.accountKey,
      loginTimeOf: (account) => account.loginTime,
    );
    late final Account selected;
    if (deduped.length == 1) {
      selected = deduped.single;
      if (currentId != null &&
          currentId.trim().isNotEmpty &&
          currentId != selected.accountKey) {
        throw const FormatException('v2 current account cannot be resolved');
      }
    } else {
      if (currentId == null || currentId.trim().isEmpty) {
        throw const FormatException('v2 current account is missing');
      }
      final matches =
          deduped.where((account) => account.accountKey == currentId).toList();
      if (matches.length != 1) {
        throw const FormatException('v2 current account cannot be resolved');
      }
      selected = matches.single;
    }
    await _clearOrphanedCampusSessions(
      storage: storage,
      historicalAccountKeys: deduped.map((account) => account.accountKey),
      currentAccountKey: selected.accountKey,
    );
    await CurrentAccountStore(storage: storage).write(selected);
  }

  static Future<void> _clearOrphanedCampusSessions({
    required FlutterSecureStorage storage,
    required Iterable<String> historicalAccountKeys,
    required String currentAccountKey,
  }) async {
    for (final accountKey in historicalAccountKeys.toSet()) {
      if (accountKey == currentAccountKey) continue;
      await AccountSessionStorageQueue.clearAccountKeys(
        storage: storage,
        accountKey: accountKey,
      );
    }
  }

  static Future<void> _cleanupObsoleteKeys(FlutterSecureStorage storage) async {
    for (final key in const [
      LegacySessionMigrationExecutor.legacyAccountsKey,
      LegacySessionMigrationExecutor.legacyCurrentAccountIdKey,
      currentAccountIdV2Key,
      migrationStateKey,
      migrationSourceHashKey,
    ]) {
      await storage.delete(key: key);
    }
  }
}
