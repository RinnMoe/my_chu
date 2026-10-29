import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../capabilities/text_utils.dart';
import '../host_platform.dart';
import '../host_version.dart';
import '../supabase/supabase_privacy_gate.dart';
import 'remote_feature_policy_config.dart';
import 'remote_feature_policy_local_policy.dart';
import 'remote_feature_policy_models.dart';
import 'remote_feature_policy_repository.dart';
import 'remote_feature_policy_source.dart';
import 'remote_feature_policy_store.dart';

/// The host identity a policy row is matched against.
@immutable
class FeaturePolicyContext {
  const FeaturePolicyContext({required this.platform, this.appVersion});

  final FeaturePlatform platform;

  /// Host versionName (`1.2.0`). Null when the build has no parseable version.
  final String? appVersion;

  @override
  bool operator ==(Object other) =>
      other is FeaturePolicyContext &&
      other.platform == platform &&
      other.appVersion == appVersion;

  @override
  int get hashCode => Object.hash(platform, appVersion);
}

enum RemoteFeaturePolicyRefreshStatus { applied, skipped, failed }

class RemoteFeaturePolicyRefreshResult {
  const RemoteFeaturePolicyRefreshResult(
    this.status, {
    this.reason,
    this.error,
  });

  final RemoteFeaturePolicyRefreshStatus status;

  /// Short, non-sensitive reason for diagnostics (`not-configured`,
  /// `consent-missing`, `throttled`).
  final String? reason;
  final Object? error;

  bool get didApply => status == RemoteFeaturePolicyRefreshStatus.applied;
}

/// Owns the effective policy snapshot and answers feature queries.
///
/// Responsibilities:
/// - keep the last validated snapshot (remote or cached) in memory;
/// - merge remote rows with local defaults and the local safety level;
/// - coalesce concurrent refreshes and throttle ordinary/foreground refreshes;
/// - never let a failed or invalid refresh widen access.
///
/// The service is deliberately independent from [AppRemoteServicesService]:
/// the user-facing "应用远程服务" switch gates announcements, feedback and
/// analytics, not published safety policies.
class RemoteFeaturePolicyService {
  RemoteFeaturePolicyService({
    required this.repository,
    required this.config,
    FeaturePolicyContext? context,
    Future<FeaturePolicyContext> Function()? contextLoader,
    Future<bool> Function()? consentCheck,
    DateTime Function()? clock,
    FeaturePolicyDefaults defaults = const CompiledFeaturePolicyDefaults(),
  }) : _fixedContext = context,
       _contextLoader = contextLoader,
       _consentCheck = consentCheck,
       _clock = clock ?? DateTime.now,
       _defaults = defaults;

  /// Process-wide instance. Tests may replace it before mounting widgets.
  static RemoteFeaturePolicyService instance = bootstrap();

  static RemoteFeaturePolicyService bootstrap() {
    final config = RemoteFeaturePolicyConfig.fromEnvironment();
    return RemoteFeaturePolicyService(
      config: config,
      repository: RemoteFeaturePolicyRepository(
        source: SupabaseFeaturePolicySource(config: config),
        store: const SharedPreferencesFeaturePolicyStore(),
      ),
      contextLoader: loadHostFeaturePolicyContext,
    );
  }

  final RemoteFeaturePolicyRepository repository;
  final RemoteFeaturePolicyConfig config;
  final FeaturePolicyContext? _fixedContext;
  final Future<FeaturePolicyContext> Function()? _contextLoader;
  final Future<bool> Function()? _consentCheck;
  final DateTime Function() _clock;
  final FeaturePolicyDefaults _defaults;

  /// Bumped whenever the effective snapshot changes so UI can re-evaluate.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  RemoteFeaturePolicySnapshot? _snapshot;
  FeaturePolicyContext? _context;
  Future<void>? _initialization;
  bool _initialized = false;
  Future<RemoteFeaturePolicyRefreshResult>? _inFlight;
  DateTime? _lastAttemptAt;
  DateTime? _lastFailureAt;

  bool get isConfigured => config.isConfigured;

  RemoteFeaturePolicySnapshot? get snapshot => _snapshot;

  FeaturePolicyContext? get context => _context;

  DateTime? get lastFailureAt => _lastFailureAt;

  /// Loads the cached snapshot once, then refreshes in the background.
  ///
  /// Call after the user agreement is accepted; [refresh] enforces that gate.
  Future<void> start({bool force = false}) async {
    await initialize();
    await refresh(force: force);
  }

  Future<void> initialize() =>
      _initialized ? Future<void>.value() : (_initialization ??= _initialize());

  Future<void> _initialize() async {
    final cached = await repository.loadCached();
    if (cached != null) {
      // Matching cached rows needs the host context; a first run without a
      // snapshot defers it to the refresh, so opening an app never waits on
      // platform channels.
      await _ensureContext();
      _adopt(cached);
    } else if (_fixedContext != null) {
      _context = _fixedContext;
    }
    _initialized = true;
  }

  /// Ordinary refresh, throttled by [RemoteFeaturePolicyConfig.refreshInterval].
  Future<RemoteFeaturePolicyRefreshResult> refresh({bool force = false}) =>
      _enqueue(force: force, interval: config.refreshInterval);

  /// Foreground refresh, throttled by a shorter interval.
  Future<RemoteFeaturePolicyRefreshResult> refreshOnForeground({
    bool force = false,
  }) => _enqueue(force: force, interval: config.foregroundRefreshInterval);

  /// Evaluates the remote layer for one feature ID.
  ///
  /// Local gates (existence, development flag, installation) are applied by
  /// `FeatureAccessGuard`; this method only answers "what does the policy layer
  /// say about this feature".
  RemoteFeatureEvaluation evaluate(String featureId) {
    if (_defaults.isProtected(featureId)) {
      return _localDefault(featureId);
    }

    final context = _context ?? _fallbackContext();
    final snapshot = _snapshot;
    final level = _defaults.levelFor(featureId);
    if (snapshot == null) {
      return level == FeatureSafetyLevel.highRisk
          ? _failClosed(featureId)
          : _localDefault(featureId);
    }

    final matches = snapshot
        .policiesFor(featureId)
        .where(
          (policy) => policy.matches(
            platform: context.platform,
            appVersion: context.appVersion,
          ),
        )
        .toList(growable: false);

    if (matches.isEmpty) {
      // A high-risk feature needs an explicit confirmation; "no row" is not one.
      return level == FeatureSafetyLevel.highRisk
          ? _failClosed(featureId)
          : _localDefault(featureId);
    }

    final best = _resolve(matches);
    if (level == FeatureSafetyLevel.highRisk &&
        best.state == FeaturePolicyState.enabled &&
        !_isFresh(snapshot)) {
      return _failClosed(featureId);
    }

    return RemoteFeatureEvaluation(
      featureId: featureId,
      availability: switch (best.state) {
        FeaturePolicyState.enabled => RemoteFeatureAvailability.enabled,
        FeaturePolicyState.maintenance => RemoteFeatureAvailability.maintenance,
        FeaturePolicyState.disabled => RemoteFeatureAvailability.disabled,
      },
      origin: RemoteFeaturePolicyOrigin.remotePolicy,
      visible: best.visible,
      message: best.message,
      fetchedAt: snapshot.fetchedAt,
    );
  }

  Future<RemoteFeaturePolicyRefreshResult> _enqueue({
    required bool force,
    required Duration interval,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    late final Future<RemoteFeaturePolicyRefreshResult> future;
    future = _runRefresh(force: force, interval: interval).whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<RemoteFeaturePolicyRefreshResult> _runRefresh({
    required bool force,
    required Duration interval,
  }) async {
    if (!config.isConfigured) {
      return const RemoteFeaturePolicyRefreshResult(
        RemoteFeaturePolicyRefreshStatus.skipped,
        reason: 'not-configured',
      );
    }
    if (!await _consentGranted()) {
      return const RemoteFeaturePolicyRefreshResult(
        RemoteFeaturePolicyRefreshStatus.skipped,
        reason: 'consent-missing',
      );
    }

    final now = _clock();
    if (!force && _isThrottled(now, interval)) {
      return const RemoteFeaturePolicyRefreshResult(
        RemoteFeaturePolicyRefreshStatus.skipped,
        reason: 'throttled',
      );
    }

    await _ensureContext();
    _lastAttemptAt = now;
    try {
      final next = await repository.fetch();
      // A withdrawn agreement fences responses already in flight.
      if (!await _consentGranted()) {
        return const RemoteFeaturePolicyRefreshResult(
          RemoteFeaturePolicyRefreshStatus.skipped,
          reason: 'consent-missing',
        );
      }
      _adopt(next);
      try {
        await repository.persist(next);
      } on Object {
        // The in-memory snapshot stays authoritative for this session.
      }
      return const RemoteFeaturePolicyRefreshResult(
        RemoteFeaturePolicyRefreshStatus.applied,
      );
    } on Object catch (error) {
      _lastFailureAt = now;
      return RemoteFeaturePolicyRefreshResult(
        RemoteFeaturePolicyRefreshStatus.failed,
        error: error,
      );
    }
  }

  bool _isThrottled(DateTime now, Duration interval) {
    final failure = _lastFailureAt;
    if (failure != null) {
      final retry =
          config.failureRetryInterval > interval
              ? config.failureRetryInterval
              : interval;
      if (now.difference(failure) < retry) return true;
    }
    final attempt = _lastAttemptAt;
    if (attempt == null) return false;
    return now.difference(attempt) < interval;
  }

  void _adopt(RemoteFeaturePolicySnapshot snapshot) {
    _snapshot = snapshot;
    revision.value++;
  }

  bool _isFresh(RemoteFeaturePolicySnapshot snapshot) {
    return _clock().difference(snapshot.fetchedAt) <= config.highRiskMaxAge;
  }

  RemoteFeatureEvaluation _localDefault(String featureId) =>
      RemoteFeatureEvaluation(
        featureId: featureId,
        availability: RemoteFeatureAvailability.enabled,
        origin: RemoteFeaturePolicyOrigin.localDefault,
        fetchedAt: _snapshot?.fetchedAt,
      );

  RemoteFeatureEvaluation _failClosed(String featureId) =>
      RemoteFeatureEvaluation(
        featureId: featureId,
        availability: RemoteFeatureAvailability.unavailable,
        origin: RemoteFeaturePolicyOrigin.failClosed,
        fetchedAt: _snapshot?.fetchedAt,
      );

  /// Deterministic resolution of overlapping rows.
  ///
  /// Rank order: explicit priority, platform specificity, version specificity,
  /// newest `updated_at`. Rows that tie on every rank fall back to the most
  /// restrictive state so an ambiguous configuration cannot silently widen
  /// access.
  RemoteFeaturePolicy _resolve(List<RemoteFeaturePolicy> candidates) {
    final sorted = List<RemoteFeaturePolicy>.of(candidates)..sort((a, b) {
      final rank = _compareRank(a, b);
      if (rank != 0) return rank;
      if (a.state.severity != b.state.severity) {
        return b.state.severity.compareTo(a.state.severity);
      }
      return a.identityKey.compareTo(b.identityKey);
    });
    return sorted.first;
  }

  int _compareRank(RemoteFeaturePolicy a, RemoteFeaturePolicy b) {
    if (a.priority != b.priority) return b.priority.compareTo(a.priority);
    if (a.platformSpecificity != b.platformSpecificity) {
      return b.platformSpecificity.compareTo(a.platformSpecificity);
    }
    if (a.versionSpecificity != b.versionSpecificity) {
      return b.versionSpecificity.compareTo(a.versionSpecificity);
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }

  Future<bool> _consentGranted() async {
    final check = _consentCheck;
    if (check != null) {
      try {
        return await check();
      } on Object {
        return false;
      }
    }
    try {
      return await SupabasePrivacyGate.isAccepted();
    } on Object {
      return false;
    }
  }

  Future<FeaturePolicyContext> _ensureContext() async {
    final fixed = _fixedContext;
    if (fixed != null) {
      _context = fixed;
      return fixed;
    }
    final existing = _context;
    if (existing != null) return existing;
    final loader = _contextLoader;
    final FeaturePolicyContext resolved;
    if (loader != null) {
      resolved = await loader();
    } else {
      resolved = _fallbackContext();
    }
    _context = resolved;
    return resolved;
  }

  FeaturePolicyContext _fallbackContext() {
    // Before [start] resolves the host context the version is unknown, so
    // version-bounded rows do not match until then.
    return FeaturePolicyContext(platform: _platformFor(HostPlatform.current));
  }

  static FeaturePlatform _platformFor(HostPlatform platform) {
    switch (platform) {
      case HostPlatform.android:
        return FeaturePlatform.android;
      case HostPlatform.apple:
        return FeaturePlatform.ios;
      case HostPlatform.harmony:
        return FeaturePlatform.harmony;
      case HostPlatform.web:
        return FeaturePlatform.web;
      case HostPlatform.other:
        return FeaturePlatform.other;
    }
  }

  @visibleForTesting
  void dispose() {
    revision.dispose();
    repository.close();
  }
}

/// Resolves the host context used by the default singleton.
///
/// Kept outside the service so tests can inject a fixed context without
/// touching PackageInfo.
Future<FeaturePolicyContext> loadHostFeaturePolicyContext() async {
  String? version;
  try {
    version = await AppHostVersion.current;
  } on Object {
    version = null;
  }
  final valid = version != null && isValidSemver(version) ? version : null;
  final platform = HostPlatform.current;
  return FeaturePolicyContext(
    platform: switch (platform) {
      HostPlatform.android => FeaturePlatform.android,
      HostPlatform.apple => FeaturePlatform.ios,
      HostPlatform.harmony => FeaturePlatform.harmony,
      HostPlatform.web => FeaturePlatform.web,
      HostPlatform.other => FeaturePlatform.other,
    },
    appVersion: valid,
  );
}
