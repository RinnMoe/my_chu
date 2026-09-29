import 'dart:async';

import 'package:flutter/foundation.dart';

/// Account-scoped layered data cache shared by feature coordinators.
///
/// Layer 1 (single-flight): concurrent callers for the same account and
/// resource join the same in-flight future instead of issuing duplicate
/// network requests.
/// Layer 2 (short TTL): a successful value is kept in memory for [ttl] so
/// repeated UI construction within the TTL does not hit the network again.
/// When [allowStale] is true and only an expired value exists, [load] returns
/// it immediately and starts a background refresh; [revision] bumps when a
/// load completes so listeners can render the fresh value.
class AccountScopedCache<T> {
  AccountScopedCache({required this.ttl, this.allowStale = true}) {
    AccountCacheRegistry.register(this);
  }

  final Duration ttl;
  final bool allowStale;

  final Map<String, _AccountCacheEntry<T>> _entries = {};
  final Map<String, Future<T>> _inFlight = {};
  final Map<String, int> _generations = {};

  /// Bumped whenever a network load completes successfully.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Returns a fresh cached value, joins an active load, or starts one.
  ///
  /// When [force] is true the cache is bypassed for freshness and the loader
  /// runs again (still single-flighted while active).
  Future<T> load(
    String accountKey,
    Future<T> Function() loader, {
    bool force = false,
  }) {
    final entry = _entries[accountKey];
    if (!force && entry != null && entry.expiresAt.isAfter(DateTime.now())) {
      return Future<T>.value(entry.value);
    }
    final pending = _inFlight[accountKey];
    if (pending != null) return pending;
    if (!force && allowStale && entry != null) {
      _refreshInBackground(accountKey, loader);
      return Future<T>.value(entry.value);
    }
    return _track(accountKey, loader);
  }

  /// Returns the last known value without starting a load.
  T? peek(String accountKey) => _entries[accountKey]?.value;

  /// Whether a value exists and is still within [ttl].
  bool isFresh(String accountKey) {
    final entry = _entries[accountKey];
    return entry != null && entry.expiresAt.isAfter(DateTime.now());
  }

  /// When the last known value was stored, if any.
  DateTime? fetchedAt(String accountKey) => _entries[accountKey]?.fetchedAt;

  void invalidate(String accountKey) {
    _advanceGeneration(accountKey);
    _entries.remove(accountKey);
    _inFlight.remove(accountKey);
  }

  void invalidateAll() {
    for (final key in {..._entries.keys, ..._inFlight.keys}) {
      _advanceGeneration(key);
    }
    _entries.clear();
    _inFlight.clear();
  }

  /// Stores [value] with [fetchedAt] so [load] treats it as already-stale (or
  /// fresh within [ttl]) without running the loader.
  void seed(String accountKey, T value, {DateTime? fetchedAt}) {
    final time = fetchedAt ?? DateTime.now();
    _entries[accountKey] = _AccountCacheEntry(value, time, time.add(ttl));
  }

  /// Removes every entry whose key satisfies [test].
  void invalidateWhere(bool Function(String accountKey) test) {
    final keys = {..._entries.keys, ..._inFlight.keys}.where(test).toList();
    for (final key in keys) {
      invalidate(key);
    }
  }

  Future<T> _track(String accountKey, Future<T> Function() loader) async {
    final existing = _inFlight[accountKey];
    if (existing != null) return existing;
    final generation = _generationOf(accountKey);
    final future = _run(accountKey, generation, loader);
    _inFlight[accountKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[accountKey], future)) {
        _inFlight.remove(accountKey);
      }
    }
  }

  void _refreshInBackground(String accountKey, Future<T> Function() loader) {
    if (_inFlight.containsKey(accountKey)) return;
    final generation = _generationOf(accountKey);
    final future = _run(accountKey, generation, loader);
    _inFlight[accountKey] = future;
    unawaited(
      future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_inFlight[accountKey], future)) {
          _inFlight.remove(accountKey);
        }
      }),
    );
  }

  Future<T> _run(
    String accountKey,
    int generation,
    Future<T> Function() loader,
  ) async {
    final value = await loader();
    if (_generationOf(accountKey) != generation) return value;
    _entries[accountKey] = _AccountCacheEntry(
      value,
      DateTime.now(),
      DateTime.now().add(ttl),
    );
    revision.value++;
    return value;
  }

  int _generationOf(String accountKey) => _generations[accountKey] ?? 0;

  void _advanceGeneration(String accountKey) {
    _generations[accountKey] = _generationOf(accountKey) + 1;
  }
}

/// Central registry so sign-out and account replacement can drop every
/// account-scoped in-memory summary without each feature knowing about it.
class AccountCacheRegistry {
  static final List<AccountScopedCache<Object?>> _caches = [];
  static final List<AccountScopedBackoff> _backoffs = [];

  static void register<T>(AccountScopedCache<T> cache) {
    _caches.add(cache);
  }

  static void registerBackoff(AccountScopedBackoff backoff) {
    _backoffs.add(backoff);
  }

  static void invalidateAll() {
    for (final cache in _caches) {
      cache.invalidateAll();
    }
    for (final backoff in _backoffs) {
      backoff.clearAll();
    }
  }
}

/// Short-lived per-account failure gate so optional summaries do not retry a
/// failing service on every home rebuild or credential-sync notification.
class AccountScopedBackoff {
  AccountScopedBackoff({required this.duration}) {
    AccountCacheRegistry.registerBackoff(this);
  }

  final Duration duration;
  final Map<String, DateTime> _blockedUntil = {};

  bool isBlocked(String accountKey) {
    final until = _blockedUntil[accountKey];
    if (until == null) return false;
    if (until.isAfter(DateTime.now())) return true;
    _blockedUntil.remove(accountKey);
    return false;
  }

  void recordFailure(String accountKey) {
    _blockedUntil[accountKey] = DateTime.now().add(duration);
  }

  void clear(String accountKey) {
    _blockedUntil.remove(accountKey);
  }

  /// Removes every entry whose key satisfies [test].
  void clearWhere(bool Function(String accountKey) test) {
    _blockedUntil.removeWhere((key, _) => test(key));
  }

  void clearAll() {
    _blockedUntil.clear();
  }
}

class _AccountCacheEntry<T> {
  final T value;
  final DateTime fetchedAt;
  final DateTime expiresAt;

  const _AccountCacheEntry(this.value, this.fetchedAt, this.expiresAt);
}
