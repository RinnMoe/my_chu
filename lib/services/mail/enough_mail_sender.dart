import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/foundation.dart';

import 'mail_compose.dart';
import 'mail_config.dart';
import 'mail_error.dart';
import 'mail_models.dart';
import 'mail_transport.dart';

/// 通过 `enough_mail` 的 SMTP 客户端发送纯文本邮件。
///
/// 该文件是除 IMAP 传输外唯一接触协议类型的地方：页面与会话只提交
/// [MailDraft]，这里负责 MIME 组装、认证与错误收敛。
class EnoughMailSender implements MailSender {
  const EnoughMailSender();

  static const maxMessageBytes = 25 * 1024 * 1024;

  @override
  Future<MailSendReceipt> send(
    MailAccountConfig config,
    String secret,
    MailDraft draft,
  ) async {
    final MailSendReceipt receipt;
    try {
      final messageText = renderMessage(config, draft);
      if (messageText.length > maxMessageBytes) {
        throw _tooLarge();
      }
      receipt = MailSendReceipt(
        messageText: messageText,
        size: messageText.length,
      );
    } on MailException {
      rethrow;
    } on Object catch (error) {
      throw MailException(
        MailErrorKind.malformed,
        '邮件内容无法编码，请检查主题或附件名',
        cause: error,
      );
    }

    final client = mail.SmtpClient(
      _clientDomain(config),
      isLogEnabled: false,
    );
    try {
      await client
          .connectToServer(
            config.smtpHost,
            config.smtpPort,
            isSecure: config.smtpSecurity == MailSecurity.ssl,
            timeout: const Duration(seconds: 15),
          )
          .timeout(const Duration(seconds: 18));
      await client.ehlo().timeout(const Duration(seconds: 15));
      if (config.smtpSecurity == MailSecurity.starttls) {
        final tls = await client
            .startTls()
            .timeout(const Duration(seconds: 15));
        if (tls.isFailedStatus) throw _protocol();
      }
      final mechanism = _authMechanism(client);
      await client
          .authenticate(config.email, secret, mechanism)
          .timeout(const Duration(seconds: 20));

      final serverLimit = client.serverInfo.maxMessageSize;
      if (serverLimit != null && serverLimit > 0 && receipt.size > serverLimit) {
        throw _tooLarge();
      }

      final response = await client
          .sendMessageText(
            receipt.messageText,
            mail.MailAddress(null, config.email),
            _toEnoughAddresses([
              ...draft.to,
              ...draft.cc,
              ...draft.bcc,
            ]),
          )
          .timeout(const Duration(seconds: 90));
      if (response.isFailedStatus) {
        throw _responseError(response);
      }
      return receipt;
    } on mail.SmtpException catch (error) {
      throw _smtpError(error);
    } on MailException {
      rethrow;
    } on TimeoutException catch (error) {
      throw MailException(
        MailErrorKind.timeout,
        '发送邮件超时，请稍后重试',
        cause: error,
      );
    } catch (error) {
      throw MailException.fromError(error);
    } finally {
      await _quitQuietly(client);
    }
  }

  /// 渲染待发送的 RFC 5322 文本。
  ///
  /// 生产发送路径复用同一方法；测试用它验证 MIME 结构与 header 安全。
  @visibleForTesting
  static String renderMessage(MailAccountConfig config, MailDraft draft) =>
      _buildMessage(config, draft).renderMessage();

  static mail.MimeMessage _buildMessage(
    MailAccountConfig config,
    MailDraft draft,
  ) {
    mail.MessageBuilder builder;
    if (draft.attachments.isEmpty) {
      builder = mail.MessageBuilder(
        text: draft.text,
        // 正文统一 base64：SMTP DATA 的 dot-stuffing 由底层库处理，
        // 避免纯文本中以 `.` 开头的行在传输时丢失首字符。
        transferEncoding: mail.TransferEncoding.base64,
        characterSet: mail.CharacterSet.utf8,
      );
    } else {
      // 根节点一旦成为 multipart，构造器里的 text 不会转成子节点，
      // 必须显式加入 text/plain 子部分，否则正文丢失。
      builder = mail.MessageBuilder(characterSet: mail.CharacterSet.utf8)
        ..addTextPlain(
          draft.text,
          transferEncoding: mail.TransferEncoding.base64,
          characterSet: mail.CharacterSet.utf8,
        );
      for (final attachment in draft.attachments) {
        builder.addBinary(
          attachment.bytes,
          _mediaType(attachment),
          filename: attachment.name,
        );
      }
    }

    builder
      ..from = [mail.MailAddress(null, config.email)]
      ..to = _toEnoughAddresses(draft.to)
      ..subject = draft.sanitizedSubject
      ..date = DateTime.now();
    if (draft.cc.isNotEmpty) builder.cc = _toEnoughAddresses(draft.cc);
    if (draft.bcc.isNotEmpty) builder.bcc = _toEnoughAddresses(draft.bcc);

    final replyId = cleanMailMessageId(draft.inReplyTo);
    if (replyId != null) {
      builder
        ..setHeader('In-Reply-To', replyId)
        ..setHeader('References', replyId);
    }

    final message = builder.buildMimeMessage();
    // 密送地址只用于 SMTP 收件人列表，不能出现在 DATA 里。
    message.removeHeader('Bcc');
    return message;
  }

  static List<mail.MailAddress> _toEnoughAddresses(List<MailAddress> addresses) {
    return [
      for (final address in addresses)
        mail.MailAddress(address.name, address.address),
    ];
  }

  static mail.MediaType _mediaType(OutgoingAttachment attachment) {
    try {
      final parsed = mail.MediaType.fromText(attachment.mimeType);
      if (parsed.text != 'application/octet-stream') return parsed;
    } on Object {
      // 退回按文件名推断。
    }
    return mail.MediaType.guessFromFileName(attachment.name);
  }

  static String _clientDomain(MailAccountConfig config) {
    final at = config.email.lastIndexOf('@');
    if (at < 0 || at == config.email.length - 1) return 'localhost';
    return config.email.substring(at + 1);
  }

  static mail.AuthMechanism _authMechanism(mail.SmtpClient client) {
    final serverInfo = client.serverInfo;
    if (serverInfo.supportsAuth(mail.AuthMechanism.plain)) {
      return mail.AuthMechanism.plain;
    }
    if (serverInfo.supportsAuth(mail.AuthMechanism.login)) {
      return mail.AuthMechanism.login;
    }
    throw const MailException(
      MailErrorKind.protocol,
      '邮件服务器不支持当前登录方式',
    );
  }

  static MailException _smtpError(mail.SmtpException error) =>
      _codeError(error.response.code, error);

  static MailException _responseError(mail.SmtpResponse response) =>
      _codeError(response.code, null);

  static MailException _codeError(int? code, Object? cause) {
    if (code == 535 || code == 534 || code == 530) {
      return MailException(
        MailErrorKind.invalidCredentials,
        '邮箱拒绝了登录，请检查密码或客户端授权码',
        cause: cause,
      );
    }
    if (code == 552 || code == 523 || code == 524) {
      return _tooLarge(cause: cause);
    }
    if (code == 550 || code == 551 || code == 553 || code == 554) {
      return MailException(
        MailErrorKind.rejected,
        '邮件被服务器拒绝，请检查收件地址',
        cause: cause,
      );
    }
    return MailException(
      MailErrorKind.protocol,
      '邮件服务器拒绝了本次发送',
      cause: cause,
    );
  }

  static MailException _tooLarge({Object? cause}) => MailException(
    MailErrorKind.tooLarge,
    '邮件过大，请减少附件后再发送',
    cause: cause,
  );

  static MailException _protocol() => const MailException(
    MailErrorKind.protocol,
    '邮件服务器拒绝了本次发送',
  );

  static Future<void> _quitQuietly(mail.SmtpClient client) async {
    try {
      await client.quit().timeout(const Duration(seconds: 5));
    } on Object {
      // 连接可能已经断开。
    }
    try {
      await client.disconnect();
    } on Object {
      // 同上。
    }
  }
}
