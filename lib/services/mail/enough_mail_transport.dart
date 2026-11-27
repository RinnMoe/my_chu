import 'dart:async';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;

import 'mail_config.dart';
import 'mail_error.dart';
import 'mail_mime.dart';
import 'mail_mime_decode.dart';
import 'mail_models.dart';
import 'mail_transport.dart';
import 'mail_uid_index.dart';

/// `enough_mail` 的唯一入口。
///
/// 该文件负责把协议异常、超时、字符集与 BODY 段细节收敛成 [MailException]，
/// 其余代码不直接依赖 `enough_mail` 类型。
class EnoughMailTransport implements MailTransport {
  const EnoughMailTransport();

  static const maxBodyBytes = 10 * 1024 * 1024;
  static const maxAttachmentBytes = 50 * 1024 * 1024;
  static const maxBodyChars = 2 * 1024 * 1024;
  static const maxInlineImages = 10;
  static const maxInlineImageBytes = 512 * 1024;

  static const _headerFetchDefinition =
      '(UID FLAGS BODYSTRUCTURE '
      'BODY.PEEK[HEADER.FIELDS (SUBJECT FROM TO CC DATE MESSAGE-ID CONTENT-TYPE)])';

  @override
  Future<MailConnection> connect(
    MailAccountConfig config,
    String secret,
  ) async {
    final client = mail.ImapClient(
      isLogEnabled: false,
      defaultResponseTimeout: const Duration(seconds: 20),
    );
    try {
      await client
          .connectToServer(
            config.imapHost,
            config.imapPort,
            isSecure: config.imapSecurity == MailSecurity.ssl,
            timeout: const Duration(seconds: 15),
          )
          .timeout(const Duration(seconds: 18));
      if (config.imapSecurity == MailSecurity.starttls) {
        await client.startTls().timeout(const Duration(seconds: 15));
      }
      await client
          .login(config.email, secret)
          .timeout(const Duration(seconds: 20));
      return _EnoughMailConnection(client);
    } on mail.ImapException catch (error) {
      await _closeQuietly(client);
      if (_looksLikeAuthFailure(error)) {
        throw MailException.invalidCredentials();
      }
      throw MailException(
        MailErrorKind.protocol,
        '无法完成邮箱登录，请稍后重试',
        cause: error,
      );
    } catch (error) {
      await _closeQuietly(client);
      throw MailException.fromError(error);
    }
  }

  /// 只识别 IMAP 认证失败的协议标记，不对任意异常文本做分类。
  static bool _looksLikeAuthFailure(mail.ImapException error) {
    final text = (error.message ?? '').toUpperCase();
    return text.contains('AUTHENTICATIONFAILED') ||
        text.contains('AUTHENTICATION FAILED') ||
        text.contains('LOGIN FAILED') ||
        text.contains('INVALID CREDENTIALS');
  }

  static Future<void> _closeQuietly(mail.ImapClient client) async {
    try {
      await client.logout().timeout(const Duration(seconds: 3));
    } catch (_) {
      // 连接可能已经断开，忽略关闭失败。
    }
    try {
      await client.disconnect();
    } catch (_) {
      // 同上。
    }
  }
}

class _EnoughMailConnection implements MailConnection {
  _EnoughMailConnection(this._client);

  final mail.ImapClient _client;
  final Map<String, mail.Mailbox> _mailboxes = {};
  final Map<String, MailUidIndex> _uidIndex = {};

  @override
  Future<List<MailFolder>> listFolders() async {
    await _loadMailboxes();

    final folders = [
      for (final box in _mailboxes.values)
        MailFolder(
          path: box.path,
          name: box.name,
          role: _roleFor(box),
          uidValidity: box.uidValidity,
        ),
    ]..sort(_compareFolders);

    final statusTargets = <MailFolder>[
      for (final folder in folders)
        if (folder.role != MailFolderRole.other) folder,
    ];
    for (final folder in folders) {
      if (statusTargets.length >= 8) break;
      if (folder.role == MailFolderRole.other) statusTargets.add(folder);
    }

    final unread = <String, int>{};
    final validities = <String, int>{};
    for (final folder in statusTargets.take(8)) {
      final box = _mailboxes[folder.path];
      if (box == null) continue;
      try {
        final status = await _guard(
          () => _client.statusMailbox(box, [
            mail.StatusFlags.unseen,
            mail.StatusFlags.uidValidity,
          ]),
        );
        unread[folder.path] = status.messagesUnseen;
        final validity = status.uidValidity;
        if (validity != null) validities[folder.path] = validity;
      } catch (_) {
        // 单个文件夹状态失败不影响整个列表。
      }
    }

    return [
      for (final folder in folders)
        folder.copyWith(
          unread: unread[folder.path] ?? folder.unread,
          uidValidity: validities[folder.path],
        ),
    ];
  }

  @override
  Future<MailPage> fetchHeaders(
    String folderPath, {
    int? beforeUid,
    int limit = 20,
  }) async {
    final box = await _select(folderPath);
    final index = await _ensureUidIndex(box, folderPath);
    final slice = index.slice(beforeUid: beforeUid, limit: limit);
    if (slice == null) return MailPage.empty;

    final sequence = mail.MessageSequence.fromIds(slice.uids, isUid: true);
    final result = await _guard(
      () => _client.uidFetchMessages(
        sequence,
        EnoughMailTransport._headerFetchDefinition,
      ),
    );
    final headers = [
      for (final message in result.messages)
        if ((message.uid ?? 0) > 0) _toHeader(message),
    ]..sort((a, b) => b.uid.compareTo(a.uid));

    return MailPage(
      items: headers,
      nextBeforeUid: slice.nextBeforeUid,
      hasMore: slice.hasMore,
    );
  }

  /// 只做 LIST，不查询各文件夹 STATUS；写副本与文件夹列表的公共前置。
  Future<void> _loadMailboxes() async {
    final boxes = await _guard(() => _client.listMailboxes(recursive: true));
    _mailboxes.clear();
    for (final box in boxes) {
      if (box.flags.contains(mail.MailboxFlag.noSelect)) continue;
      _mailboxes[box.path] = box;
    }
  }

  /// 文件夹真实 UID 列表；首次或服务器状态变化时重新 SEARCH。
  Future<MailUidIndex> _ensureUidIndex(
    mail.Mailbox box,
    String folderPath,
  ) async {
    final cached = _uidIndex[folderPath];
    if (cached != null &&
        !cached.isStale(
          uidValidity: box.uidValidity,
          uidNext: box.uidNext,
          messagesExists: box.messagesExists,
        )) {
      return cached;
    }

    final search = await _guard(
      () => _client.uidSearchMessages(searchCriteria: 'ALL'),
    );
    final uids = search.matchingSequence?.toList() ?? const <int>[];
    final index = MailUidIndex(
      uidValidity: box.uidValidity,
      uidsAscending: uids,
    );
    _uidIndex[folderPath] = index;
    return index;
  }

  @override
  Future<MailBody> fetchBody(String folderPath, int uid) async {
    await _select(folderPath);
    final sequence = mail.MessageSequence.fromId(uid, isUid: true);
    final result = await _guard(
      () => _client.uidFetchMessages(
        sequence,
        '(UID FLAGS RFC822.SIZE BODY.PEEK[])',
      ),
    );
    final message = _first(result.messages);
    if (message == null) {
      throw const MailException(MailErrorKind.protocol, '邮件不存在或已被删除');
    }
    if ((message.size ?? 0) > EnoughMailTransport.maxBodyBytes) {
      throw MailException.tooLarge();
    }

    var text = message.decodeTextPlainPart();
    var html = message.decodeTextHtmlPart();
    var truncated = false;
    const maxChars = EnoughMailTransport.maxBodyChars;
    if (text != null && text.length > maxChars) {
      text = text.substring(0, maxChars);
      truncated = true;
    }
    if (html != null && html.length > maxChars) {
      html = html.substring(0, maxChars);
      truncated = true;
    }

    return MailBody(
      text: text,
      html: html,
      attachments: _attachments(message),
      inlineImages: _inlineImages(message),
      truncated: truncated,
    );
  }

  @override
  Future<Uint8List> downloadAttachment(
    String folderPath,
    int uid,
    String fetchId, {
    int knownSize = 0,
  }) async {
    if (knownSize > EnoughMailTransport.maxAttachmentBytes) {
      throw MailException.tooLarge();
    }
    await _select(folderPath);
    final sequence = mail.MessageSequence.fromId(uid, isUid: true);

    final partial = await _guard(
      () => _client.uidFetchMessages(
        sequence,
        '(UID BODYSTRUCTURE BODY.PEEK[$fetchId])',
      ),
    );
    Uint8List? bytes;
    final partialMessage = _first(partial.messages);
    // BODYSTRUCTURE 让 enough_mail 能把 Content-Transfer-Encoding 复制到
    // 单独下载的 part 上；缺少时按原文返回 base64，必须回退完整 FETCH。
    if (partialMessage?.body != null) {
      bytes = mailPartBytes(partialMessage!, fetchId);
    }

    if (bytes == null) {
      final full = await _guard(
        () => _client.uidFetchMessages(
          sequence,
          '(UID FLAGS RFC822.SIZE BODY.PEEK[])',
        ),
      );
      final message = _first(full.messages);
      if ((message?.size ?? 0) > EnoughMailTransport.maxAttachmentBytes * 2) {
        throw MailException.tooLarge();
      }
      bytes = message == null ? null : mailPartBytes(message, fetchId);
    }

    if (bytes == null) {
      throw const MailException(MailErrorKind.malformed, '附件内容无法读取');
    }
    if (bytes.length > EnoughMailTransport.maxAttachmentBytes) {
      throw MailException.tooLarge();
    }
    return bytes;
  }

  @override
  Future<void> setSeen(String folderPath, int uid, bool seen) async {
    await _select(folderPath);
    final sequence = mail.MessageSequence.fromId(uid, isUid: true);
    await _guard(
      () => _client.uidStore(
        sequence,
        [mail.MessageFlags.seen],
        action: seen ? mail.StoreAction.add : mail.StoreAction.remove,
        silent: true,
      ),
    );
  }

  @override
  Future<int> unreadCount(String folderPath) async {
    var box = _mailboxes[folderPath];
    if (box == null && folderPath.toUpperCase() == 'INBOX') {
      // 焦点只需要 INBOX 未读数，避免为一次 STATUS 走完整 LIST。
      box = mail.Mailbox(
        encodedName: 'INBOX',
        encodedPath: 'INBOX',
        flags: [mail.MailboxFlag.inbox],
        pathSeparator: '/',
      );
    }
    if (box == null) {
      await listFolders();
      box = _mailboxes[folderPath];
    }
    final target = box;
    if (target == null) return 0;
    final status = await _guard(
      () => _client.statusMailbox(target, [mail.StatusFlags.unseen]),
    );
    return status.messagesUnseen;
  }

  @override
  Future<bool> appendToSent(String messageText) async {
    if (messageText.isEmpty) return false;
    // 文件夹由用户或服务器命名，只有 LIST 之后才能确定「已发送」路径。
    // 只做 LIST、不查 STATUS：写副本不需要未读数，避免拖慢发送。
    if (_mailboxes.isEmpty) {
      await _loadMailboxes();
    }
    mail.Mailbox? sentBox;
    for (final box in _mailboxes.values) {
      if (_roleFor(box) == MailFolderRole.sent) {
        sentBox = box;
        break;
      }
    }
    final target = sentBox;
    if (target == null) return false;
    await _guard(
      () => _client.appendMessageText(
        messageText,
        flags: const [r'\Seen'],
        targetMailbox: target,
      ),
      timeout: const Duration(seconds: 60),
    );
    _uidIndex.remove(target.path);
    return true;
  }

  @override
  Future<void> close() => EnoughMailTransport._closeQuietly(_client);

  Future<mail.Mailbox> _select(String folderPath) async {
    final existing = _mailboxes[folderPath];
    if (existing != null) {
      return _guard(() => _client.selectMailbox(existing));
    }
    return _guard(() => _client.selectMailboxByPath(folderPath));
  }

  MailHeader _toHeader(mail.MimeMessage message) {
    final from = message.from;
    final to = message.to;
    return MailHeader(
      uid: message.uid ?? 0,
      subject: message.decodeSubject() ?? message.envelope?.subject ?? '',
      from: from != null && from.isNotEmpty ? _toAddress(from.first) : null,
      to: [
        for (final address in to ?? const <mail.MailAddress>[])
          _toAddress(address),
      ],
      cc: [
        for (final address in message.cc ?? const <mail.MailAddress>[])
          _toAddress(address),
      ],
      date: message.decodeDate() ?? message.envelope?.date,
      isRead: message.isSeen,
      hasAttachments: _hasAttachments(message),
      messageId:
          message.getHeaderValue('message-id') ?? message.envelope?.messageId,
    );
  }

  List<MailAttachment> _attachments(mail.MimeMessage message) {
    try {
      return [
        for (final info in message.findContentInfo(
          disposition: mail.ContentDisposition.attachment,
        ))
          MailAttachment(
            fetchId: info.fetchId,
            fileName: _fileName(info),
            mimeType: info.mediaType?.text ?? 'application/octet-stream',
            size: info.size ?? 0,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 从已下载的完整正文中解码 cid 内嵌图片，不额外发起网络请求。
  Map<String, Uint8List> _inlineImages(mail.MimeMessage message) {
    final result = <String, Uint8List>{};
    try {
      for (final info in message.findContentInfo(
        disposition: mail.ContentDisposition.inline,
      )) {
        if (result.length >= EnoughMailTransport.maxInlineImages) break;
        if (!info.isImage) continue;
        final cid = normalizeMailCid(info.cid ?? '');
        if (cid.isEmpty) continue;
        if ((info.size ?? 0) > EnoughMailTransport.maxInlineImageBytes) {
          continue;
        }
        final bytes = mailPartBytes(message, info.fetchId);
        if (bytes == null || bytes.isEmpty) continue;
        if (bytes.length > EnoughMailTransport.maxInlineImageBytes) continue;
        result[cid] = bytes;
      }
    } catch (_) {
      // 单张内嵌图失败不影响正文。
    }
    return result;
  }

  static String _fileName(mail.ContentInfo info) {
    final name = info.fileName?.trim() ?? '';
    return name.isEmpty ? '附件' : name;
  }

  static bool _hasAttachments(mail.MimeMessage message) {
    try {
      return message.hasAttachments() ||
          message.hasAttachmentsOrInlineNonTextualParts();
    } catch (_) {
      return false;
    }
  }

  static MailAddress _toAddress(mail.MailAddress address) =>
      MailAddress(name: address.personalName, address: address.email);

  static MailFolderRole _roleFor(mail.Mailbox box) {
    return resolveMailFolderRole(
      name: box.name,
      isInbox: box.isInbox,
      isSent: box.isSent,
      isDrafts: box.isDrafts,
      isTrash: box.isTrash,
      isJunk: box.isJunk,
      isArchive: box.isArchive,
    );
  }

  static int _compareFolders(MailFolder left, MailFolder right) {
    final role = _roleOrder(left.role).compareTo(_roleOrder(right.role));
    if (role != 0) return role;
    return left.name.compareTo(right.name);
  }

  static int _roleOrder(MailFolderRole role) => switch (role) {
    MailFolderRole.inbox => 0,
    MailFolderRole.sent => 1,
    MailFolderRole.drafts => 2,
    MailFolderRole.archive => 3,
    MailFolderRole.junk => 4,
    MailFolderRole.trash => 5,
    MailFolderRole.other => 6,
  };

  Future<T> _guard<T>(
    Future<T> Function() action, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      return await action().timeout(timeout);
    } on MailException {
      rethrow;
    } on mail.ImapException catch (error) {
      if (EnoughMailTransport._looksLikeAuthFailure(error)) {
        throw MailException.invalidCredentials();
      }
      throw MailException(MailErrorKind.protocol, '邮件服务器拒绝了本次操作', cause: error);
    } catch (error) {
      throw MailException.fromError(error);
    }
  }

  static T? _first<T>(List<T> items) => items.isEmpty ? null : items.first;
}
