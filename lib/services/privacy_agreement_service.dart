import 'package:shared_preferences/shared_preferences.dart';

/// Stores whether the user accepted the current user agreement.
class PrivacyAgreementService {
  PrivacyAgreementService._();

  /// Bump when a new agreement must be explicitly accepted.
  static const int currentVersion = 2;
  static const String versionKey = 'privacy.agreement.version';
  static const String _legacyMigrationKey =
      'privacy.agreement.legacy_v7_migrated';
  static const String _legacyConsentKey = 'privacy.consent.sdk_list';
  static const String _legacyVersionKey = 'privacy.consent.sdk_list.version';
  static const int _legacyConsentVersion = 7;

  static Future<bool> isAccepted() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyV7(preferences);
    return (preferences.getInt(versionKey) ?? 0) >= currentVersion;
  }

  static Future<void> accept() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyV7(preferences);
    final saved = await preferences.setInt(versionKey, currentVersion);
    if (!saved) throw StateError('无法保存隐私协议状态');
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyV7(preferences);
    final removed = await preferences.remove(versionKey);
    if (!removed && preferences.containsKey(versionKey)) {
      throw StateError('无法清除隐私协议状态');
    }
  }

  static Future<void> _migrateLegacyV7(SharedPreferences preferences) async {
    if (preferences.getBool(_legacyMigrationKey) == true) return;

    final legacyKeys = preferences
        .getKeys()
        .where((key) => key.startsWith('privacy.consent.'))
        .toList(growable: false);
    final legacyAccepted =
        preferences.getBool(_legacyConsentKey) == true &&
        (preferences.getInt(_legacyVersionKey) ?? 0) >= _legacyConsentVersion;

    if (legacyAccepted) {
      final saved = await preferences.setInt(versionKey, currentVersion - 1);
      if (!saved) throw StateError('无法迁移既有隐私协议状态');
    }

    for (final key in legacyKeys) {
      final removed = await preferences.remove(key);
      if (!removed && preferences.containsKey(key)) {
        throw StateError('无法清理旧隐私状态');
      }
    }

    final marked = await preferences.setBool(_legacyMigrationKey, true);
    if (!marked) throw StateError('无法完成旧隐私状态迁移');
  }
}
