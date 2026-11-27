import '../../capabilities/saved_login_credential.dart';

/// 邮箱密码的安全存储。
///
/// 使用宿主已有的 `SavedLoginCredentialCapability`，命名空间为 `mail`，
/// 与统一身份、频道资料站互不覆盖。
class MailCredentialStore {
  static const scope = 'mail';

  final SavedLoginCredentialCapability _capability;

  MailCredentialStore({SavedLoginCredentialCapability? capability})
    : _capability = capability ?? SavedLoginCredentialCapability(scope: scope);

  Future<String?> readSecret(String email) async {
    final credential = await _capability.read();
    if (credential == null) return null;
    if (credential.username != email) return null;
    return credential.password;
  }

  Future<bool> hasCredential(String email) async =>
      await readSecret(email) != null;

  Future<void> save(String email, String secret) =>
      _capability.save(email, secret);

  Future<void> clear() => _capability.clear();
}
