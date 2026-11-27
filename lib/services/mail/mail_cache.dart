import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'mail_models.dart';

class MailCacheStats {
  final int bytes;
  final int files;

  const MailCacheStats({required this.bytes, required this.files});

  static const empty = MailCacheStats(bytes: 0, files: 0);
}

class CachedMailFolders {
  final List<MailFolder> folders;
  final DateTime fetchedAt;

  const CachedMailFolders({required this.folders, required this.fetchedAt});
}

class CachedMailHeaders {
  final List<MailHeader> items;
  final DateTime fetchedAt;

  const CachedMailHeaders({required this.items, required this.fetchedAt});
}

/// 首页焦点使用的未读摘要，与 folders.json 完全隔离。
class FocusUnread {
  final int unread;
  final DateTime? checkedAt;

  const FocusUnread({required this.unread, this.checkedAt});
}

/// 邮件本地缓存。
///
/// 目录位于应用缓存目录，不进入系统备份；目录名使用邮箱哈希，不落明文地址。
/// 所有读写失败都被吞掉，缓存不可用不应影响收发。
class MailCache {
  MailCache({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? _defaultRoot;

  static const foldersTtl = Duration(hours: 1);
  static const headersTtl = Duration(minutes: 30);
  static const bodyTtl = Duration(days: 7);
  static const focusUnreadTtl = Duration(hours: 24);
  static const attachmentTtl = Duration(days: 7);
  static const maxAttachmentBytes = 50 * 1024 * 1024;

  final Future<Directory> Function() _rootProvider;

  static Future<Directory> _defaultRoot() async {
    Directory base;
    try {
      base = await getApplicationCacheDirectory();
    } on Object {
      base = await getApplicationSupportDirectory();
    }
    return Directory('${base.path}${Platform.pathSeparator}mail');
  }

  Future<Directory> _accountDir(String email) async {
    final root = await _rootProvider();
    return Directory('${root.path}${Platform.pathSeparator}${_hash(email)}');
  }

  Future<Directory> _ensureDir(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> writeFolders(
    String email,
    List<MailFolder> folders, {
    DateTime? now,
  }) async {
    try {
      final directory = await _accountDir(email);
      await _ensureDir(directory.path);
      final file = File(
        '${directory.path}${Platform.pathSeparator}folders.json',
      );

      final previous = await _readFoldersRaw(file);
      if (previous != null) {
        final previousValidity = {
          for (final folder in previous) folder.path: folder.uidValidity,
        };
        for (final folder in folders) {
          final oldValidity = previousValidity[folder.path];
          if (oldValidity != null &&
              folder.uidValidity != null &&
              oldValidity != folder.uidValidity) {
            await _clearFolderCaches(email, folder.path);
          }
        }
      }

      final payload = {
        'schema': 1,
        'fetchedAt': (now ?? DateTime.now()).toIso8601String(),
        'folders': [for (final folder in folders) _folderToJson(folder)],
      };
      await _writeJsonAtomic(file, payload);
    } on Object {
      // 缓存写入失败可忽略。
    }
  }

  Future<CachedMailFolders?> readFolders(
    String email, {
    Duration ttl = foldersTtl,
    DateTime? now,
  }) async {
    try {
      final directory = await _accountDir(email);
      final file = File(
        '${directory.path}${Platform.pathSeparator}folders.json',
      );
      final payload = await _readPayload(file, ttl: ttl, now: now);
      if (payload == null) return null;
      final raw = payload['folders'];
      if (raw is! List) return null;
      final folders = <MailFolder>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final folder = _folderFromJson(Map<String, dynamic>.from(item));
        if (folder != null) folders.add(folder);
      }
      return CachedMailFolders(
        folders: folders,
        fetchedAt: DateTime.parse(payload['fetchedAt'] as String),
      );
    } on Object {
      return null;
    }
  }

  Future<void> writeHeaders(
    String email,
    String folderPath,
    int startUid,
    List<MailHeader> items, {
    DateTime? now,
  }) async {
    try {
      final directory = await _headersDir(email, folderPath);
      await _ensureDir(directory.path);
      final payload = {
        'schema': 1,
        'fetchedAt': (now ?? DateTime.now()).toIso8601String(),
        'items': [for (final item in items) _headerToJson(item)],
      };
      await _writeJsonAtomic(
        File('${directory.path}${Platform.pathSeparator}$startUid.json'),
        payload,
      );
    } on Object {
      // 忽略缓存写入失败。
    }
  }

  Future<CachedMailHeaders?> readHeaders(
    String email,
    String folderPath,
    int startUid, {
    Duration ttl = headersTtl,
    DateTime? now,
  }) async {
    try {
      final directory = await _headersDir(email, folderPath);
      final file = File(
        '${directory.path}${Platform.pathSeparator}$startUid.json',
      );
      final payload = await _readPayload(file, ttl: ttl, now: now);
      if (payload == null) return null;
      final raw = payload['items'];
      if (raw is! List) return null;
      final items = <MailHeader>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final header = _headerFromJson(Map<String, dynamic>.from(item));
        if (header != null) items.add(header);
      }
      return CachedMailHeaders(
        items: items,
        fetchedAt: DateTime.parse(payload['fetchedAt'] as String),
      );
    } on Object {
      return null;
    }
  }

  Future<void> writeBody(
    String email,
    String folderPath,
    int uid,
    MailBody body, {
    DateTime? now,
  }) async {
    try {
      final directory = await _bodyDir(email, folderPath);
      await _ensureDir(directory.path);
      final payload = {
        'schema': 1,
        'fetchedAt': (now ?? DateTime.now()).toIso8601String(),
        'text': body.text,
        'html': body.html,
        'truncated': body.truncated,
        'attachments': [
          for (final attachment in body.attachments)
            _attachmentToJson(attachment),
        ],
      };
      await _writeJsonAtomic(
        File('${directory.path}${Platform.pathSeparator}$uid.json'),
        payload,
      );
    } on Object {
      // 忽略缓存写入失败。
    }
  }

  Future<MailBody?> readBody(
    String email,
    String folderPath,
    int uid, {
    Duration ttl = bodyTtl,
    DateTime? now,
  }) async {
    try {
      final directory = await _bodyDir(email, folderPath);
      final file = File('${directory.path}${Platform.pathSeparator}$uid.json');
      final payload = await _readPayload(file, ttl: ttl, now: now);
      if (payload == null) return null;
      final rawAttachments = payload['attachments'];
      final attachments = <MailAttachment>[];
      if (rawAttachments is List) {
        for (final item in rawAttachments) {
          if (item is! Map) continue;
          final attachment = _attachmentFromJson(
            Map<String, dynamic>.from(item),
          );
          if (attachment != null) attachments.add(attachment);
        }
      }
      return MailBody(
        text: payload['text']?.toString(),
        html: payload['html']?.toString(),
        truncated: payload['truncated'] == true,
        attachments: attachments,
      );
    } on Object {
      return null;
    }
  }

  Future<void> writeAttachment(
    String email,
    String folderPath,
    int uid,
    String fetchId,
    Uint8List bytes,
  ) async {
    try {
      final directory = await _attachmentDir(email, folderPath, uid);
      await _ensureDir(directory.path);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${_hash(fetchId)}',
      );
      await file.writeAsBytes(bytes, flush: true);
      await trimAttachments(email);
    } on Object {
      // 忽略缓存写入失败。
    }
  }

  Future<Uint8List?> readAttachment(
    String email,
    String folderPath,
    int uid,
    String fetchId, {
    Duration ttl = attachmentTtl,
    DateTime? now,
  }) async {
    try {
      final directory = await _attachmentDir(email, folderPath, uid);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${_hash(fetchId)}',
      );
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final current = now ?? DateTime.now();
      if (current.difference(stat.modified) > ttl) {
        await file.delete();
        return null;
      }
      return await file.readAsBytes();
    } on Object {
      return null;
    }
  }

  /// 焦点未读摘要与 folders.json 分离，避免只读 INBOX 时覆盖完整文件夹列表。
  Future<void> writeFocusUnread(
    String email,
    int unread, {
    DateTime? checkedAt,
  }) async {
    try {
      final directory = await _accountDir(email);
      await _ensureDir(directory.path);
      await _writeJsonAtomic(
        File('${directory.path}${Platform.pathSeparator}focus_unread.json'),
        {
          'schema': 1,
          'fetchedAt': (checkedAt ?? DateTime.now()).toIso8601String(),
          'unread': unread,
          'checkedAt': (checkedAt ?? DateTime.now()).toIso8601String(),
        },
      );
    } on Object {
      // 忽略缓存写入失败。
    }
  }

  Future<FocusUnread?> readFocusUnread(
    String email, {
    Duration ttl = focusUnreadTtl,
    DateTime? now,
  }) async {
    try {
      final directory = await _accountDir(email);
      final payload = await _readPayload(
        File('${directory.path}${Platform.pathSeparator}focus_unread.json'),
        ttl: ttl,
        now: now,
      );
      if (payload == null) return null;
      return FocusUnread(
        unread: _asInt(payload['unread']),
        checkedAt: DateTime.tryParse(payload['checkedAt']?.toString() ?? ''),
      );
    } on Object {
      return null;
    }
  }

  /// 清空指定邮箱的全部缓存，登出或换账号时调用。
  Future<void> clear(String email) async {
    try {
      final directory = await _accountDir(email);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on Object {
      // 忽略清理失败。
    }
  }

  Future<MailCacheStats> stats(String email) async {
    try {
      final directory = await _accountDir(email);
      if (!await directory.exists()) return MailCacheStats.empty;
      var bytes = 0;
      var files = 0;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File) continue;
        files++;
        bytes += await entity.length();
      }
      return MailCacheStats(bytes: bytes, files: files);
    } on Object {
      return MailCacheStats.empty;
    }
  }

  /// 附件超过总量上限时按修改时间删除最旧文件。
  Future<void> trimAttachments(String email) async {
    try {
      final directory = await _accountDir(email);
      final attachRoot = Directory(
        '${directory.path}${Platform.pathSeparator}attach',
      );
      if (!await attachRoot.exists()) return;

      final entries = <({File file, DateTime modified, int size})>[];
      var total = 0;
      await for (final entity in attachRoot.list(recursive: true)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        entries.add((file: entity, modified: stat.modified, size: stat.size));
        total += stat.size;
      }
      if (total <= maxAttachmentBytes) return;

      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (total <= maxAttachmentBytes) break;
        try {
          await entry.file.delete();
          total -= entry.size;
        } on Object {
          // 单个文件删除失败时继续尝试下一个。
        }
      }
    } on Object {
      // 忽略裁剪失败。
    }
  }

  Future<Directory> _headersDir(String email, String folderPath) async {
    final account = await _accountDir(email);
    return Directory(
      '${account.path}${Platform.pathSeparator}headers'
      '${Platform.pathSeparator}${_hash(folderPath)}',
    );
  }

  Future<Directory> _bodyDir(String email, String folderPath) async {
    final account = await _accountDir(email);
    return Directory(
      '${account.path}${Platform.pathSeparator}body'
      '${Platform.pathSeparator}${_hash(folderPath)}',
    );
  }

  Future<Directory> _attachmentDir(
    String email,
    String folderPath,
    int uid,
  ) async {
    final account = await _accountDir(email);
    return Directory(
      '${account.path}${Platform.pathSeparator}attach'
      '${Platform.pathSeparator}${_hash(folderPath)}'
      '${Platform.pathSeparator}$uid',
    );
  }

  Future<List<MailFolder>?> _readFoldersRaw(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['folders'];
      if (list is! List) return null;
      final folders = <MailFolder>[];
      for (final item in list) {
        if (item is! Map) continue;
        final folder = _folderFromJson(Map<String, dynamic>.from(item));
        if (folder != null) folders.add(folder);
      }
      return folders;
    } on Object {
      return null;
    }
  }

  Future<void> _clearFolderCaches(String email, String folderPath) async {
    final headers = await _headersDir(email, folderPath);
    if (await headers.exists()) await headers.delete(recursive: true);
    final body = await _bodyDir(email, folderPath);
    if (await body.exists()) await body.delete(recursive: true);
    final account = await _accountDir(email);
    final attach = Directory(
      '${account.path}${Platform.pathSeparator}attach'
      '${Platform.pathSeparator}${_hash(folderPath)}',
    );
    if (await attach.exists()) await attach.delete(recursive: true);
  }

  Future<void> _writeJsonAtomic(File file, Map<String, dynamic> payload) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    // Windows 上 rename 不会覆盖已存在的目标文件。
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<Map<String, dynamic>?> _readPayload(
    File file, {
    required Duration ttl,
    DateTime? now,
  }) async {
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['schema'] != 1) return null;
    final fetchedAt = DateTime.tryParse(payload['fetchedAt']?.toString() ?? '');
    if (fetchedAt == null) return null;
    final current = now ?? DateTime.now();
    if (current.difference(fetchedAt) > ttl) return null;
    return payload;
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 16);

  static Map<String, dynamic> _folderToJson(MailFolder folder) => {
    'path': folder.path,
    'name': folder.name,
    'role': folder.role.name,
    'unread': folder.unread,
    'uidValidity': folder.uidValidity,
  };

  static MailFolder? _folderFromJson(Map<String, dynamic> json) {
    final path = (json['path'] ?? '').toString();
    if (path.isEmpty) return null;
    return MailFolder(
      path: path,
      name: (json['name'] ?? path).toString(),
      role: MailFolderRole.values.firstWhere(
        (value) => value.name == json['role'],
        orElse: () => MailFolderRole.other,
      ),
      unread: _asInt(json['unread']),
      uidValidity:
          json['uidValidity'] is int ? json['uidValidity'] as int : null,
    );
  }

  static Map<String, dynamic> _headerToJson(MailHeader header) => {
    'uid': header.uid,
    'subject': header.subject,
    'fromName': header.from?.name,
    'fromAddress': header.from?.address,
    'to': [
      for (final address in header.to)
        {'name': address.name, 'address': address.address},
    ],
    'cc': [
      for (final address in header.cc)
        {'name': address.name, 'address': address.address},
    ],
    'date': header.date?.toIso8601String(),
    'isRead': header.isRead,
    'hasAttachments': header.hasAttachments,
    'messageId': header.messageId,
  };

  static MailHeader? _headerFromJson(Map<String, dynamic> json) {
    final uid = _asInt(json['uid']);
    if (uid <= 0) return null;
    final fromAddress = json['fromAddress']?.toString();
    final rawTo = json['to'];
    final rawCc = json['cc'];
    return MailHeader(
      uid: uid,
      subject: (json['subject'] ?? '').toString(),
      from:
          fromAddress == null || fromAddress.isEmpty
              ? null
              : MailAddress(
                name: json['fromName']?.toString(),
                address: fromAddress,
              ),
      to: _addressList(rawTo),
      cc: _addressList(rawCc),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      isRead: json['isRead'] == true,
      hasAttachments: json['hasAttachments'] == true,
      messageId: json['messageId']?.toString(),
    );
  }

  /// 旧缓存没有 `cc` 字段，统一按空列表读取。
  static List<MailAddress> _addressList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          if ((item['address'] ?? '').toString().isNotEmpty)
            MailAddress(
              name: item['name']?.toString(),
              address: item['address'].toString(),
            ),
    ];
  }

  static Map<String, dynamic> _attachmentToJson(MailAttachment attachment) => {
    'fetchId': attachment.fetchId,
    'fileName': attachment.fileName,
    'mimeType': attachment.mimeType,
    'size': attachment.size,
  };

  static MailAttachment? _attachmentFromJson(Map<String, dynamic> json) {
    final fetchId = (json['fetchId'] ?? '').toString();
    if (fetchId.isEmpty) return null;
    return MailAttachment(
      fetchId: fetchId,
      fileName: (json['fileName'] ?? '附件').toString(),
      mimeType: (json['mimeType'] ?? 'application/octet-stream').toString(),
      size: _asInt(json['size']),
    );
  }

  static int _asInt(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text) ?? 0,
    _ => 0,
  };
}
