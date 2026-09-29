import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'persistent_campus_cookie_jar.dart';
import 'session_artifact_store.dart';
import 'session_runtime_fence.dart';
import 'session_storage_support.dart';
import 'service_endpoints.dart';
import 'session_materialization.dart';

/// Account-owned persistent identity and derived session state.
class CampusSessionStore {
  CampusSessionStore._({
    required this.accountKey,
    required FlutterSecureStorage storage,
    required this.identityEpoch,
  }) : _storage = storage;

  final String accountKey;
  final FlutterSecureStorage _storage;
  String identityEpoch;

  final Map<String, PersistentCampusCookieJar> _cookieJars = {};
  SessionArtifactStore? _artifacts;

  static Future<CampusSessionStore> open({
    required String accountKey,
    FlutterSecureStorage? storage,
  }) async {
    final secureStorage = storage ?? const FlutterSecureStorage();
    final epoch = await AccountSessionStorageQueue.run(accountKey, () async {
      final key = SessionStorageKeys.identityEpochKey(accountKey);
      final existing = await secureStorage.read(key: key);
      if (existing != null && existing.isNotEmpty) return existing;
      final nextEpoch = _newIdentityEpoch();
      await secureStorage.write(key: key, value: nextEpoch);
      return nextEpoch;
    });
    return CampusSessionStore._(
      accountKey: accountKey,
      storage: secureStorage,
      identityEpoch: epoch,
    );
  }

  PersistentCampusCookieJar cookieJar(
    CampusServiceId serviceId, {
    SessionScope scope = const ServiceSessionScope(),
  }) => _cookieJars.putIfAbsent(
    '${serviceId.value}|${scope.key}',
    () => PersistentCampusCookieJar(
      accountKey: accountKey,
      serviceId: serviceId,
      sessionScope: scope.key,
      identityEpoch: identityEpoch,
      storage: _storage,
      materializationKey:
          serviceId == CampusServices.unifiedIdentity
              ? SessionMaterializationRegistry.rootKey(accountKey)
              : SessionMaterializationRegistry.serviceKey(
                accountKey,
                serviceId,
              ),
    ),
  );

  PersistentCampusCookieJar get rootCookieJar =>
      cookieJar(CampusServices.unifiedIdentity);

  /// Seeds the two CHD identity hosts without exposing the cookie header to
  /// callers outside the identity/session layer.
  Future<void> seedRootIdentityCookies(String cookieHeader) async {
    if (cookieHeader.isEmpty) return;
    final mutation = await beginRootMaterializationMutation();
    var ended = false;
    try {
      await rootCookieJar.seedCookieHeader(
        CampusServiceEndpoints.idsAuthUri,
        cookieHeader,
        mutation: mutation,
      );
      await rootCookieJar.seedCookieHeader(
        CampusServiceEndpoints.identityRealmUri,
        cookieHeader,
        mutation: mutation,
      );
      await mutation.end(commit: true);
      ended = true;
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  Future<String> rootCookieHeader({Uri? uri}) =>
      rootCookieJar.headerFor(uri ?? CampusServiceEndpoints.idsAuthUri);

  SessionRuntimeFence captureFence({
    required CampusServiceId serviceId,
    required String scopeKey,
    required int sessionRevision,
    Iterable<String> additionalScopeKeys = const [],
  }) {
    final scopeKeys = <String>{scopeKey, ...additionalScopeKeys};
    final serviceGenerations = <String, int>{
      for (final key in scopeKeys)
        key: ServiceGenerationRegistry.current(
          accountKey: accountKey,
          serviceId: serviceId,
          scopeKey: key,
        ),
    };
    return SessionRuntimeFence(
      accountKey: accountKey,
      serviceId: serviceId,
      scopeKey: scopeKey,
      sessionRevision: sessionRevision,
      serviceGenerations: serviceGenerations,
    );
  }

  Future<WebViewMaterializationFence> captureWebViewFence({
    required CampusServiceId serviceId,
    required int sessionRevision,
  }) => SessionMaterializationRegistry.captureStableFence(
    accountKey: accountKey,
    serviceId: serviceId,
    sessionRevision: sessionRevision,
    identityEpoch: identityEpoch,
  );

  Future<SessionMaterializationMutation> beginRootMaterializationMutation() =>
      SessionMaterializationRegistry.beginRootMutation(accountKey);

  Future<SessionMaterializationMutation> beginServiceMaterializationMutation(
    CampusServiceId serviceId,
  ) => SessionMaterializationRegistry.beginServiceMutation(
    accountKey,
    serviceId,
  );

  /// Confirms that this store instance still belongs to the persisted root
  /// identity. A false result also drops this instance's local projections so
  /// callers cannot accidentally export stale material after an epoch change.
  Future<bool> isCurrentIdentityEpoch() async {
    return AccountSessionStorageQueue.run(accountKey, () async {
      final current = await _storage.read(
        key: SessionStorageKeys.identityEpochKey(accountKey),
      );
      if (current == identityEpoch) return true;
      _cookieJars.clear();
      _artifacts = null;
      return false;
    });
  }

  /// Invalidates only one service scope and its derived artifacts.
  Future<void> invalidateService({
    required CampusServiceId serviceId,
    SessionScope scope = const ServiceSessionScope(),
  }) async {
    final mutation = await beginServiceMaterializationMutation(serviceId);
    var ended = false;
    try {
      await cookieJar(serviceId, scope: scope).clear(mutation: mutation);
      await artifacts.delete(serviceId, mutation: mutation);
      await mutation.end(commit: true);
      ended = true;
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  SessionArtifactStore get artifacts =>
      _artifacts ??= SessionArtifactStore(
        accountKey: accountKey,
        identityEpoch: identityEpoch,
        storage: _storage,
      );

  /// Replaces the root identity fence before clearing any old derived state.
  /// If the process stops during cleanup, the old records remain unusable
  /// because their stored epoch no longer matches [identityEpoch].
  Future<String> replaceRootIdentity() async {
    final nextEpoch = _newIdentityEpoch();
    final mutation = await beginRootMaterializationMutation();
    var ended = false;
    try {
      await AccountSessionStorageQueue.run(accountKey, () async {
        identityEpoch = nextEpoch;
        await _storage.write(
          key: SessionStorageKeys.identityEpochKey(accountKey),
          value: nextEpoch,
        );
        await _clearDerivedKeys();
      });
      _cookieJars.clear();
      _artifacts = null;
      await mutation.end(commit: true);
      ended = true;
      return nextEpoch;
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  Future<void> clear() async {
    final mutation = await beginRootMaterializationMutation();
    var ended = false;
    try {
      await AccountSessionStorageQueue.clearAccountKeys(
        storage: _storage,
        accountKey: accountKey,
      );
      _cookieJars.clear();
      _artifacts = null;
      ServiceGenerationRegistry.clearAccount(accountKey);
      await mutation.end(commit: true);
      ended = true;
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  Future<void> _clearDerivedKeys() async {
    final all = await _storage.readAll();
    final encoded = SessionStorageKeys.accountSegment(accountKey);
    final prefixes = [
      '${SessionStorageKeys.cookiePrefix}$encoded.',
      '${SessionStorageKeys.artifactPrefix}$encoded',
    ];
    for (final key in all.keys.toList()) {
      if (prefixes.any(key.startsWith)) await _storage.delete(key: key);
    }
  }

  static String _newIdentityEpoch() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
