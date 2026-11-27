import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;

/// 从已解析的邮件中取出指定 BODY 段的二进制内容。
///
/// 单独下载附件时，`enough_mail` 只有在同一 FETCH 里拿到 BODYSTRUCTURE 才能
/// 把 `Content-Transfer-Encoding` 复制到 part 上；本函数只负责解码，编码是否
/// 完整由调用方保证。
Uint8List? mailPartBytes(mail.MimeMessage message, String fetchId) {
  try {
    return message.getPart(fetchId)?.decodeContentBinary();
  } on Object {
    return null;
  }
}
