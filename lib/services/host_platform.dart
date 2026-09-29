import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

/// A normalized platform identity for shared host logic.
///
/// Flutter OH adds an ohos target name. Resolve its runtime name instead of
/// referring to a fork-only enum value so standard Flutter remains compatible.
enum HostPlatform {
  android,
  apple,
  harmony,
  web,
  other;

  /// The current runtime platform, normalized across Flutter distributions.
  static HostPlatform get current =>
      resolve(platformName: defaultTargetPlatform.name, isWeb: kIsWeb);

  /// Maps Flutter's platform name without requiring fork-specific enum cases.
  static HostPlatform resolve({
    required String platformName,
    required bool isWeb,
  }) {
    if (isWeb) return HostPlatform.web;
    switch (platformName.trim().toLowerCase()) {
      case 'android':
        return HostPlatform.android;
      case 'ios':
        return HostPlatform.apple;
      case 'ohos':
        return HostPlatform.harmony;
      default:
        return HostPlatform.other;
    }
  }
}
