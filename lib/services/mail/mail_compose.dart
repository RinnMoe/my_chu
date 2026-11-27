/// 写信的纯业务模型与预填规则。
///
/// 不依赖 Flutter 与 `enough_mail`，只做地址解析、校验、引用文本拼装，
/// 便于离线测试；SMTP 细节留在 `enough_mail_sender.dart`。
library;

import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'mail_models.dart';

/// 写信的本地限制。附件只保留在内存中，不落盘、不进入缓存。
class MailComposeLimits {
  static const maxRecipients = 50;
  static const maxAttachments = 10;
  static const maxAttachmentBytes = 10 * 1024 * 1024;
  static const maxTotalAttachmentBytes = 15 * 1024 * 1024;
  static const maxBodyChars = 100000;
  static const maxSubjectChars = 500;
  static const maxAttachmentNameChars = 120;
}

/// 待发送的附件。
class OutgoingAttachment {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  OutgoingAttachment({
    required String name,
    this.mimeType = 'application/octet-stream',
    required this.bytes,
  }) : name = sanitizeMailFileName(name);

  int get size => bytes.length;
}

/// 一封待发送的纯文本邮件。
class MailDraft {
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final String text;
  final List<OutgoingAttachment> attachments;

  /// 回复时用于 `In-Reply-To` / `References`，不携带会话数据。
  final String? inReplyTo;

  const MailDraft({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.text = '',
    this.attachments = const [],
    this.inReplyTo,
  });

  bool get hasRecipients => to.isNotEmpty || cc.isNotEmpty || bcc.isNotEmpty;

  int get recipientCount => to.length + cc.length + bcc.length;

  int get totalAttachmentBytes {
    var total = 0;
    for (final attachment in attachments) {
      total += attachment.size;
    }
    return total;
  }

  /// 主题中的换行会破坏 header 结构，发送前统一清理。
  String get sanitizedSubject => sanitizeMailHeaderText(subject);

  String? get validationError {
    if (!hasRecipients) return '请填写收件人';
    if (recipientCount > MailComposeLimits.maxRecipients) {
      return '收件人过多，请减少后再发送';
    }
    if (attachments.length > MailComposeLimits.maxAttachments) {
      return '附件数量过多，最多 ${MailComposeLimits.maxAttachments} 个';
    }
    if (totalAttachmentBytes > MailComposeLimits.maxTotalAttachmentBytes) {
      return '附件总大小超过 15 MB，请减少附件';
    }
    for (final attachment in attachments) {
      if (attachment.size > MailComposeLimits.maxAttachmentBytes) {
        return '单个附件超过 10 MB，请压缩后再发送';
      }
    }
    if (text.trim().isEmpty && attachments.isEmpty) {
      return '请输入正文或添加附件';
    }
    if (text.length > MailComposeLimits.maxBodyChars) {
      return '正文过长，请精简后再发送';
    }
    if (sanitizedSubject.length > MailComposeLimits.maxSubjectChars) {
      return '主题过长，请精简后再发送';
    }
    return null;
  }
}

const _mailAddressPattern = r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$';
final _mailAddressRegExp = RegExp(_mailAddressPattern);
final _controlCharacters = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
final _angleAddress = RegExp(r'^(.*?)<([^<>]+)>$');
final _blockTags = {
  'article',
  'blockquote',
  'div',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tr',
  'ul',
};

/// 清理会破坏邮件 header 的字符（CR/LF 与控制字符）。
String sanitizeMailHeaderText(String value) {
  return value
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(_controlCharacters, '')
      .trim();
}

/// 附件名只保留文件名部分，避免路径与 header 注入。
String sanitizeMailFileName(String value) {
  final clean = sanitizeMailHeaderText(value);
  final isDirectoryName = clean.endsWith('/') || clean.endsWith(r'\');
  final segments =
      clean
          .split(RegExp(r'[\\/]'))
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
  if (isDirectoryName || segments.isEmpty) return '附件';
  var name = segments.last;
  if (name.runes.length > MailComposeLimits.maxAttachmentNameChars) {
    // 按 rune 截断，避免把 emoji 等代理对切成孤立字符。
    name = String.fromCharCodes(
      name.runes.take(MailComposeLimits.maxAttachmentNameChars),
    );
  }
  return name.isEmpty ? '附件' : name;
}

/// 解析一行地址输入，支持 `姓名 <地址>`。
///
/// 非法地址抛 [FormatException]，由页面转成字段错误。
MailAddress parseMailRecipient(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    throw const FormatException('收件地址格式不正确');
  }
  final match = _angleAddress.firstMatch(value);
  String? name;
  var address = value;
  if (match != null) {
    name = _unquoteName(match.group(1) ?? '');
    address = (match.group(2) ?? '').trim();
  }
  if (!_mailAddressRegExp.hasMatch(address)) {
    throw const FormatException('收件地址格式不正确');
  }
  return MailAddress(
    name: (name == null || name.isEmpty) ? null : name,
    address: address,
  );
}

/// 解析多个收件地址：逗号、分号、顿号、换行与中文标点都视为分隔符。
List<MailAddress> parseMailRecipientList(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  final parts = <String>[];
  final buffer = StringBuffer();
  var inAngle = false;
  var inQuote = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == '<') inAngle = true;
    if (char == '>') inAngle = false;
    if (char == '"') inQuote = !inQuote;
    final isSeparator =
        !inAngle &&
        !inQuote &&
        (char == ',' ||
            char == ';' ||
            char == '，' ||
            char == '；' ||
            char == '、' ||
            char == '\n' ||
            char == '\r');
    if (isSeparator) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());

  final seen = <String>{};
  final result = <MailAddress>[];
  for (final part in parts) {
    final value = part.trim();
    if (value.isEmpty) continue;
    final address = parseMailRecipient(value);
    if (seen.add(address.address.toLowerCase())) {
      result.add(address);
    }
  }
  return result;
}

String _unquoteName(String raw) {
  var name = raw.trim();
  if (name.length > 1 && name.startsWith('"') && name.endsWith('"')) {
    name = name.substring(1, name.length - 1);
  }
  return name.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 回信主题：已有 `Re:` / `回复：` 前缀时不重复添加。
String replySubject(String subject) {
  final clean = sanitizeMailHeaderText(subject);
  final lower = clean.toLowerCase();
  if (lower.startsWith('re:') ||
      clean.startsWith('回复：') ||
      clean.startsWith('回复:')) {
    return clean;
  }
  return clean.isEmpty ? 'Re:' : 'Re: $clean';
}

/// 转发主题：已有 `Fwd:` / `Fw:` / `转发：` 前缀时不重复添加。
String forwardSubject(String subject) {
  final clean = sanitizeMailHeaderText(subject);
  final lower = clean.toLowerCase();
  if (lower.startsWith('fwd:') ||
      lower.startsWith('fw:') ||
      clean.startsWith('转发：') ||
      clean.startsWith('转发:')) {
    return clean;
  }
  return clean.isEmpty ? 'Fwd:' : 'Fwd: $clean';
}

/// 回复全部是否有额外收件人：原 to/cc 中除自己与发件人外还有人。
bool hasReplyAllRecipients(MailHeader header, String selfAddress) {
  final self = selfAddress.trim().toLowerCase();
  final sender = header.from?.address.trim().toLowerCase();
  for (final address in [...header.to, ...header.cc]) {
    final key = address.address.trim().toLowerCase();
    if (key.isEmpty || key == self || key == sender) continue;
    return true;
  }
  return false;
}

/// 构造回复草稿。
///
/// [originalText] 是已转成纯文本的原文；HTML 邮件由页面先调用
/// [mailPlainTextFromHtml] 转换。
MailDraft buildReplyDraft({
  required MailHeader header,
  required String selfAddress,
  required String originalText,
  bool replyAll = false,
}) {
  final sender = header.from;
  final self = selfAddress.trim().toLowerCase();
  final to = <MailAddress>[
    if (sender != null && sender.address.trim().isNotEmpty) sender,
  ];
  final cc = <MailAddress>[];
  if (replyAll) {
    final seen = <String>{
      if (sender != null) sender.address.trim().toLowerCase(),
      if (self.isNotEmpty) self,
    };
    for (final address in [...header.to, ...header.cc]) {
      final key = address.address.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      cc.add(address);
    }
  }
  final headerLine = _replyHeaderLine(header);
  final quoted = quoteMailText(originalText);
  final body = StringBuffer('\n\n')..write(headerLine);
  if (quoted.isNotEmpty) {
    body
      ..write('\n')
      ..write(quoted);
  }
  return MailDraft(
    to: to,
    cc: cc,
    subject: replySubject(header.subject),
    text: body.toString(),
    inReplyTo: cleanMailMessageId(header.messageId),
  );
}

/// 构造转发草稿：收件人留空，由用户填写。
MailDraft buildForwardDraft({
  required MailHeader header,
  required String originalText,
}) {
  final lines = <String>[
    '',
    '',
    '---------- 转发邮件 ----------',
    '发件人：${header.from?.displayName ?? '未知发件人'}',
    if (header.date != null) '发送时间：${_quoteDate(header.date)}',
    if (header.to.isNotEmpty)
      '收件人：${header.to.map((address) => address.displayName).join('、')}',
    '主题：${header.displaySubject}',
    '',
  ];
  final text = originalText.trim();
  if (text.isNotEmpty) lines.addAll(text.split('\n'));
  return MailDraft(
    subject: forwardSubject(header.subject),
    text: lines.join('\n'),
  );
}

/// 引用原文：逐行加 `> `。
String quoteMailText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  return trimmed
      .split('\n')
      .map((line) => line.isEmpty ? '>' : '> $line')
      .join('\n');
}

/// 把 HTML 正文转成可引用的纯文本。
///
/// 只处理常见排版标签；脚本、样式与表单内容直接丢弃。
String mailPlainTextFromHtml(String html) {
  if (html.trim().isEmpty) return '';
  final document = html_parser.parse(html);
  for (final element in document.querySelectorAll(
    'script,style,head,title,noscript,iframe,object',
  )) {
    element.remove();
  }
  final body = document.body;
  if (body == null) return '';
  final buffer = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    final block = _blockTags.contains(tag);
    if (block) buffer.write('\n');
    for (final child in node.nodes) {
      walk(child);
    }
    if (block) buffer.write('\n');
  }

  walk(body);
  var text = buffer.toString().replaceAll('\u00A0', ' ');
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String? cleanMailMessageId(String? value) {
  final clean = sanitizeMailHeaderText(value ?? '');
  if (clean.isEmpty) return null;
  if (clean.contains('<') && clean.contains('>')) return clean;
  return '<$clean>';
}

String _replyHeaderLine(MailHeader header) {
  final who = header.from?.displayName ?? '发件人';
  final date = _quoteDate(header.date);
  return date.isEmpty ? '在 $who 的来信中写道：' : '在 $date，$who 写道：';
}

String _quoteDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
