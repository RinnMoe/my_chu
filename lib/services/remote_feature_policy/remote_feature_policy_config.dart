import '../supabase/supabase_project_config.dart';

/// Compile-time configuration for the Remote Feature Policy module.
///
/// Only the project URL and the publishable (anon) key are compiled into the
/// client. Database administration keys must never be shipped: every write is
/// denied by row level security and performed from the Supabase Dashboard or a
/// trusted backend.
class RemoteFeaturePolicyConfig {
  const RemoteFeaturePolicyConfig({
    this.endpoint,
    this.publishableKey = '',
    this.requestTimeout = const Duration(seconds: 6),
    this.refreshInterval = const Duration(minutes: 15),
    this.foregroundRefreshInterval = const Duration(minutes: 5),
    this.failureRetryInterval = const Duration(minutes: 5),
    this.highRiskMaxAge = const Duration(hours: 24),
  });

  /// Fully qualified PostgREST endpoint of the policy table.
  final Uri? endpoint;
  final String publishableKey;
  final Duration requestTimeout;

  /// Minimum interval between two successful refreshes.
  final Duration refreshInterval;

  /// Minimum interval between two foreground refreshes.
  final Duration foregroundRefreshInterval;

  /// Minimum interval before retrying after a failed refresh.
  final Duration failureRetryInterval;

  /// A high-risk feature stays closed when its confirming snapshot is older
  /// than this window.
  final Duration highRiskMaxAge;

  /// The module is inert unless both values are present and valid.
  bool get isConfigured =>
      endpoint != null &&
      SupabaseEndpointConfig.tryParse(
            url: endpoint!.replace(path: '').toString(),
            anonKey: publishableKey,
          ) !=
          null;

  Map<String, String> get authHeaders =>
      SupabaseEndpointConfig.tryParse(
        url: endpoint!.replace(path: '').toString(),
        anonKey: publishableKey,
      )!.authHeaders;

  static const String urlEnvironmentKey = 'MYCHU_SUPABASE_URL';
  static const String keyEnvironmentKey = 'MYCHU_SUPABASE_PUBLISHABLE_KEY';
  static const String tableName = 'feature_policies';

  /// Reads `--dart-define` values. A malformed URL disables the module instead
  /// of pointing the client at an unintended host.
  factory RemoteFeaturePolicyConfig.fromEnvironment() {
    return RemoteFeaturePolicyConfig.fromValues(
      projectUrl: SupabaseEndpointConfig.environmentUrl,
      publishableKey: SupabaseEndpointConfig.environmentKey,
    );
  }

  factory RemoteFeaturePolicyConfig.fromValues({
    required String projectUrl,
    required String publishableKey,
    Duration requestTimeout = const Duration(seconds: 6),
    Duration refreshInterval = const Duration(minutes: 15),
    Duration foregroundRefreshInterval = const Duration(minutes: 5),
    Duration failureRetryInterval = const Duration(minutes: 5),
    Duration highRiskMaxAge = const Duration(hours: 24),
  }) {
    return RemoteFeaturePolicyConfig(
      endpoint: SupabaseEndpointConfig.tryParse(
        url: projectUrl,
        anonKey: publishableKey,
      )?.restUri(tableName),
      publishableKey: publishableKey.trim(),
      requestTimeout: requestTimeout,
      refreshInterval: refreshInterval,
      foregroundRefreshInterval: foregroundRefreshInterval,
      failureRetryInterval: failureRetryInterval,
      highRiskMaxAge: highRiskMaxAge,
    );
  }

  /// Builds the policy endpoint from a project URL.
  ///
  /// Accepts `https://<ref>.supabase.co` with or without a trailing slash and
  /// rejects plaintext HTTP, query strings and non-root paths.
  static Uri? resolveEndpoint(String projectUrl) {
    return SupabaseEndpointConfig.tryParse(
      url: projectUrl,
      anonKey: 'sb_publishable_endpoint_validation',
    )?.restUri(tableName);
  }
}
