import 'package:flutter/foundation.dart';

import '../capabilities/saved_login_credential.dart';

export '../capabilities/saved_login_credential.dart' show SavedLoginCredential;

/// 已保存登录凭据的宿主级安全存储。
///
/// - 账号密码写入 `FlutterSecureStorage`（Android Keystore 加密）。
/// - 退出登录、静默重登确认密码失效时清除账号密码。
class SavedLoginCredentialService {
  SavedLoginCredentialService._();

  /// Notifies host surfaces when saved login data changes.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Test hook：允许测试替换安全存储与偏好存储入口。
  static Future<String?> Function(String key)? debugSecureRead;
  static Future<void> Function(String key, String value)? debugSecureWrite;
  static Future<void> Function(String key)? debugSecureDelete;

  static SavedLoginCredentialCapability get _capability =>
      SavedLoginCredentialCapability.unifiedIdentity(
        secureRead: debugSecureRead,
        secureWrite: debugSecureWrite,
        secureDelete: debugSecureDelete,
      );

  /// 读取已保存凭据；不存在或格式异常时返回 null。
  static Future<SavedLoginCredential?> read() => _capability.read();

  static Future<bool> hasCredential() async => (await read()) != null;

  /// 保存（覆盖）账号密码。空值直接忽略。
  static Future<void> save(String username, String password) async {
    await _capability.save(username, password);
    revision.value++;
  }

  /// 清除已保存账号密码。
  static Future<void> clearCredential() async {
    await _capability.clear();
    revision.value++;
  }

  /// 日志/界面展示用的脱敏账号：保留首尾各 2 位。
  static String maskUsername(String username) {
    if (username.length <= 4) return username;
    return '${username.substring(0, 2)}****${username.substring(username.length - 2)}';
  }
}
