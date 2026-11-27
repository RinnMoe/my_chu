import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mail_config.dart';

/// 非机密邮箱配置的本地存储。
class MailConfigStore {
  static const storageKey = 'mychu.mail.account.v1';

  final Future<SharedPreferences> Function() _preferences;

  MailConfigStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  Future<MailAccountConfig?> read() async {
    final preferences = await _preferences();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MailAccountConfig.fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<void> save(MailAccountConfig config) async {
    final preferences = await _preferences();
    await preferences.setString(storageKey, jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    final preferences = await _preferences();
    await preferences.remove(storageKey);
  }
}
