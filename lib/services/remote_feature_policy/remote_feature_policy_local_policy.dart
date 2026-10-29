/// How strongly a feature depends on a confirmed remote policy.
enum FeatureSafetyLevel {
  /// Normal feature: it stays available when no policy row matches, so a
  /// Supabase outage cannot disable the whole application.
  standard,

  /// Operation that must be confirmed by the server before it may run.
  ///
  /// A high-risk feature is only available while a fresh snapshot contains an
  /// explicit `enabled` row for it. Missing or stale snapshots keep it closed.
  /// This is a local, compile-time decision: a remote payload cannot promote a
  /// feature to a lower safety level.
  highRisk,
}

/// Local, trusted policy defaults compiled into the build.
///
/// Remote configuration can only restrict what this registry and the existing
/// development/installation gates already allow. Adding a feature ID here is a
/// deliberate release decision and must be reviewed with the feature owner.
class FeatureLocalPolicyRegistry {
  FeatureLocalPolicyRegistry._();

  /// Explicit safety overrides. Unlisted built-in apps are [standard].
  static const Map<String, FeatureSafetyLevel> overrides = {};

  static FeatureSafetyLevel levelFor(String featureId) =>
      overrides[featureId] ?? FeatureSafetyLevel.standard;

  /// IDs that must never be disabled remotely because losing them would remove
  /// the user's ability to consent, sign out, update, or recover the client.
  ///
  /// Core host surfaces (agreement, login, settings, updates, profile) are not
  /// registered apps, so they are already outside the policy surface. This list
  /// additionally protects any future app ID that carries the same duty.
  static const Set<String> protectedFeatureIds = {};

  static bool isProtected(String featureId) =>
      protectedFeatureIds.contains(featureId);
}

/// Local defaults consumed by the policy service.
///
/// The production implementation reads the compiled registry above; tests
/// inject their own instance instead of mutating global state.
abstract class FeaturePolicyDefaults {
  const FeaturePolicyDefaults();

  FeatureSafetyLevel levelFor(String featureId);

  bool isProtected(String featureId);
}

class CompiledFeaturePolicyDefaults implements FeaturePolicyDefaults {
  const CompiledFeaturePolicyDefaults();

  @override
  FeatureSafetyLevel levelFor(String featureId) =>
      FeatureLocalPolicyRegistry.levelFor(featureId);

  @override
  bool isProtected(String featureId) =>
      FeatureLocalPolicyRegistry.isProtected(featureId);
}
