import 'dart:async';

import 'campus_service_id.dart';

/// A non-secret revision pair attached to a service projection produced by a
/// Store mutation. It lets a WebView acquisition distinguish a session that
/// was produced by its own mutation from a session that became stale while it
/// was being assembled.
class MaterializationRevisionStamp {
  const MaterializationRevisionStamp({
    required this.rootRevision,
    required this.serviceRevision,
  });

  final int rootRevision;
  final int serviceRevision;

  bool matches(WebViewMaterializationFence fence) =>
      rootRevision == fence.rootRevision &&
      serviceRevision == fence.serviceRevision;
}

/// Stable Store ↔ platform-WebView materialization state.
///
/// The runtime/session fence and the materialization fence deliberately remain
/// separate. The former controls account and service exchange lifetime; this
/// fence controls whether the credential content represented by a WebView
/// snapshot is still the current Store content.
class WebViewMaterializationFence {
  const WebViewMaterializationFence({
    required this.accountKey,
    required this.serviceId,
    required this.sessionRevision,
    required this.identityEpoch,
    required this.rootRevision,
    required this.serviceRevision,
    required this.cookieManagerEpoch,
  });

  final String accountKey;
  final CampusServiceId serviceId;
  final int sessionRevision;
  final String identityEpoch;
  final int rootRevision;
  final int serviceRevision;
  final int cookieManagerEpoch;

  bool hasSameMaterialization(WebViewMaterializationFence other) =>
      accountKey == other.accountKey &&
      serviceId == other.serviceId &&
      rootRevision == other.rootRevision &&
      serviceRevision == other.serviceRevision &&
      cookieManagerEpoch == other.cookieManagerEpoch;

  bool isCurrent({
    required String currentAccountKey,
    required String currentIdentityEpoch,
    required int currentSessionRevision,
  }) =>
      accountKey == currentAccountKey &&
      identityEpoch == currentIdentityEpoch &&
      sessionRevision == currentSessionRevision &&
      SessionMaterializationRegistry.isRootCurrent(
        accountKey: accountKey,
        revision: rootRevision,
      ) &&
      SessionMaterializationRegistry.isServiceCurrent(
        accountKey: accountKey,
        serviceId: serviceId,
        revision: serviceRevision,
      ) &&
      SessionMaterializationRegistry.isCookieManagerCurrent(
        epoch: cookieManagerEpoch,
      );
}

class SessionMaterializationMutationResult {
  const SessionMaterializationMutationResult({
    required this.committed,
    required this.revisions,
  });

  final bool committed;
  final Map<String, int> revisions;
}

/// Exclusive mutation reservation for one or more materialization keys.
///
/// A mutation becomes visible as transient before its predecessor is awaited.
/// Therefore existing fences become stale immediately, while new captures
/// wait until [end] publishes the next stable revision.
class SessionMaterializationMutation {
  SessionMaterializationMutation._({required this.keys, required this.release});

  final Set<String> keys;
  final Completer<void> release;
  var _ended = false;
  Map<String, int>? _finishedRevisions;
  bool? _finishedCommit;

  bool covers(String key) => keys.contains(key);

  void requireKey(String key) {
    if (!covers(key)) {
      throw StateError('materialization mutation does not cover $key');
    }
  }

  int? revisionFor(String key) => _finishedRevisions?[key];

  Future<SessionMaterializationMutationResult> end({
    required bool commit,
  }) async {
    if (_ended) {
      return SessionMaterializationMutationResult(
        committed: _finishedCommit ?? false,
        revisions: Map.unmodifiable(_finishedRevisions ?? const {}),
      );
    }
    _ended = true;
    _finishedCommit = commit;
    final revisions = <String, int>{};
    for (final key in keys) {
      revisions[key] = SessionMaterializationRegistry._finishKey(key);
    }
    _finishedRevisions = Map.unmodifiable(revisions);
    release.complete();
    return SessionMaterializationMutationResult(
      committed: commit,
      revisions: _finishedRevisions!,
    );
  }
}

class CookieManagerResetHandle {
  CookieManagerResetHandle._({required this.previous, required this.release});

  final Future<void> previous;
  final Completer<void> release;
  var _ended = false;

  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    SessionMaterializationRegistry._finishCookieManagerReset();
    release.complete();
  }
}

class _MaterializationState {
  Future<void> tail = Future<void>.value();
  var pending = 0;
  var revision = 0;
}

/// Dart-isolate-local seqlock for credential materialization.
///
/// Store writes are persisted under [AccountSessionStorageQueue], but that
/// queue alone cannot invalidate a WebView lease that already captured the old
/// data. This registry supplies the missing transient/stable protocol.
class SessionMaterializationRegistry {
  SessionMaterializationRegistry._();

  static final Map<String, _MaterializationState> _states = {};
  static Future<void> _cookieManagerTail = Future<void>.value();
  static var _cookieManagerPending = 0;
  static var _cookieManagerEpoch = 0;

  static String rootKey(String accountKey) => 'root|$accountKey';

  static String serviceKey(String accountKey, CampusServiceId serviceId) =>
      'service|$accountKey|${serviceId.value}';

  static int currentRootRevision(String accountKey) =>
      _state(rootKey(accountKey)).revision;

  static int currentServiceRevision(
    String accountKey,
    CampusServiceId serviceId,
  ) => _state(serviceKey(accountKey, serviceId)).revision;

  static int get cookieManagerEpoch => _cookieManagerEpoch;

  static Future<SessionMaterializationMutation> beginRootMutation(
    String accountKey,
  ) => beginMutation(keys: [rootKey(accountKey)]);

  static Future<SessionMaterializationMutation> beginServiceMutation(
    String accountKey,
    CampusServiceId serviceId,
  ) => beginMutation(keys: [serviceKey(accountKey, serviceId)]);

  static Future<SessionMaterializationMutation> beginMutation({
    required Iterable<String> keys,
  }) async {
    final normalized = keys.toSet().toList()..sort();
    if (normalized.isEmpty) {
      throw ArgumentError.value(keys, 'keys', '至少需要一个 materialization key');
    }

    final release = Completer<void>();
    final predecessors = <Future<void>>[];
    for (final key in normalized) {
      final state = _state(key);
      // Reserve every key before awaiting. Sorting the keys makes overlapping
      // multi-key batches acquire in one deterministic order and avoids a
      // root/service deadlock.
      state.pending++;
      predecessors.add(state.tail);
      state.tail = release.future;
    }
    await Future.wait(predecessors);
    return SessionMaterializationMutation._(
      keys: normalized.toSet(),
      release: release,
    );
  }

  static Future<WebViewMaterializationFence> captureStableFence({
    required String accountKey,
    required CampusServiceId serviceId,
    required int sessionRevision,
    required String identityEpoch,
  }) async {
    final root = rootKey(accountKey);
    final service = serviceKey(accountKey, serviceId);
    while (true) {
      final states = [_state(root), _state(service)];
      final pendingWaiters = <Future<void>>[];
      for (final state in states) {
        if (state.pending > 0) pendingWaiters.add(state.tail);
      }
      if (_cookieManagerPending > 0) {
        pendingWaiters.add(_cookieManagerTail);
      }
      if (pendingWaiters.isNotEmpty) {
        await Future.wait(pendingWaiters);
        continue;
      }

      // No await occurs between this check and the returned snapshot. A new
      // mutation can only start after this synchronous linearization point;
      // its transient state then makes this fence stale.
      final rootState = _state(root);
      final serviceState = _state(service);
      if (rootState.pending > 0 ||
          serviceState.pending > 0 ||
          _cookieManagerPending > 0) {
        continue;
      }
      return WebViewMaterializationFence(
        accountKey: accountKey,
        serviceId: serviceId,
        sessionRevision: sessionRevision,
        identityEpoch: identityEpoch,
        rootRevision: rootState.revision,
        serviceRevision: serviceState.revision,
        cookieManagerEpoch: _cookieManagerEpoch,
      );
    }
  }

  static bool isRootCurrent({
    required String accountKey,
    required int revision,
  }) {
    final state = _state(rootKey(accountKey));
    return state.pending == 0 && state.revision == revision;
  }

  static bool isServiceCurrent({
    required String accountKey,
    required CampusServiceId serviceId,
    required int revision,
  }) {
    final state = _state(serviceKey(accountKey, serviceId));
    return state.pending == 0 && state.revision == revision;
  }

  static bool isCookieManagerCurrent({required int epoch}) =>
      _cookieManagerPending == 0 && _cookieManagerEpoch == epoch;

  static CookieManagerResetHandle beginCookieManagerReset() {
    final previous = _cookieManagerTail;
    final release = Completer<void>();
    _cookieManagerPending++;
    _cookieManagerEpoch++;
    _cookieManagerTail = release.future;
    return CookieManagerResetHandle._(previous: previous, release: release);
  }

  static int _finishKey(String key) {
    final state = _state(key);
    if (state.pending <= 0) {
      throw StateError('materialization mutation ended without a reservation');
    }
    state.pending--;
    state.revision++;
    return state.revision;
  }

  static void _finishCookieManagerReset() {
    if (_cookieManagerPending <= 0) {
      throw StateError('CookieManager reset ended without a reservation');
    }
    _cookieManagerPending--;
  }

  static _MaterializationState _state(String key) =>
      _states.putIfAbsent(key, _MaterializationState.new);

  /// Test-only reset for deterministic protocol tests. Production code never
  /// resets revisions because ABA protection depends on monotonic values.
  static void debugReset() {
    if (_cookieManagerPending != 0 ||
        _states.values.any((state) => state.pending != 0)) {
      throw StateError('cannot reset materialization registry while pending');
    }
    _states.clear();
    _cookieManagerTail = Future<void>.value();
    _cookieManagerEpoch = 0;
  }
}
