import 'dart:async';
import 'dart:io';

import '../failure_details.dart';

enum MailErrorKind {
  notConfigured,
  invalidCredentials,
  connection,
  timeout,
  tls,
  protocol,
  rejected,
  malformed,
  tooLarge,
  unknown,
}

/// 邮件层的类型化失败。
///
/// 面向用户的文案只描述下一步动作，不携带服务器原文、地址或异常对象。
class MailException implements Exception, ClassifiedFailure {
  final MailErrorKind kind;
  final String userMessage;
  final Object? cause;

  const MailException(this.kind, this.userMessage, {this.cause});

  bool get isRetryable =>
      kind == MailErrorKind.connection ||
      kind == MailErrorKind.timeout ||
      kind == MailErrorKind.protocol;

  @override
  FailureReason get failureReason => switch (kind) {
    MailErrorKind.notConfigured => FailureReason.invalidState,
    MailErrorKind.invalidCredentials => FailureReason.authentication,
    MailErrorKind.connection => FailureReason.connection,
    MailErrorKind.timeout => FailureReason.timeout,
    MailErrorKind.tls => FailureReason.tls,
    MailErrorKind.protocol => FailureReason.malformedResponse,
    MailErrorKind.rejected => FailureReason.businessRejected,
    MailErrorKind.malformed => FailureReason.malformedResponse,
    MailErrorKind.tooLarge => FailureReason.businessRejected,
    MailErrorKind.unknown => FailureReason.unexpected,
  };

  static MailException notConfigured() =>
      const MailException(MailErrorKind.notConfigured, '请先完成邮箱设置');

  static MailException invalidCredentials() =>
      const MailException(MailErrorKind.invalidCredentials, '密码不正确，请重新输入');

  static MailException tooLarge() =>
      const MailException(MailErrorKind.tooLarge, '邮件或附件过大，请在网页版查看');

  /// 按异常类型映射，不解析异常文本。
  static MailException fromError(Object error) {
    if (error is MailException) return error;
    if (error is TimeoutException) {
      return MailException(
        MailErrorKind.timeout,
        '连接邮件服务器超时，请稍后重试',
        cause: error,
      );
    }
    if (error is TlsException || error is HandshakeException) {
      return MailException(
        MailErrorKind.tls,
        '邮件服务器证书校验失败，请检查网络环境',
        cause: error,
      );
    }
    if (error is SocketException) {
      return MailException(
        MailErrorKind.connection,
        '无法连接邮件服务器，请检查网络后重试',
        cause: error,
      );
    }
    if (error is FormatException) {
      return MailException(MailErrorKind.malformed, '邮件内容无法解析', cause: error);
    }
    return MailException(MailErrorKind.unknown, '邮件操作失败，请稍后重试', cause: error);
  }

  @override
  String toString() => 'MailException(${kind.name})';
}
