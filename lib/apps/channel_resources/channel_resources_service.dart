import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;

import '../../capabilities/channel_account_capability.dart';
import '../../services/channel_resources_session_service.dart';
import '../../capabilities/saved_login_credential.dart';
import 'channel_resources_models.dart';

export '../../capabilities/channel_account_capability.dart'
    show
        ChannelAccountState,
        ChannelAccountStatus,
        ChannelAccountErrorType,
        ChannelAccountUser,
        ChannelAccountException,
        ChannelAccountHttpResponse;

class ChannelResourcesServiceException implements Exception {
  final String message;
  final int? statusCode;

  const ChannelResourcesServiceException(this.message, {this.statusCode});

  @override
  String toString() => 'ChannelResourcesServiceException($statusCode)';
}

/// Typed feature adapter for the normal-user routes of the channel site.
///
/// Pages only receive models and operation results. Authentication state,
/// refresh cookies, and access tokens remain inside
/// [ChannelResourcesSession].
class ChannelResourcesService {
  ChannelResourcesService.withAccount(ChannelAccountCapability account)
    : _account = account;

  @visibleForTesting
  ChannelResourcesService.forSessionForTesting(
    ChannelResourcesSession session, {
    SavedLoginCredentialCapability? savedCredential,
  }) : _account = ChannelAccountCapability(
         session,
         savedCredential: savedCredential,
       );

  static final ChannelResourcesService current =
      ChannelResourcesService.withAccount(ChannelAccountCapability.current);

  final ChannelAccountCapability _account;

  @visibleForTesting
  ChannelAccountCapability get accountForTesting => _account;

  ChannelAccountUser? get user => _account.user;
  ChannelAccountState get authState => _account.state;
  ValueListenable<ChannelAccountState> get authStateListenable =>
      _account.stateListenable;

  Future<ChannelAccountState> restore() => _account.restore();

  Future<ChannelResourcePage> loadResources({
    String search = '',
    String tags = '',
    int page = 1,
    int perPage = 12,
    String sortBy = 'downloads',
  }) async {
    final response = await _request(
      'GET',
      'resources',
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (tags.trim().isNotEmpty) 'tags': tags.trim(),
        'page': page.toString(),
        'per_page': perPage.toString(),
        'sort_by': sortBy,
      },
    );
    final root = _map(_decode(response));
    final rawResources = _list(root, 'resources');
    final ownedIds = ChannelResourcesJson.strings(root['user_resource_ids']);
    final resources = rawResources
        .map((item) => _map(item))
        .map(
          (item) => ChannelResource.fromJson(
            item,
            owned: ownedIds.contains(ChannelResourcesJson.text(item, 'id')),
          ),
        )
        .toList(growable: false);
    return ChannelResourcePage(
      resources: resources,
      page: ChannelResourcesJson.number(root, 'page', fallback: page),
      perPage: ChannelResourcesJson.number(root, 'per_page', fallback: perPage),
      totalPages: ChannelResourcesJson.number(root, 'total_pages', fallback: 1),
      totalResources: ChannelResourcesJson.number(
        root,
        'total_resources',
        fallback: resources.length,
      ),
      sortBy: ChannelResourcesJson.text(
        root,
        'applied_sort_by',
        fallback: ChannelResourcesJson.text(
          root,
          'applied_sort',
          fallback: sortBy,
        ),
      ),
      sortNotice: ChannelResourcesJson.text(root, 'sort_notice'),
    );
  }

  Future<List<ChannelTag>> loadTags() async {
    final response = await _request('GET', 'tags');
    final raw = _list(_decode(response), 'tags');
    return raw
        .map((item) => ChannelTag.fromJson(_map(item)))
        .where((tag) => tag.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<ChannelAnnouncement>> loadAnnouncements() async {
    final response = await _request('GET', 'announcements/public');
    final root = _map(_decode(response));
    return _announcementItems(root)
        .map((item) => ChannelAnnouncement.fromJson(_map(item)))
        .toList(growable: false);
  }

  Future<List<ChannelLink>> loadLinks() async {
    final response = await _request('GET', 'links');
    return _list(_decode(response), 'links')
        .map((item) => ChannelLink.fromJson(_map(item)))
        .where((link) => link.url.isNotEmpty)
        .toList(growable: false);
  }

  /// Returns false when the backend reports that the resource was already
  /// owned. A second tap therefore cannot create a duplicate purchase.
  Future<bool> purchaseResource(String resourceId) async {
    final userId = user?.id;
    if (userId == null || userId.isEmpty) {
      throw const ChannelResourcesServiceException('请先登录频道账号。');
    }
    final response = await _request(
      'POST',
      'resources/purchase',
      queryParameters: {'resource_id': resourceId, 'user_id': userId},
      allowedStatusCodes: const {409},
    );
    if (response.statusCode == 409) return false;
    _expectSuccess(response);
    return true;
  }

  Future<Uri> resolveResource(ChannelResource resource) async {
    final identifier = resource.fakeId.isEmpty ? resource.id : resource.fakeId;
    if (identifier.isEmpty) {
      throw const ChannelResourcesServiceException('资料链接不可用。');
    }
    final response = await _request(
      'GET',
      'redirect/${Uri.encodeComponent(identifier)}',
    );
    final map = _map(_decode(response));
    final target = ChannelResourcesJson.text(map, 'target_url');
    final uri = Uri.tryParse(target);
    if (uri == null ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https') ||
        uri.host.isEmpty) {
      throw const ChannelResourcesServiceException('资料链接不可用。');
    }
    return uri;
  }

  Future<int?> loadCurrentPoints() async {
    final response = await _request(
      'GET',
      'users/me/points',
      allowedStatusCodes: const {404},
    );
    if (response.statusCode == 404) return null;
    _expectSuccess(response);
    final map = _map(_decode(response));
    final value = map['points'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Future<ChannelCheckinResult> checkIn() async {
    final userId = user?.id;
    if (userId == null || userId.isEmpty) {
      throw const ChannelResourcesServiceException('请先登录频道账号。');
    }
    final response = await _request(
      'POST',
      'users/checkin',
      queryParameters: {'user_id': userId},
      allowedStatusCodes: const {409},
    );
    if (response.statusCode == 409) {
      return const ChannelCheckinResult(
        alreadyCheckedIn: true,
        rewardPoints: 0,
        points: 0,
      );
    }
    _expectSuccess(response);
    final map = _map(_decode(response));
    return ChannelCheckinResult(
      alreadyCheckedIn: false,
      rewardPoints: ChannelResourcesJson.number(map, 'reward_points'),
      points: ChannelResourcesJson.number(map, 'points'),
    );
  }

  Future<void> submitResource({
    required String name,
    required String link,
    required int points,
    required List<String> tags,
  }) async {
    final userId = user?.id;
    if (userId == null || userId.isEmpty) {
      throw const ChannelResourcesServiceException('请先登录频道账号。');
    }
    final response = await _request(
      'POST',
      'resources',
      body: {
        'name': name.trim(),
        'link': link.trim(),
        'contributor_id': userId,
        'approved': false,
        'points': points,
        'tags': tags.join(','),
      },
    );
    _expectSuccess(response);
  }

  Future<List<ChannelMessage>> loadMessages() async {
    final response = await _request('GET', 'messages');
    return _list(_decode(response), 'messages')
        .map((item) => ChannelMessage.fromJson(_map(item)))
        .toList(growable: false);
  }

  Future<List<ChannelAdmin>> loadAdmins() async {
    final response = await _request('GET', 'messages/admins');
    return _list(
      _decode(response),
      'admins',
    ).map((item) => ChannelAdmin.fromJson(_map(item))).toList(growable: false);
  }

  Future<void> sendMessageToAdmin({
    required String adminId,
    required String content,
  }) async {
    final response = await _request(
      'POST',
      'messages/send-to-admin',
      queryParameters: {'admin_id': adminId, 'content': content},
    );
    _expectSuccess(response);
  }

  Future<void> deleteMessage(String messageId) async {
    final response = await _request(
      'DELETE',
      'messages/${Uri.encodeComponent(messageId)}',
    );
    _expectSuccess(response);
  }

  Future<void> deleteAllMessages() async {
    final response = await _request('DELETE', 'messages');
    _expectSuccess(response);
  }

  Future<ChannelReviewStats> loadReviewStats() async {
    final response = await _request('GET', 'records/review');
    final raw = _map(_decode(response));
    final counts = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is int) {
        counts[entry.key] = value;
      } else if (value is num) {
        counts[entry.key] = value.toInt();
      } else {
        final parsed = int.tryParse(ChannelResourcesJson.string(value) ?? '');
        if (parsed != null) counts[entry.key] = parsed;
      }
    }
    return ChannelReviewStats(Map<String, int>.unmodifiable(counts));
  }

  Future<ChannelAccountHttpResponse> _request(
    String method,
    String path, {
    Map<String, String> queryParameters = const {},
    Object? body,
    Set<int> allowedStatusCodes = const {},
  }) async {
    final response = await _account.request(
      method,
      path,
      queryParameters: queryParameters,
      body: body,
    );
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        !allowedStatusCodes.contains(response.statusCode)) {
      throw _operationException(response);
    }
    return response;
  }

  static Object _decode(ChannelAccountHttpResponse response) {
    final body = response.body.trimLeft();
    final contentType = response.contentType?.toLowerCase() ?? '';
    if (contentType.startsWith('text/html') || body.startsWith('<')) {
      throw const ChannelResourcesServiceException('服务器返回了网页而不是接口数据。');
    }
    try {
      return jsonDecode(response.body);
    } on Object {
      throw const ChannelResourcesServiceException('服务器返回了无法识别的数据。');
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    final map = ChannelResourcesJson.map(value);
    if (map == null) {
      throw const ChannelResourcesServiceException('服务器返回了无法识别的数据。');
    }
    return map;
  }

  static List<Object?> _list(Object? value, String key) {
    final map = _map(value);
    final list = ChannelResourcesJson.list(map[key]);
    if (list == null) {
      throw const ChannelResourcesServiceException('服务器返回了无法识别的数据。');
    }
    return list;
  }

  static List<Object?> _announcementItems(Map<String, dynamic> root) {
    final raw = root['ticker_announcements'] ?? root['announcements'];
    final ticker =
        raw == null ? const <Object?>[] : ChannelResourcesJson.list(raw);
    if (ticker == null) {
      throw const ChannelResourcesServiceException('服务器返回了无法识别的数据。');
    }

    final popup = root['popup_announcement'];
    if (popup == null) return ticker;
    final popupMap = ChannelResourcesJson.map(popup);
    if (popupMap == null) {
      throw const ChannelResourcesServiceException('服务器返回了无法识别的数据。');
    }

    final popupId = ChannelResourcesJson.text(popupMap, 'id');
    final alreadyIncluded =
        popupId.isNotEmpty &&
        ticker.any((item) {
          final map = ChannelResourcesJson.map(item);
          return map != null && ChannelResourcesJson.text(map, 'id') == popupId;
        });
    return alreadyIncluded ? ticker : <Object?>[...ticker, popup];
  }

  static void _expectSuccess(ChannelAccountHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _operationException(response);
    }
  }

  static ChannelResourcesServiceException _operationException(
    ChannelAccountHttpResponse response,
  ) {
    final message = switch (response.statusCode) {
      400 => '请求参数不正确。',
      403 => '频道资料站拒绝了这项操作。',
      404 => '请求的内容不存在。',
      409 => '这项操作与当前状态冲突。',
      >= 500 => '频道账号服务暂时不可用，请稍后重试。',
      _ => '操作未完成，请稍后重试。',
    };
    return ChannelResourcesServiceException(
      message,
      statusCode: response.statusCode,
    );
  }
}
