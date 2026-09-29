import 'package:flutter/foundation.dart';

import '../../capabilities/persistent_summary_cache.dart';
import '../../services/auth_service.dart';
import '../../services/campus_session.dart';
import '../../services/service_endpoints.dart';
import 'classroom_usage_models.dart';

/// 空教室查询服务：只声明 URL 与请求参数，凭证/换票由统一身份层负责。
class ClassroomUsageService {
  static final _client = CampusSession.client(CampusServices.roomReservation);

  static const _buildingsResourceKey = 'buildings';

  /// 楼栋列表：变动极不频繁，与首页“学期/教学周”同类冷缓存（内存 TTL
  /// 5 分钟 + 磁盘持久 30 天，按账号分键，登出即清）；`force` 时绕过。
  static final _buildingsCache =
      PersistentSummaryCache<RoomBuildingsCacheEntry>(
        storageKey: 'roomis.buildings.v1',
        ttl: const Duration(minutes: 5),
        persistTtl: const Duration(days: 30),
        maxEntries: 8,
        fromJson: RoomBuildingsCacheEntry.fromJson,
        toJson: (entry) => entry.toJson(),
      );

  /// 建筑表：冷启动先展示磁盘旧值并后台刷新，`force` 时绕过缓存。
  static Future<List<RoomBuilding>> fetchBuildings({bool force = false}) async {
    final accountKey = await _tryCurrentAccountKey();
    if (accountKey == null) {
      return (await _fetchBuildingsFromNetwork()).buildings;
    }
    final entry = await _buildingsCache.load(
      accountKey,
      _buildingsResourceKey,
      _fetchBuildingsFromNetwork,
      force: force,
    );
    return entry.buildings;
  }

  static Future<RoomBuildingsCacheEntry> _fetchBuildingsFromNetwork() async {
    final response = await _client.request(
      'GET',
      buildingsUri().toString(),
      extraHeaders: {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': CampusServiceEndpoints.roomisBookingSpacesUri.toString(),
      },
      throwOnHttpError: false,
    );
    _throwIfFailed(response.body, response.statusCode, '楼栋列表');
    return RoomBuildingsCacheEntry(
      buildings: parseRoomBuildings(response.body),
    );
  }

  static Future<String?> _tryCurrentAccountKey() async {
    try {
      return (await AuthService.getCurrentAccount())?.accountKey;
    } catch (_) {
      return null;
    }
  }

  /// 教室占用查询：时间敏感，不做业务缓存，仅依赖 CampusSession 对 GET
  /// 单飞去重。
  static Future<List<RoomUsageItem>> fetchSpaces({
    required String date,
    String? beginTime,
    String? endTime,
    String? locationId,
    int pageSize = 20,
    int pageIndex = 1,
  }) async {
    final response = await _client.request(
      'GET',
      spacesUri(
        date: date,
        beginTime: beginTime,
        endTime: endTime,
        locationId: locationId,
        pageSize: pageSize,
        pageIndex: pageIndex,
      ).toString(),
      extraHeaders: {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': CampusServiceEndpoints.roomisBookingSpacesUri.toString(),
      },
      throwOnHttpError: false,
    );
    _throwIfFailed(response.body, response.statusCode, '教室占用查询');
    return parseRoomUsageItems(response.body);
  }

  @visibleForTesting
  static Uri buildingsUri() {
    return CampusServiceEndpoints.roomisBuildingsUri.replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
  }

  @visibleForTesting
  static Uri spacesUri({
    String? date,
    String? beginTime,
    String? endTime,
    String? locationId,
    int pageSize = 20,
    int pageIndex = 1,
  }) {
    return CampusServiceEndpoints.roomisSpacesUri.replace(
      queryParameters: {
        // 与网页版保持一致：筛选参数始终携带，未选时为空串。
        'date': date ?? '',
        'beginTime': beginTime ?? '',
        'endTime': endTime ?? '',
        'locationId': locationId ?? '',
        'status': '',
        'num': '',
        'keyword': '',
        'pageSize': '$pageSize',
        'pageIndex': '$pageIndex',
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }

  static void _throwIfFailed(String body, int statusCode, String label) {
    if (statusCode == 200) return;
    final lower = body.toLowerCase();
    if (lower.contains('openid-connect') ||
        lower.contains('authserver') ||
        lower.contains('统一身份认证') ||
        lower.contains('login')) {
      throw const RoomUsageAuthenticationException();
    }
    throw RoomUsageApiException('$label失败（HTTP $statusCode）');
  }
}

class RoomUsageAuthenticationException implements Exception {
  final String message;

  const RoomUsageAuthenticationException([
    this.message = '教室平台登录状态已失效，请重新登录后重试。',
  ]);

  @override
  String toString() => message;
}

class RoomUsageApiException implements Exception {
  final String message;

  const RoomUsageApiException(this.message);

  @override
  String toString() => message;
}
