import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Imports only the account active at upgrade. Never falls back to a former
/// account or anonymous settings. Cleanup is retryable after the durable marker.
class GlobalPreferencesMigration {
  @visibleForTesting
  static Future<bool> Function(String key, Object value)? debugWrite;
  static const marker = 'preferences.v1.migrated';
  static const _families = {
    'nav.v2.tabs.': 'preferences.v1.navigation',
    'nav.v1.tabs.': 'preferences.v1.navigation',
    'home.v2.quick_apps.': 'preferences.v1.quick_apps',
    'campus.settings.v1.': 'preferences.v1.campus',
    'academic_schedule.show_noncurrent.v1.':
        'preferences.v1.schedule.show_noncurrent',
    'academic_schedule.hide_weekend.v1.':
        'preferences.v1.schedule.hide_weekend',
    'information_portal.balance_hidden.v1.': 'preferences.v1.balance_hidden',
    'plugins.v1.recent.': 'preferences.v1.recent',
  };

  static Future<void> ensure(String? currentAccountKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(marker) != true) {
      if (currentAccountKey != null) {
        for (final entry in _families.entries) {
          final value = prefs.get('${entry.key}$currentAccountKey');
          if (value != null &&
              _validValue(entry.value, value) &&
              !prefs.containsKey(entry.value)) {
            await _writeVerified(prefs, entry.value, value);
          }
        }
      }
      await _writeVerified(prefs, marker, true);
    }
    final obsolete =
        prefs
            .getKeys()
            .where(
              (key) =>
                  _families.keys.any(key.startsWith) ||
                  key.startsWith('live_update.') ||
                  key.startsWith('alerts.v1.') ||
                  key == 'plugins.v1.recent',
            )
            .toList();
    for (final key in obsolete) {
      if (!await prefs.remove(key)) {
        throw StateError('Preference cleanup failed');
      }
    }
  }

  static bool _validValue(String key, Object value) {
    if (key == 'preferences.v1.campus') return value is String;
    if (key == 'preferences.v1.recent') return value is List<String>;
    if (key == 'preferences.v1.navigation' ||
        key == 'preferences.v1.quick_apps') {
      if (value is! String) return false;
      try {
        final decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic>) return false;
        if (key == 'preferences.v1.quick_apps' &&
            decoded['enabled'] != null &&
            decoded['enabled'] is! bool) {
          return false;
        }
        return true;
      } on FormatException {
        return false;
      }
    }
    return value is bool;
  }

  static Future<void> _writeVerified(
    SharedPreferences prefs,
    String key,
    Object value,
  ) async {
    final saved =
        debugWrite != null
            ? await debugWrite!(key, value)
            : switch (value) {
              bool v => await prefs.setBool(key, v),
              String v => await prefs.setString(key, v),
              int v => await prefs.setInt(key, v),
              double v => await prefs.setDouble(key, v),
              List<String> v => await prefs.setStringList(key, v),
              _ => false,
            };
    if (saved) await prefs.reload();
    final actual = prefs.get(key);
    final matches =
        value is List<String>
            ? actual is List<String> && listEquals(value, actual)
            : actual == value;
    if (!saved || !matches) throw StateError('Preference migration failed');
  }
}
