import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorageKeys {
  const SessionStorageKeys._();

  static const cookiePrefix = 'session.cookies.v2.';
  static const artifactPrefix = 'session.artifacts.v2.';
  static const identityEpochPrefix = 'session.identity-epoch.v2.';

  /// Returns whether a secure-storage key belongs to the campus session
  /// namespace. Other identity namespaces are left untouched by omission.
  static bool isCampusOwned(String key) {
    return key.startsWith(cookiePrefix) ||
        key.startsWith(artifactPrefix) ||
        key.startsWith(identityEpochPrefix);
  }

  static String accountSegment(String accountKey) =>
      Uri.encodeComponent(accountKey);

  static String cookieKey({
    required String accountKey,
    required String serviceId,
    required String scopeKey,
  }) =>
      '$cookiePrefix${accountSegment(accountKey)}.'
      '${Uri.encodeComponent(serviceId)}.${Uri.encodeComponent(scopeKey)}';

  static String artifactKey(String accountKey) =>
      '$artifactPrefix${accountSegment(accountKey)}';

  static String identityEpochKey(String accountKey) =>
      '$identityEpochPrefix${accountSegment(accountKey)}';

  static String accountPrefix(String prefix, String accountKey) =>
      '$prefix${accountSegment(accountKey)}';
}

/// Serializes all secure-storage writes belonging to one account, including
/// cookie, artifact, epoch replacement and logout cleanup operations.
class AccountSessionStorageQueue {
  AccountSessionStorageQueue._();

  static final Map<String, Future<void>> _tails = {};

  static Future<T> run<T>(String accountKey, Future<T> Function() operation) {
    final previous = _tails[accountKey];
    final release = Completer<void>();
    _tails[accountKey] = release.future;
    return (() async {
      if (previous != null) await previous;
      try {
        return await operation();
      } finally {
        release.complete();
        if (identical(_tails[accountKey], release.future)) {
          _tails.remove(accountKey);
        }
      }
    })();
  }

  static Future<void> clearAccountKeys({
    required FlutterSecureStorage storage,
    required String accountKey,
  }) => run(accountKey, () async {
    final encoded = SessionStorageKeys.accountSegment(accountKey);
    final all = await storage.readAll();
    final prefixes = [
      '${SessionStorageKeys.cookiePrefix}$encoded.',
      '${SessionStorageKeys.artifactPrefix}$encoded',
      '${SessionStorageKeys.identityEpochPrefix}$encoded',
    ];
    for (final key in all.keys.toList()) {
      if (prefixes.any(key.startsWith)) {
        await storage.delete(key: key);
      }
    }
  });

  /// Clears every persisted campus session, including accounts that are no
  /// longer present in the current account profile list.
  static Future<void> clearAll({required FlutterSecureStorage storage}) async {
    final pending = _tails.values.toList(growable: false);
    if (pending.isNotEmpty) await Future.wait(pending);
    final all = await storage.readAll();
    final keys = all.keys.where(SessionStorageKeys.isCampusOwned).toList();
    for (final key in keys) {
      await storage.delete(key: key);
    }
  }
}
