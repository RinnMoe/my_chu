import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'account_scoped_cache.dart';

typedef SummaryDecoder<T> = T Function(Map<String, dynamic> json);
typedef SummaryEncoder<T> = Map<String, dynamic> Function(T value);

/// Account-scoped persistent summary cache.
///
/// Adds a disk layer on top of the single-flight/short-TTL memory behaviour:
/// on a cold start the last persisted value is shown immediately and refreshed
/// in the background. Keys always include `accountKey` and the resource key.
/// Persistence is opt-in per plugin and best-effort: failures never break the
/// in-memory path.
///
/// Optional change detection: when [fingerprint] and [onChanged] are provided,
/// a completed load that differs from the previously known value (memory or
/// disk) fires [onChanged] with the account key and both values. The callback
/// is fire-and-forget and never blocks or breaks the load path. Reminders are
/// no longer produced here: features that need to remind publish through
/// `AlertCenterService.evaluate` from the change callback.
class PersistentSummaryCache<T> {
  PersistentSummaryCache({
    required this.storageKey,
    required this.ttl,
    required this.persistTtl,
    required this.maxEntries,
    required this.fromJson,
    required this.toJson,
    this.allowStale = true,
    this.fingerprint,
    this.onChanged,
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory {
    _memoryCache = AccountScopedCache<T>(ttl: ttl, allowStale: allowStale);
    PersistentCacheRegistry.register(this);
  }

  static const _schema = 1;

  final String storageKey;
  final Duration ttl;

  /// Maximum age of a disk snapshot. A null value means that the snapshot is
  /// retained until the feature explicitly refreshes or the account logs out.
  final Duration? persistTtl;
  final int maxEntries;
  final SummaryDecoder<T> fromJson;
  final SummaryEncoder<T> toJson;
  final bool allowStale;
  final Future<Directory> Function() _directoryProvider;

  /// Projects a value to a stable identity for change detection. Only used
  /// when [onChanged] is also provided.
  final Object? Function(T value)? fingerprint;

  /// Invoked (fire-and-forget) when a load produced a different fingerprint
  /// than the previously known value, with the account key for scoping.
  final void Function(String accountKey, T previous, T fresh)? onChanged;

  late final AccountScopedCache<T> _memoryCache;
  final Map<String, int> _generations = {};
  final Map<String, Future<void>> _diskMutations = {};

  /// Bumped whenever a load completes so listeners can render fresh values.
  ValueNotifier<int> get revision => _memoryCache.revision;

  /// Returns a fresh value, joins an active load, or starts one.
  ///
  /// On a cold start (empty memory) a valid disk value is returned immediately
  /// and refreshed in the background; [force] bypasses memory and disk.
  Future<T> load(
    String accountKey,
    String resourceKey,
    Future<T> Function() loader, {
    bool force = false,
  }) async {
    final key = _memoryKey(accountKey, resourceKey);
    final generation = _generationOf(key);
    var seededFromDisk = false;
    if (!force && allowStale && _memoryCache.peek(key) == null) {
      final disk = await _readDisk(accountKey, resourceKey);
      if (!_isCurrent(key, generation)) return loader();
      if (disk != null && !_olderThan(disk.fetchedAt, persistTtl)) {
        _memoryCache.seed(key, disk.value, fetchedAt: disk.fetchedAt);
        seededFromDisk = true;
      }
    }
    final previous = _memoryCache.peek(key);
    Future<T> refresh() async {
      final value = await loader();
      await _queueDiskMutation(key, () async {
        if (!_isCurrent(key, generation)) return;
        await _writeDisk(accountKey, resourceKey, value, DateTime.now());
        if (!_isCurrent(key, generation)) {
          await _deleteDisk(accountKey, resourceKey);
          return;
        }
        _notifyChanged(accountKey, previous, value);
      });
      return value;
    }

    if (seededFromDisk) {
      // The disk value can still be fresh within its memory TTL. Refresh in
      // the background anyway so a cold start surfaces the latest value
      // promptly instead of waiting for the TTL to expire.
      final value = _memoryCache.peek(key);
      if (value == null) {
        return _memoryCache.load(key, refresh, force: true);
      }
      unawaited(
        _memoryCache
            .load(key, refresh, force: true)
            .then<void>((_) {}, onError: (Object _) {}),
      );
      return value;
    }
    return _memoryCache.load(key, refresh, force: force);
  }

  /// Last known in-memory value without starting a load.
  T? peek(String accountKey, String resourceKey) =>
      _memoryCache.peek(_memoryKey(accountKey, resourceKey));

  /// Last persisted value that is still within [persistTtl], or null.
  Future<T?> readFromDisk(String accountKey, String resourceKey) async {
    final disk = await _readDisk(accountKey, resourceKey);
    if (disk == null || _olderThan(disk.fetchedAt, persistTtl)) return null;
    return disk.value;
  }

  Future<void> invalidate(String accountKey, String resourceKey) async {
    final key = _memoryKey(accountKey, resourceKey);
    _advanceGeneration(key);
    _memoryCache.invalidate(key);
    await _queueDiskMutation(key, () => _deleteDisk(accountKey, resourceKey));
    revision.value++;
  }

  /// Drops every entry (memory and disk) for one account.
  Future<void> clearAccount(String accountKey) async {
    final prefix = '$accountKey|';
    final keys = _generations.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      _advanceGeneration(key);
    }
    _memoryCache.invalidateWhere((key) => key.startsWith('$accountKey|'));
    await Future.wait([
      for (final key in keys)
        _queueDiskMutation(key, () async {
          final resourceKey = key.substring(prefix.length);
          await _deleteDisk(accountKey, resourceKey);
        }),
    ]);
    final dir = await _directoryFor(storageKey);
    if (await dir.exists()) {
      final filePrefix = '${_safe(accountKey)}__';
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.uri.pathSegments.last.startsWith(filePrefix)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
    revision.value++;
  }

  /// Drops every entry across all accounts for this cache.
  Future<void> clearAll() async {
    final keys = _generations.keys.toList(growable: false);
    for (final key in keys) {
      _advanceGeneration(key);
    }
    _memoryCache.invalidateAll();
    await Future.wait([
      for (final key in keys)
        _queueDiskMutation(key, () async {
          final separator = key.indexOf('|');
          if (separator < 0) return;
          await _deleteDisk(
            key.substring(0, separator),
            key.substring(separator + 1),
          );
        }),
    ]);
    final dir = await _directoryFor(storageKey);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    revision.value++;
  }

  void _notifyChanged(String accountKey, T? previous, T fresh) {
    final fingerprintOf = fingerprint;
    if (previous == null || fingerprintOf == null) return;
    if (fingerprintOf(previous) == fingerprintOf(fresh)) return;
    final changed = onChanged;
    if (changed != null) {
      try {
        changed(accountKey, previous, fresh);
      } catch (_) {
        // Change callbacks are best-effort and must never break loading.
      }
    }
  }

  int _generationOf(String key) => _generations.putIfAbsent(key, () => 0);

  bool _isCurrent(String key, int generation) =>
      _generationOf(key) == generation;

  void _advanceGeneration(String key) {
    _generations[key] = _generationOf(key) + 1;
  }

  Future<void> _queueDiskMutation(
    String key,
    Future<void> Function() mutation,
  ) {
    final previous = _diskMutations[key] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .then<void>(
          (_) => mutation(),
          onError: (Object _, StackTrace __) => mutation(),
        )
        .whenComplete(() {
          if (identical(_diskMutations[key], next)) {
            _diskMutations.remove(key);
          }
        });
    _diskMutations[key] = next;
    return next;
  }

  Future<Directory> _directoryFor(String storageKey) async {
    final root = await _directoryProvider();
    return Directory('${root.path}/${_safe(storageKey)}');
  }

  Future<File> _fileFor(String accountKey, String resourceKey) async {
    final dir = await _directoryFor(storageKey);
    return File('${dir.path}/${_safe(accountKey)}__${_safe(resourceKey)}.json');
  }

  Future<void> _writeDisk(
    String accountKey,
    String resourceKey,
    T value,
    DateTime fetchedAt,
  ) async {
    try {
      final file = await _fileFor(accountKey, resourceKey);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'schema': _schema,
          'fetchedAt': fetchedAt.toIso8601String(),
          'value': toJson(value),
        }),
      );
      await _prune();
    } catch (_) {
      // Disk persistence is best-effort; never fail the request path.
    }
  }

  Future<_DiskSummary<T>?> _readDisk(
    String accountKey,
    String resourceKey,
  ) async {
    try {
      final file = await _fileFor(accountKey, resourceKey);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schema'] != _schema) return null;
      final fetchedAtRaw = decoded['fetchedAt'];
      final fetchedAt =
          fetchedAtRaw is String ? DateTime.tryParse(fetchedAtRaw) : null;
      final valueRaw = decoded['value'];
      if (fetchedAt == null || valueRaw is! Map<String, dynamic>) return null;
      return _DiskSummary(fetchedAt: fetchedAt, value: fromJson(valueRaw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteDisk(String accountKey, String resourceKey) async {
    try {
      final file = await _fileFor(accountKey, resourceKey);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _prune() async {
    try {
      final dir = await _directoryFor(storageKey);
      if (!await dir.exists()) return;
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File) files.add(entity);
      }
      if (files.length <= maxEntries) return;
      final withModified = <(File, DateTime)>[];
      for (final file in files) {
        try {
          withModified.add((file, await file.lastModified()));
        } catch (_) {}
      }
      withModified.sort((a, b) => a.$2.compareTo(b.$2));
      final excess = withModified.length - maxEntries;
      for (var i = 0; i < excess; i++) {
        try {
          await withModified[i].$1.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/summary_cache');
  }

  static String _memoryKey(String accountKey, String resourceKey) =>
      '$accountKey|$resourceKey';

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static bool _olderThan(DateTime fetchedAt, Duration? ttl) =>
      ttl != null && fetchedAt.add(ttl).isBefore(DateTime.now());
}

class _DiskSummary<T> {
  final DateTime fetchedAt;
  final T value;

  const _DiskSummary({required this.fetchedAt, required this.value});
}

/// Central registry so sign-out and account replacement can drop every
/// persisted summary without each feature knowing about it.
class PersistentCacheRegistry {
  static final List<PersistentSummaryCache<Object?>> _caches = [];

  static void register<T>(PersistentSummaryCache<T> cache) {
    _caches.add(cache);
  }

  static Future<void> clearAll() async {
    for (final cache in _caches) {
      await cache.clearAll();
    }
  }
}
