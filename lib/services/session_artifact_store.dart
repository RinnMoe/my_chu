import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'campus_service_id.dart';
import 'session_storage_support.dart';
import 'session_materialization.dart';

class TokenArtifact {
  final CampusServiceId serviceId;
  final String rawValue;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String identityEpoch;

  const TokenArtifact({
    required this.serviceId,
    required this.rawValue,
    required this.createdAt,
    required this.expiresAt,
    required this.identityEpoch,
  });

  bool isExpired(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  Map<String, Object?> toJson() => {
    'serviceId': serviceId.value,
    'artifactType': 'token',
    'rawValue': rawValue,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    'identityEpoch': identityEpoch,
  };

  static TokenArtifact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final serviceId = raw['serviceId'];
    final artifactType = raw['artifactType'];
    final rawValue = raw['rawValue'];
    final createdAt = _date(raw['createdAt']);
    final expiresAt = raw['expiresAt'] == null ? null : _date(raw['expiresAt']);
    final identityEpoch = raw['identityEpoch'];
    if (serviceId is! String ||
        serviceId.isEmpty ||
        artifactType != 'token' ||
        rawValue is! String ||
        rawValue.isEmpty ||
        createdAt == null ||
        raw['expiresAt'] != null && expiresAt == null ||
        identityEpoch is! String) {
      return null;
    }
    return TokenArtifact(
      serviceId: CampusServiceId(serviceId),
      rawValue: rawValue,
      createdAt: createdAt,
      expiresAt: expiresAt,
      identityEpoch: identityEpoch,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

/// Stores raw token values only. Header names, prefixes and runtime revisions
/// are always derived from the service definition at request time.
class SessionArtifactStore {
  SessionArtifactStore({
    required this.accountKey,
    required this.identityEpoch,
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _now = now ?? DateTime.now;

  final String accountKey;
  final String identityEpoch;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final Map<String, TokenArtifact> _artifacts = {};
  Future<void>? _openFuture;
  var _opened = false;

  String get storageKey => SessionStorageKeys.artifactKey(accountKey);

  Future<void> open() {
    if (_opened) return Future<void>.value();
    final pending = _openFuture;
    if (pending != null) return pending;
    final future = _load();
    _openFuture = future;
    return future;
  }

  Future<void> _load() async {
    try {
      await _reloadFromStorage();
    } finally {
      _opened = true;
    }
  }

  Future<TokenArtifact?> read(CampusServiceId serviceId) async {
    final currentArtifacts = await _currentSnapshot();
    final artifact = currentArtifacts[serviceId.value];
    if (artifact == null || artifact.isExpired(_now().toUtc())) {
      return null;
    }
    return artifact;
  }

  Future<void> write(
    TokenArtifact artifact, {
    SessionMaterializationMutation? mutation,
  }) async {
    await writeIfCurrent(
      artifact,
      isCurrent: () => true,
      verifyIdentityEpoch: true,
      mutation: mutation,
    );
  }

  Future<bool> writeIfCurrent(
    TokenArtifact artifact, {
    required bool Function() isCurrent,
    bool verifyIdentityEpoch = true,
    SessionMaterializationMutation? mutation,
  }) async {
    if (artifact.identityEpoch != identityEpoch) {
      throw StateError('artifact identity epoch mismatch');
    }
    if (artifact.rawValue.isEmpty) {
      throw ArgumentError.value(artifact.rawValue, 'rawValue');
    }
    return _runMutation(
      mutation: mutation,
      serviceId: artifact.serviceId,
      action: () async {
        await open();
        return AccountSessionStorageQueue.run(accountKey, () async {
          if (!isCurrent() ||
              verifyIdentityEpoch && !await _identityEpochMatchesStorage()) {
            _artifacts.clear();
            return false;
          }
          await _reloadFromStorage();
          if (!isCurrent() ||
              verifyIdentityEpoch && !await _identityEpochMatchesStorage()) {
            _artifacts.clear();
            return false;
          }
          _artifacts[artifact.serviceId.value] = artifact;
          await _persist();
          return true;
        });
      },
    );
  }

  Future<void> delete(
    CampusServiceId serviceId, {
    SessionMaterializationMutation? mutation,
  }) async {
    await _runVoidMutation(
      mutation: mutation,
      serviceId: serviceId,
      action: () async {
        await open();
        await AccountSessionStorageQueue.run(accountKey, () async {
          if (!await _identityEpochMatchesStorage()) {
            _artifacts.clear();
            return;
          }
          await _reloadFromStorage();
          if (!await _identityEpochMatchesStorage()) {
            _artifacts.clear();
            return;
          }
          _artifacts.remove(serviceId.value);
          await _persist();
        });
      },
    );
  }

  Future<List<TokenArtifact>> snapshot() async {
    final currentArtifacts = await _currentSnapshot();
    final now = _now().toUtc();
    return currentArtifacts.values
        .where((artifact) => !artifact.isExpired(now))
        .toList(growable: false);
  }

  Future<void> clear({SessionMaterializationMutation? mutation}) async {
    await _runVoidMutation(
      mutation: mutation,
      keyOverride: SessionMaterializationRegistry.rootKey(accountKey),
      action: () async {
        await AccountSessionStorageQueue.run(accountKey, () async {
          if (!await _identityEpochMatchesStorage()) {
            _artifacts.clear();
            return;
          }
          _artifacts.clear();
          await _storage.delete(key: storageKey);
        });
      },
    );
  }

  Future<T> _runMutation<T>({
    required SessionMaterializationMutation? mutation,
    CampusServiceId? serviceId,
    String? keyOverride,
    required Future<T> Function() action,
  }) async {
    final key =
        keyOverride ??
        SessionMaterializationRegistry.serviceKey(accountKey, serviceId!);
    final owned =
        mutation == null
            ? await SessionMaterializationRegistry.beginMutation(keys: [key])
            : null;
    mutation?.requireKey(key);
    try {
      final result = await action();
      if (owned != null) await owned.end(commit: result is! bool || result);
      return result;
    } catch (_) {
      if (owned != null) await owned.end(commit: false);
      rethrow;
    }
  }

  Future<void> _runVoidMutation({
    required SessionMaterializationMutation? mutation,
    CampusServiceId? serviceId,
    String? keyOverride,
    required Future<void> Function() action,
  }) async {
    final key =
        keyOverride ??
        SessionMaterializationRegistry.serviceKey(accountKey, serviceId!);
    final owned =
        mutation == null
            ? await SessionMaterializationRegistry.beginMutation(keys: [key])
            : null;
    mutation?.requireKey(key);
    try {
      await action();
      if (owned != null) await owned.end(commit: true);
    } catch (_) {
      if (owned != null) await owned.end(commit: false);
      rethrow;
    }
  }

  /// Reloads artifacts under the account queue before exposing any token.
  ///
  /// A store instance can remain in memory after another instance replaces the
  /// root identity. Its captured epoch is not sufficient proof that the
  /// artifact is still current; the persisted epoch must be checked on read.
  Future<Map<String, TokenArtifact>> _currentSnapshot() async {
    await open();
    return AccountSessionStorageQueue.run(accountKey, () async {
      if (!await _identityEpochMatchesStorage()) {
        _artifacts.clear();
        return const <String, TokenArtifact>{};
      }
      await _reloadFromStorage();
      if (!await _identityEpochMatchesStorage()) {
        _artifacts.clear();
        return const <String, TokenArtifact>{};
      }
      return Map<String, TokenArtifact>.of(_artifacts);
    });
  }

  Future<void> _persist() async {
    final value = jsonEncode(
      _artifacts.values.map((artifact) => artifact.toJson()).toList(),
    );
    await _storage.write(key: storageKey, value: value);
  }

  Future<void> _reloadFromStorage() async {
    _artifacts.clear();
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    final now = _now().toUtc();
    for (final item in decoded) {
      final artifact = TokenArtifact.fromJson(item);
      if (artifact == null ||
          artifact.identityEpoch != identityEpoch ||
          artifact.isExpired(now)) {
        continue;
      }
      _artifacts[artifact.serviceId.value] = artifact;
    }
  }

  Future<bool> _identityEpochMatchesStorage() async {
    final current = await _storage.read(
      key: SessionStorageKeys.identityEpochKey(accountKey),
    );
    return current == identityEpoch;
  }
}
