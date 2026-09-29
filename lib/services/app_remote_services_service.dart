import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference and service boundary for MyCHU-operated remote services.
///
/// Campus services and independent third-party APIs do not use this switch.
class AppRemoteServicesService {
  AppRemoteServicesService._();

  static const String preferenceKey = 'mychu.remote_services.enabled';
  static const String _legacyAnalyticsPreferenceKey = 'mychu.analytics.enabled';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    final currentValue = preferences.getBool(preferenceKey);
    if (currentValue != null) return currentValue;

    // Preserve an explicit opt-out from builds that had the narrower
    // Aptabase-only switch. A missing legacy value still defaults to enabled.
    if (preferences.containsKey(_legacyAnalyticsPreferenceKey)) {
      final previousValue =
          preferences.getBool(_legacyAnalyticsPreferenceKey) ?? false;
      final saved = await preferences.setBool(preferenceKey, previousValue);
      if (!saved) throw StateError('无法迁移应用远程服务设置');
      await preferences.remove(_legacyAnalyticsPreferenceKey);
      return previousValue;
    }
    return true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(preferenceKey, enabled);
    if (!saved) throw StateError('无法保存应用远程服务设置');
    await preferences.remove(_legacyAnalyticsPreferenceKey);
    revision.value++;
  }
}

class AppRemoteServicesDisabledException implements Exception {
  const AppRemoteServicesDisabledException();

  static const String userMessage = '您已关闭应用远程服务';

  @override
  String toString() => 'AppRemoteServicesDisabledException';
}
