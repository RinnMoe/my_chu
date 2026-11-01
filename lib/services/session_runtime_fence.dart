import 'campus_service_id.dart';

/// Process-local account and service generations captured by an async request.
///
/// Persistent identity lineage belongs to [CampusSessionStore] and its cookie
/// or artifact stores. This fence only answers whether an in-flight runtime
/// operation still belongs to the current account/revision and captured
/// service scopes.
class SessionRuntimeFence {
  SessionRuntimeFence({
    required this.accountKey,
    required this.serviceId,
    required this.scopeKey,
    required this.sessionRevision,
    required Map<String, int> serviceGenerations,
  }) : serviceGenerations = Map.unmodifiable(serviceGenerations);

  final String accountKey;
  final CampusServiceId serviceId;
  final String scopeKey;
  final int sessionRevision;
  final Map<String, int> serviceGenerations;

  String get serviceKey => '$accountKey|${serviceId.value}|$scopeKey';

  /// Stable key for single-flight operations sharing this exact runtime
  /// fence. Map entries are sorted so multi-scope captures do not depend on
  /// insertion order.
  String get fingerprint =>
      '$accountKey|${serviceId.value}|$sessionRevision|$_generationsKey';

  /// Single-flight key that survives a same-account root refresh.
  ///
  /// The identity generation replaces the runtime revision, while the captured
  /// service generations still split scopes invalidated by an explicit refresh.
  /// Callers must keep using [isCurrent] for the exchange fence itself.
  String identityFingerprint(int identityRevision) =>
      '$accountKey|${serviceId.value}|i$identityRevision|$_generationsKey';

  String get _generationsKey {
    final entries =
        serviceGenerations.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join(',');
  }

  bool hasSameServiceGenerations(SessionRuntimeFence other) {
    if (serviceGenerations.length != other.serviceGenerations.length) {
      return false;
    }
    return serviceGenerations.entries.every(
      (entry) => other.serviceGenerations[entry.key] == entry.value,
    );
  }

  bool isCurrent({
    required String currentAccountKey,
    required int currentSessionRevision,
  }) {
    if (accountKey != currentAccountKey ||
        sessionRevision != currentSessionRevision) {
      return false;
    }
    return hasCurrentServiceGenerations();
  }

  /// Whether every captured service generation is still current.
  bool hasCurrentServiceGenerations() => serviceGenerations.entries.every(
    (entry) =>
        entry.value ==
        ServiceGenerationRegistry.current(
          accountKey: accountKey,
          serviceId: serviceId,
          scopeKey: entry.key,
        ),
  );

  /// Account and service-generation check that deliberately ignores
  /// [sessionRevision].
  ///
  /// A same-account root refresh advances the runtime revision but keeps every
  /// persisted service session valid, so a cached projection may still be
  /// reused. An explicit service invalidation still fails this check.
  bool identityIsCurrent({required String currentAccountKey}) {
    if (accountKey != currentAccountKey) return false;
    return hasCurrentServiceGenerations();
  }

  /// Checks the captured generation for one redirect target scope.
  bool isCurrentForScope({
    required String targetScopeKey,
    required String currentAccountKey,
    required int currentSessionRevision,
  }) {
    final expectedGeneration = serviceGenerations[targetScopeKey];
    if (expectedGeneration == null ||
        accountKey != currentAccountKey ||
        sessionRevision != currentSessionRevision) {
      return false;
    }
    return expectedGeneration ==
        ServiceGenerationRegistry.current(
          accountKey: accountKey,
          serviceId: serviceId,
          scopeKey: targetScopeKey,
        );
  }
}

/// Process-local generation for one account/service/scope.
///
/// A service refresh increments only its own generation. Root identity
/// replacement uses [clearAccount] so all derived services become stale
/// without introducing a global request lock.
class ServiceGenerationRegistry {
  ServiceGenerationRegistry._();

  static final Map<String, int> _generations = {};

  static int current({
    required String accountKey,
    required CampusServiceId serviceId,
    required String scopeKey,
  }) => _generations[_key(accountKey, serviceId, scopeKey)] ?? 0;

  static int bump({
    required String accountKey,
    required CampusServiceId serviceId,
    required String scopeKey,
  }) {
    final key = _key(accountKey, serviceId, scopeKey);
    final next = (_generations[key] ?? 0) + 1;
    _generations[key] = next;
    return next;
  }

  static void clearAccount(String accountKey) {
    final prefix = '$accountKey|';
    _generations.removeWhere((key, _) => key.startsWith(prefix));
  }

  static void clear() => _generations.clear();

  static String _key(
    String accountKey,
    CampusServiceId serviceId,
    String scopeKey,
  ) => '$accountKey|${serviceId.value}|$scopeKey';
}
