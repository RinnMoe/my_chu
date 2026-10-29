import 'dart:convert';

import '../../capabilities/text_utils.dart';

/// Wire values accepted by the `platform` column of `feature_policies`.
///
/// `all` matches every host; the remaining values mirror [HostPlatform] so a
/// policy can be limited to one distribution platform.
enum FeaturePlatform {
  all('all'),
  android('android'),
  ios('ios'),
  harmony('harmony'),
  web('web'),
  other('other');

  const FeaturePlatform(this.wireValue);

  final String wireValue;

  static FeaturePlatform? tryParse(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim().toLowerCase();
    for (final platform in FeaturePlatform.values) {
      if (platform.wireValue == value) return platform;
    }
    return null;
  }
}

/// The three operational states a remote policy can request.
///
/// [severity] only breaks ties between otherwise equally ranked rows; it never
/// overrides an explicit priority, platform or version match.
enum FeaturePolicyState {
  enabled('enabled', 0),
  maintenance('maintenance', 1),
  disabled('disabled', 2);

  const FeaturePolicyState(this.wireValue, this.severity);

  final String wireValue;
  final int severity;

  static FeaturePolicyState? tryParse(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim().toLowerCase();
    for (final state in FeaturePolicyState.values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

/// Thrown when a remote payload (or a cached snapshot) cannot be trusted.
///
/// A single invalid row invalidates the whole snapshot: partial application of
/// a damaged policy set is less predictable than keeping the previous snapshot.
class RemoteFeaturePolicyFormatException implements Exception {
  const RemoteFeaturePolicyFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'RemoteFeaturePolicyFormatException($reason)';
}

/// Thrown when the transport layer cannot deliver a policy payload.
class RemoteFeaturePolicyFetchException implements Exception {
  const RemoteFeaturePolicyFetchException(this.reason, {this.statusCode});

  final String reason;
  final int? statusCode;

  @override
  String toString() =>
      'RemoteFeaturePolicyFetchException($reason'
      '${statusCode == null ? '' : ', status $statusCode'})';
}

/// One published row of `feature_policies`.
class RemoteFeaturePolicy {
  const RemoteFeaturePolicy({
    required this.featureId,
    required this.state,
    required this.platform,
    required this.updatedAt,
    this.visible = true,
    this.message,
    this.minVersion,
    this.maxVersion,
    this.priority = 0,
  });

  static const int maxFeatureIdLength = 128;
  static const int maxMessageLength = 280;
  static const int maxPriorityMagnitude = 1000000;
  static final RegExp _featureIdPattern = RegExp(r'^[a-z0-9][a-z0-9._:-]*$');

  /// Stable MyCHU app ID, for example `feature.charging.pile`.
  final String featureId;
  final FeaturePolicyState state;

  /// Whether ordinary entry points (catalog, quick apps, navigation) list the
  /// feature. Independent from [state]: hiding is not prohibition.
  final bool visible;
  final String? message;
  final FeaturePlatform platform;

  /// Inclusive lower/upper bounds evaluated against the host versionName.
  final String? minVersion;
  final String? maxVersion;

  /// Higher wins before specificity is considered.
  final int priority;
  final DateTime updatedAt;

  /// Identity of the configuration scope, used to reject duplicate rows.
  String get scopeKey =>
      '$featureId|${platform.wireValue}|${minVersion ?? ''}|${maxVersion ?? ''}';

  /// Full row identity, used as a deterministic final tie-break.
  String get identityKey =>
      '$scopeKey|${state.wireValue}|'
      '${updatedAt.toUtc().toIso8601String()}|$priority';

  int get platformSpecificity => platform == FeaturePlatform.all ? 0 : 1;

  int get versionSpecificity {
    final bounded = (minVersion == null ? 0 : 1) + (maxVersion == null ? 0 : 1);
    return bounded;
  }

  /// Whether this row applies to the current host.
  ///
  /// Version-bounded rows never match when the host version is unknown, so a
  /// build without a parseable versionName falls back to unbounded rows only.
  bool matches({
    required FeaturePlatform platform,
    required String? appVersion,
  }) {
    if (this.platform != FeaturePlatform.all && this.platform != platform) {
      return false;
    }
    if (minVersion == null && maxVersion == null) return true;
    final version = appVersion;
    if (version == null || !isValidSemver(version)) return false;
    if (minVersion != null && compareSemver(version, minVersion!) < 0) {
      return false;
    }
    if (maxVersion != null && compareSemver(version, maxVersion!) > 0) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'feature_id': featureId,
    'state': state.wireValue,
    'visible': visible,
    'message': message,
    'platform': platform.wireValue,
    'min_version': minVersion,
    'max_version': maxVersion,
    'priority': priority,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory RemoteFeaturePolicy.parse(Object? value) {
    if (value is! Map) {
      throw const RemoteFeaturePolicyFormatException('row is not an object');
    }
    final rawId = value['feature_id'];
    if (rawId is! String) {
      throw const RemoteFeaturePolicyFormatException('feature_id is missing');
    }
    final featureId = rawId.trim();
    if (featureId.isEmpty ||
        featureId.length > maxFeatureIdLength ||
        !_featureIdPattern.hasMatch(featureId)) {
      throw const RemoteFeaturePolicyFormatException('feature_id is invalid');
    }

    final state = FeaturePolicyState.tryParse(value['state']);
    if (state == null) {
      throw const RemoteFeaturePolicyFormatException('state is invalid');
    }

    final platform = FeaturePlatform.tryParse(value['platform'] ?? 'all');
    if (platform == null) {
      throw const RemoteFeaturePolicyFormatException('platform is invalid');
    }

    final rawVisible = value['visible'];
    if (rawVisible != null && rawVisible is! bool) {
      throw const RemoteFeaturePolicyFormatException('visible is invalid');
    }

    final rawMessage = value['message'];
    if (rawMessage != null && rawMessage is! String) {
      throw const RemoteFeaturePolicyFormatException('message is invalid');
    }
    var message = (rawMessage as String?)?.trim();
    if (message != null && message.isEmpty) message = null;
    if (message != null && message.length > maxMessageLength) {
      message = message.substring(0, maxMessageLength);
    }

    final minVersion = _parseVersion(value['min_version'], 'min_version');
    final maxVersion = _parseVersion(value['max_version'], 'max_version');
    if (minVersion != null &&
        maxVersion != null &&
        compareSemver(minVersion, maxVersion) > 0) {
      throw const RemoteFeaturePolicyFormatException(
        'version range is inverted',
      );
    }

    final rawPriority = value['priority'];
    final int? priority;
    if (rawPriority == null) {
      priority = 0;
    } else if (rawPriority is int) {
      priority = rawPriority;
    } else if (rawPriority is num) {
      priority = rawPriority.toInt();
    } else {
      throw const RemoteFeaturePolicyFormatException('priority is invalid');
    }
    if (priority.abs() > maxPriorityMagnitude) {
      throw const RemoteFeaturePolicyFormatException(
        'priority is out of range',
      );
    }

    return RemoteFeaturePolicy(
      featureId: featureId,
      state: state,
      visible: (rawVisible as bool?) ?? true,
      message: message,
      platform: platform,
      minVersion: minVersion,
      maxVersion: maxVersion,
      priority: priority,
      updatedAt: _parseTimestamp(value['updated_at']),
    );
  }
}

String? _parseVersion(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! String) {
    throw RemoteFeaturePolicyFormatException('$field is invalid');
  }
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!isValidSemver(value)) {
    throw RemoteFeaturePolicyFormatException('$field is not a version');
  }
  return value;
}

DateTime _parseTimestamp(Object? raw) {
  if (raw is DateTime) return raw.toUtc();
  if (raw is String) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed != null) return parsed.toUtc();
  }
  throw const RemoteFeaturePolicyFormatException('updated_at is invalid');
}

/// A complete, validated policy set captured at one point in time.
///
/// The snapshot is replaced atomically: callers either keep the previous
/// snapshot or adopt a fully validated new one.
class RemoteFeaturePolicySnapshot {
  const RemoteFeaturePolicySnapshot({
    required this.policies,
    required this.fetchedAt,
  });

  static const int schemaVersion = 1;

  final List<RemoteFeaturePolicy> policies;
  final DateTime fetchedAt;

  /// Validates every row before constructing the snapshot.
  factory RemoteFeaturePolicySnapshot.fromRows(
    Iterable<Object?> rows, {
    required DateTime fetchedAt,
  }) {
    final policies = <RemoteFeaturePolicy>[
      for (final row in rows) RemoteFeaturePolicy.parse(row),
    ];
    final scopes = <String>{};
    for (final policy in policies) {
      if (!scopes.add(policy.scopeKey)) {
        throw const RemoteFeaturePolicyFormatException(
          'duplicate policy scope',
        );
      }
    }
    return RemoteFeaturePolicySnapshot(
      policies: List<RemoteFeaturePolicy>.unmodifiable(policies),
      fetchedAt: fetchedAt.toUtc(),
    );
  }

  factory RemoteFeaturePolicySnapshot.decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const RemoteFeaturePolicyFormatException('snapshot is not JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RemoteFeaturePolicyFormatException(
        'snapshot is not an object',
      );
    }
    if (decoded['schema'] != schemaVersion) {
      throw const RemoteFeaturePolicyFormatException('snapshot schema differs');
    }
    final rows = decoded['policies'];
    if (rows is! List) {
      throw const RemoteFeaturePolicyFormatException('snapshot has no rows');
    }
    return RemoteFeaturePolicySnapshot.fromRows(
      rows,
      fetchedAt: _parseTimestamp(decoded['fetched_at']),
    );
  }

  String encode() => jsonEncode({
    'schema': schemaVersion,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
    'policies': [for (final policy in policies) policy.toJson()],
  });

  /// All rows that name [featureId], regardless of platform/version match.
  Iterable<RemoteFeaturePolicy> policiesFor(String featureId) =>
      policies.where((policy) => policy.featureId == featureId);
}

/// Where the effective decision for one feature came from.
enum RemoteFeaturePolicyOrigin { localDefault, remotePolicy, failClosed }

/// The availability a remote policy layer assigns to one feature.
enum RemoteFeatureAvailability { enabled, disabled, maintenance, unavailable }

/// Result of evaluating the remote layer alone, before local gates apply.
class RemoteFeatureEvaluation {
  const RemoteFeatureEvaluation({
    required this.featureId,
    required this.availability,
    required this.origin,
    this.visible = true,
    this.message,
    this.fetchedAt,
  });

  final String featureId;
  final RemoteFeatureAvailability availability;
  final RemoteFeaturePolicyOrigin origin;

  /// Entry visibility requested by the policy, including blocked entries.
  final bool visible;
  final String? message;

  /// Capture time of the snapshot that produced this decision.
  final DateTime? fetchedAt;

  bool get allowsUsage => availability == RemoteFeatureAvailability.enabled;

  bool get allowsEntry => allowsUsage && visible;
}
