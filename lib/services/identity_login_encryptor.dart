import 'dart:convert';
import 'dart:math';

import 'package:pointycastle/export.dart';

/// 复刻统一身份认证登录页 `encrypt.js` 的密码加密逻辑。
///
/// 官方流程（与 CHUAuthSDK Python 实现一致）：
/// 1. 明文 = `randomString(64) + password`；
/// 2. AES-128-CBC + PKCS7，key 为页面 `pwdEncryptSalt` 的 UTF-8 字节，
///    IV 为 `randomString(16)` 的 UTF-8 字节；
/// 3. 输出为原始密文的 Base64（不含 `Salted__` 前缀）。
///
/// 64 位随机前缀保证密文首块对服务端解密误差不可见；仅用于登录提交，
/// 不承担本地存储加密职责（本地密码由系统安全存储保护）。
class IdentityLoginEncryptor {
  IdentityLoginEncryptor._();

  static const _aesChars =
      'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  /// 与官方 `randomString` 相同字符表的随机串；[random] 仅供测试注入。
  static String randomString(int length, {Random? random}) {
    final source = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(
        _aesChars.codeUnitAt(source.nextInt(_aesChars.length)),
      );
    }
    return buffer.toString();
  }

  /// 按登录页脚本加密密码；[salt] 为登录页 `pwdEncryptSalt` 隐藏字段值。
  static String encryptPassword(String password, String salt, {Random? random}) {
    final prefix = randomString(64, random: random);
    final ivText = randomString(16, random: random);

    final plainBytes = utf8.encode(prefix + password);
    final keyBytes = utf8.encode(salt);
    final ivBytes = utf8.encode(ivText);

    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
          null,
        ),
      );
    return base64Encode(cipher.process(plainBytes));
  }
}
