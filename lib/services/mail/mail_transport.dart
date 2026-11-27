import 'dart:typed_data';

import 'mail_compose.dart';
import 'mail_config.dart';
import 'mail_models.dart';

/// 邮件传输抽象。
///
/// 生产实现只在 `enough_mail_transport.dart` 中出现；测试通过构造函数注入
/// 假实现，不建立任何 socket 连接。
abstract interface class MailTransport {
  Future<MailConnection> connect(MailAccountConfig config, String secret);
}

/// SMTP 发送抽象。
///
/// 生产实现只在 `enough_mail_sender.dart` 中出现。
abstract interface class MailSender {
  Future<MailSendReceipt> send(
    MailAccountConfig config,
    String secret,
    MailDraft draft,
  );
}

abstract interface class MailConnection {
  Future<List<MailFolder>> listFolders();

  Future<MailPage> fetchHeaders(
    String folderPath, {
    int? beforeUid,
    int limit = 20,
  });

  Future<MailBody> fetchBody(String folderPath, int uid);

  Future<Uint8List> downloadAttachment(
    String folderPath,
    int uid,
    String fetchId, {
    int knownSize = 0,
  });

  Future<void> setSeen(String folderPath, int uid, bool seen);

  Future<int> unreadCount(String folderPath);

  /// 把已发送邮件追加到服务器「已发送」文件夹。
  ///
  /// 成功写入返回 true；服务器没有可识别的已发送文件夹时返回 false。
  Future<bool> appendToSent(String messageText);

  Future<void> close();
}
