import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../capabilities/east8_time.dart';
import '../../capabilities/persistent_summary_cache.dart';
import '../../services/account_network_session_service.dart';
import '../../services/auth_service.dart';
import '../../services/campus_session.dart';
import '../../services/mobile_campus_request_signer.dart';
import '../../services/service_endpoints.dart';
import 'mobile_campus_notice_models.dart';
import 'portal_notices_models.dart';

class MobileCampusAuthenticationException implements Exception {
  final String message;

  const MobileCampusAuthenticationException([
    this.message = '移动校园登录状态已失效，请重新登录后重试。',
  ]);

  @override
  String toString() => message;
}

class MobileCampusApiException implements Exception {
  final String message;

  const MobileCampusApiException(this.message);

  @override
  String toString() => message;
}

/// Reads the mobile campus notification APIs declared in the captured HAR:
/// list-all, tag list, department summary, keyword search and HTML detail.
class MobileCampusNoticeService {
  static const _requestTimeout = Duration(seconds: 12);
  static const _noticesTtl = Duration(seconds: 30);

  static final PersistentSummaryCache<List<PortalNotice>>
  _noticesCache = PersistentSummaryCache<List<PortalNotice>>(
    storageKey: 'mobile.notices.v1',
    ttl: _noticesTtl,
    persistTtl: const Duration(minutes: 30),
    maxEntries: 4,
    fromJson: (json) {
      final list = json['notices'];
      if (list is! List) return const <PortalNotice>[];
      return list
          .whereType<Map>()
          .map((item) => PortalNotice.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    },
    toJson:
        (notices) => {
          'notices': [for (final notice in notices) notice.toJson()],
        },
  );

  static ValueListenable<int> get noticesRevision => _noticesCache.revision;

  Future<List<PortalNotice>> fetchNotices({bool force = false}) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) throw StateError('请先登录后再读取通知公告');
    return _noticesCache.load(
      account.accountKey,
      'mobile-notices-page-1',
      () async => (await fetchListPage(offset: 1, limit: 10)).items,
      force: force,
    );
  }

  Future<PortalNoticePage> fetchListPage({
    required int offset,
    String? tagId,
    String? theme,
    int limit = 10,
  }) async {
    if (offset < 1 || limit < 1) {
      throw ArgumentError.value(offset, 'offset', '分页参数无效');
    }
    final hasTag = tagId != null && tagId.isNotEmpty;
    final param = <String, Object?>{
      'campusType': 1,
      if (hasTag) 'tagId': tagId,
      if (hasTag) 'type': 1,
      if (theme != null && theme.isNotEmpty) 'theme': theme,
      'offset': offset,
      'wxCode': null,
      'client': null,
      'openId': null,
    };
    final path = hasTag ? 'getMessageListByTag.do' : 'getMessageList.do';
    final decoded = await _post(path, param);
    return MobileCampusNoticeParser.parsePage(
      decoded,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<MobileCampusNoticeColumn>> fetchColumns() async {
    final decoded = await _post('getMessageSummary.do', {
      'campusType': 1,
      'wxCode': null,
      'client': null,
      'openId': null,
    });
    return MobileCampusNoticeParser.parseColumns(decoded);
  }

  Future<List<MobileCampusNoticeSearchGroup>> searchGroups(String theme) async {
    final query = theme.trim();
    if (query.isEmpty) return const [];
    final decoded = await _post('searchMessage.do', {
      'campusType': 1,
      'theme': query,
      'wxCode': null,
      'client': null,
      'openId': null,
    });
    return MobileCampusNoticeParser.parseSearchGroups(decoded);
  }

  Future<MobileCampusNoticeDetail> fetchDetail({
    required String messageId,
    required String tagId,
  }) async {
    final decoded = await _post('getMessageInfo.do', {
      'campusType': 1,
      'messageInfo': {
        'isRead': 0,
        'messageId': int.tryParse(messageId) ?? 0,
        'tagId': tagId,
      },
      'wxCode': null,
      'client': null,
      'openId': null,
    });
    return MobileCampusNoticeParser.parseDetail(decoded);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> param,
  ) async {
    try {
      return await _postOnce(path, param);
    } on MobileCampusAuthenticationException {
      final refreshed =
          await CampusSession.client(CampusServices.mobileCampus).refresh();
      if (!refreshed) rethrow;
      return _postOnce(path, param);
    }
  }

  Future<Map<String, dynamic>> _postOnce(
    String path,
    Map<String, Object?> param,
  ) async {
    final uri = '${CampusServiceEndpoints.mobileCampusMessageBase}/$path';
    final response = await CampusSession.client(
      CampusServices.mobileCampus,
    ).request(
      'POST',
      uri,
      body: MobileCampusRequestSigner.signedBody(param),
      contentType: ContentType.json,
      requestTimeout: _requestTimeout,
      responseTimeout: _requestTimeout,
      throwOnHttpError: false,
      autoExchangeService: false,
      extraHeaders: const {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Origin': 'file://',
        'X-Requested-With': 'com.lantu.MobileCampus.chd',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Version/4.0 Chrome/139.0 Mobile '
            'Safari/537.36 lantuMobilecampus lantuMC',
      },
    );
    return MobileCampusNoticeParser.decodeResponse(response, Uri.parse(uri));
  }
}

class MobileCampusNoticeParser {
  static Map<String, dynamic> decodeResponse(
    AccountNetworkResponse response,
    Uri uri,
  ) {
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden ||
        (response.statusCode >= HttpStatus.multipleChoices &&
            response.statusCode < HttpStatus.badRequest)) {
      throw const MobileCampusAuthenticationException();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw MobileCampusApiException('移动校园服务返回 HTTP ${response.statusCode}');
    }
    final raw =
        response.body.startsWith('\uFEFF')
            ? response.body.substring(1)
            : response.body;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (decoded == null) {
      if (looksLikeAuthenticationPage(raw)) {
        throw const MobileCampusAuthenticationException();
      }
      throw const MobileCampusApiException('移动校园服务返回了无法识别的数据');
    }
    final map = _asMap(decoded);
    throwIfFailed(map);
    return map;
  }

  static void throwIfFailed(Map<String, dynamic> map) {
    final msgState = map['msgState'];
    if (msgState != null && msgState.toString() != '1') {
      final message = _string(map['msg']);
      if (_looksLikeAuthenticationFailure(message)) {
        throw MobileCampusAuthenticationException(message);
      }
      throw MobileCampusApiException(message.isEmpty ? '移动校园服务请求失败' : message);
    }
    final errorCode = map['errcode'];
    if (errorCode != null && errorCode.toString() != '0') {
      final message = _string(map['errmsg']);
      if (_looksLikeAuthenticationFailure(message)) {
        throw MobileCampusAuthenticationException(message);
      }
      throw MobileCampusApiException(message.isEmpty ? '移动校园服务请求失败' : message);
    }
  }

  static PortalNoticePage parsePage(
    Object? raw, {
    required int offset,
    required int limit,
  }) {
    final map = _asMap(raw);
    throwIfFailed(map);
    final rows = map['messageList'];
    if (rows is! List) {
      throw const MobileCampusApiException('公告列表格式异常');
    }
    final items = rows
        .whereType<Map>()
        .map((item) => _parseNotice(Map<String, dynamic>.from(item)))
        .where((notice) => notice.id.isNotEmpty && notice.title.isNotEmpty)
        .toList(growable: false);
    final totalPages = _int(map['totalPages']);
    final serverLimit = _int(map['limit']);
    final effectiveLimit = serverLimit > 0 ? serverLimit : limit;
    return PortalNoticePage(
      items: items,
      totalSize: totalPages <= 0 ? 0 : totalPages * effectiveLimit,
      pageNumber: offset,
      pageSize: effectiveLimit,
    );
  }

  static List<MobileCampusNoticeColumn> parseColumns(Object? raw) {
    final map = _asMap(raw);
    throwIfFailed(map);
    final rows = map['messageSummary'];
    if (rows is! List) {
      throw const MobileCampusApiException('栏目摘要格式异常');
    }
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _int(item['type']) != 2)
        .map(
          (item) => MobileCampusNoticeColumn(
            tagId: _string(item['tagId']),
            tagName: _string(item['tagName']),
          ),
        )
        .where((column) => column.tagId.isNotEmpty && column.tagName.isNotEmpty)
        .toList(growable: false);
  }

  static List<MobileCampusNoticeSearchGroup> parseSearchGroups(Object? raw) {
    final map = _asMap(raw);
    throwIfFailed(map);
    final rows = map['list'];
    if (rows is! List) {
      throw const MobileCampusApiException('公告搜索格式异常');
    }
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _int(item['type']) != 2)
        .map(
          (item) => MobileCampusNoticeSearchGroup(
            tagId: _string(item['tagId']),
            tagName: _string(item['tagName']),
            count: _int(item['cnt']),
            latestTitle: _string(item['theme']),
            type: _string(item['typeCode']),
          ),
        )
        .where(
          (group) =>
              group.tagId.isNotEmpty &&
              group.tagName.isNotEmpty &&
              group.latestTitle.isNotEmpty,
        )
        .toList(growable: false);
  }

  static MobileCampusNoticeDetail parseDetail(Object? raw) {
    final map = _asMap(raw);
    throwIfFailed(map);
    final info = map['messageInfo'];
    if (info is! Map) {
      throw const MobileCampusApiException('公告正文格式异常');
    }
    final fields = Map<String, dynamic>.from(info);
    return MobileCampusNoticeDetail(
      messageId: _string(fields['messageId']),
      tagId: _string(fields['tagId']),
      title: _string(fields['theme']),
      department: _string(fields['messageFrom']),
      publishedAt: _formatEpoch(_int(fields['createTime'])),
      contentHtml: _string(fields['content']),
      read: _int(fields['isRead']) == 1,
    );
  }

  static PortalNotice _parseNotice(Map<String, dynamic> item) {
    return PortalNotice(
      id: _string(item['messageId']),
      title: _string(item['theme']),
      department: _string(item['messageFrom']),
      publishedAt: _formatEpoch(_int(item['createTime'])),
      column: _string(item['tagName']),
      tagId: _string(item['tagId']),
      pinned: _int(item['isTop']) == 1,
      read: _int(item['isRead']) == 1,
    );
  }

  static bool looksLikeAuthenticationPage(String rawBody) {
    final lower = rawBody.toLowerCase();
    return lower.contains('authserver/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('cas login') ||
        lower.contains('protocol/openid-connect') ||
        (lower.contains('<html') && lower.contains('登录'));
  }

  static bool _looksLikeAuthenticationFailure(String message) {
    final lower = message.toLowerCase();
    return lower.contains('login') ||
        lower.contains('session') ||
        lower.contains('token') ||
        message.contains('登录') ||
        message.contains('未登录') ||
        message.contains('凭证') ||
        message.contains('认证') ||
        message.contains('无权限') ||
        message.contains('无权');
  }

  static String _formatEpoch(int milliseconds) {
    if (milliseconds <= 0) return '';
    final east8 = DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).add(east8Offset);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${east8.year}-${two(east8.month)}-${two(east8.day)} '
        '${two(east8.hour)}:${two(east8.minute)}';
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const MobileCampusApiException('移动校园数据格式异常');
  }

  static int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

  static String _string(Object? value) => value?.toString().trim() ?? '';
}
