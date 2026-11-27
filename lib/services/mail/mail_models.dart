/// 校园邮箱的宿主层数据模型。
///
/// 这些类型只描述邮件内容，不包含凭证、连接或协议对象；应用层只消费这些
/// 不可变结果。
library;

import 'dart:typed_data';

enum MailFolderRole { inbox, sent, drafts, trash, junk, archive, other }

class MailFolder {
  final String path;
  final String name;
  final MailFolderRole role;
  final int unread;
  final int? uidValidity;

  const MailFolder({
    required this.path,
    required this.name,
    this.role = MailFolderRole.other,
    this.unread = 0,
    this.uidValidity,
  });

  MailFolder copyWith({
    int? unread,
    int? uidValidity,
  }) {
    return MailFolder(
      path: path,
      name: name,
      role: role,
      unread: unread ?? this.unread,
      uidValidity: uidValidity ?? this.uidValidity,
    );
  }
}

/// 文件夹角色识别：优先使用 IMAP special-use 标志，名称只作兜底。
MailFolderRole resolveMailFolderRole({
  required String name,
  bool isInbox = false,
  bool isSent = false,
  bool isDrafts = false,
  bool isTrash = false,
  bool isJunk = false,
  bool isArchive = false,
}) {
  if (isInbox) return MailFolderRole.inbox;
  if (isSent) return MailFolderRole.sent;
  if (isDrafts) return MailFolderRole.drafts;
  if (isTrash) return MailFolderRole.trash;
  if (isJunk) return MailFolderRole.junk;
  if (isArchive) return MailFolderRole.archive;

  final normalized = name.trim().toLowerCase();
  if (normalized == 'inbox' || normalized == '收件箱') {
    return MailFolderRole.inbox;
  }
  if (normalized.contains('已发送') ||
      normalized == 'sent' ||
      normalized.startsWith('sent ')) {
    return MailFolderRole.sent;
  }
  if (normalized.contains('草稿') || normalized == 'drafts') {
    return MailFolderRole.drafts;
  }
  if (normalized.contains('已删除') ||
      normalized.contains('废纸篓') ||
      normalized == 'trash' ||
      normalized == 'deleted messages') {
    return MailFolderRole.trash;
  }
  if (normalized.contains('垃圾') ||
      normalized == 'junk' ||
      normalized == 'spam') {
    return MailFolderRole.junk;
  }
  if (normalized.contains('归档') || normalized == 'archive') {
    return MailFolderRole.archive;
  }
  return MailFolderRole.other;
}

class MailAddress {
  final String? name;
  final String address;

  const MailAddress({this.name, required this.address});

  String get displayName {
    final value = name?.trim() ?? '';
    return value.isEmpty ? address : value;
  }

  /// 列表头像使用的首字符，兼容中文与英文。
  String get initial {
    final value = displayName.trim();
    if (value.isEmpty) return '?';
    return value.substring(0, 1).toUpperCase();
  }
}

class MailHeader {
  final int uid;
  final String subject;
  final MailAddress? from;
  final List<MailAddress> to;

  /// 抄送地址。旧缓存没有该字段时按空列表读取。
  final List<MailAddress> cc;
  final DateTime? date;
  final bool isRead;
  final bool hasAttachments;
  final String? messageId;

  const MailHeader({
    required this.uid,
    required this.subject,
    required this.from,
    required this.to,
    this.cc = const [],
    required this.date,
    required this.isRead,
    required this.hasAttachments,
    required this.messageId,
  });

  String get displaySubject => subject.trim().isEmpty ? '（无主题）' : subject;

  MailHeader copyWith({bool? isRead}) {
    return MailHeader(
      uid: uid,
      subject: subject,
      from: from,
      to: to,
      cc: cc,
      date: date,
      isRead: isRead ?? this.isRead,
      hasAttachments: hasAttachments,
      messageId: messageId,
    );
  }
}

class MailAttachment {
  /// IMAP BODY 段标识，用于按需下载单个附件。
  final String fetchId;
  final String fileName;
  final String mimeType;
  final int size;

  const MailAttachment({
    required this.fetchId,
    required this.fileName,
    required this.mimeType,
    required this.size,
  });
}

class MailBody {
  final String? text;
  final String? html;
  final List<MailAttachment> attachments;

  /// cid 内嵌图片，仅存在于本次正文加载；不写入磁盘缓存。
  final Map<String, Uint8List> inlineImages;
  final bool truncated;

  const MailBody({
    this.text,
    this.html,
    this.attachments = const [],
    this.inlineImages = const {},
    this.truncated = false,
  });
}

class MailPage {
  final List<MailHeader> items;
  final int? nextBeforeUid;
  final bool hasMore;

  const MailPage({
    required this.items,
    required this.nextBeforeUid,
    required this.hasMore,
  });

  static const empty = MailPage(items: [], nextBeforeUid: null, hasMore: false);
}

/// SMTP 发送成功后交给 IMAP 追加副本的已渲染邮件。
///
/// [messageText] 是完整的 RFC 5322 文本，已剔除密送头；只在内存中短暂存在。
class MailSendReceipt {
  final String messageText;
  final int size;

  const MailSendReceipt({required this.messageText, required this.size});
}

/// 一次发送的可见结果。
///
/// [sentCopyStored] 只表示服务器「已发送」副本是否写入成功，不代表发送失败。
class MailSendResult {
  final bool sentCopyStored;

  const MailSendResult({required this.sentCopyStored});
}
