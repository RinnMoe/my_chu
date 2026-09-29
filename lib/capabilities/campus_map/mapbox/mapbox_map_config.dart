import "package:mapbox_maps_flutter/mapbox_maps_flutter.dart";

import "../../mapbox_cloud_config.dart";
import "../map_engine.dart";

/// Mapbox runtime configuration.
///
/// Supply the Mapbox Public Token through the
/// `MAPBOX_PUBLIC_ACCESS_TOKEN` Dart compile-time define. Public `pk.*` tokens
/// are intended for client applications; Secret `sk.*` tokens must never be
/// used here. The Studio Style is fixed in the app. Constructor values are
/// retained only for SDK-free tests.
class MapboxMapConfig {
  static const String mapboxAccessToken = MapboxCloudConfig.accessToken;
  static const String mapLanguage = "zh-Hans";
  static const String mapWorldview = "CN";
  // This is the fixed Studio style used by the web preview and the App.
  static const String mapboxStyleUri = MapboxCloudConfig.styleUri;
  static const String builtInStyleUri = mapboxStyleUri;
  // Keep the native attribution affordance legible while reducing the
  // saturated blue accent against the light map surface. The Mapbox wordmark
  // itself remains native and unmodified.
  static const int attributionIconColor = 0xCC8E969E;

  final String? _accessTokenOverride;
  final String? _styleUriOverride;

  const MapboxMapConfig({String? accessToken, String? styleUri})
    : _accessTokenOverride = accessToken,
      _styleUriOverride = styleUri;

  String get accessToken {
    final override = _accessTokenOverride;
    if (override != null) return override.trim();
    return mapboxAccessToken;
  }

  bool get isConfigured =>
      accessToken.startsWith("pk.") && accessToken.length > "pk.".length;

  bool get hasCustomStyle => resolvedStyleUri != MapboxStyles.STANDARD;

  String get resolvedStyleUri {
    final value = (_styleUriOverride ?? mapboxStyleUri).trim();
    return value.isEmpty ? MapboxStyles.STANDARD : value;
  }

  void configureSdk() {
    if (!isConfigured) {
      throw const CampusMapConfigurationException(
        "Mapbox access token is not configured.",
      );
    }
    MapboxOptions.setAccessToken(accessToken);
    // Mapbox Standard reads the SDK-wide BCP-47 locale during map
    // initialization. The Flutter SDK documents this API but still marks it
    // experimental, so keep the suppression scoped to this required call.
    // ignore: experimental_member_use
    MapboxMapsOptions.setLanguage(mapLanguage);
    // Match the web preview's China worldview. This is a global SDK option
    // and must be set before the MapWidget/native map instance is created.
    // ignore: experimental_member_use
    MapboxMapsOptions.setWorldview(mapWorldview);
  }
}
