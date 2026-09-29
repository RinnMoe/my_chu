import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'public_http_client.dart';
import 'service_endpoints.dart';

/// 校园网状态：通过图书馆公开接口查询出口 IP 与是否校内白名单。
///
/// 接口：`GET https://lib.chd.edu.cn/entry/user/getUserIpAndCheck`，
/// 返回 `data.ip` 与 `data.inWhiteList`；无需登录态。短时内存缓存避免
/// 每次进入“我的”页都重复请求。走共享公开 HTTP 客户端（[PublicHttpClient]）。
class IpStatusService {
  IpStatusService({http.Client? client})
    : _http = client == null ? _sharedHttp : PublicHttpClient(client: client);

  final PublicHttpClient _http;
  static final PublicHttpClient _sharedHttp = PublicHttpClient();

  static final _statusUri = CampusServiceEndpoints.libraryPublicIpStatusUri;
  static const _cacheTtl = Duration(minutes: 5);

  static CampusNetworkStatus? _cached;
  static DateTime? _cachedAt;

  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _cachedAt = null;
  }

  /// 拉取校园网状态；TTL 内返回缓存，失败返回 null（由 UI 静默降级）。
  Future<CampusNetworkStatus?> fetchStatus({bool force = false}) async {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    try {
      final response = await _http.get(
        _statusUri,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final status = parseStatus(response.body);
      if (status == null) return null;
      _cached = status;
      _cachedAt = DateTime.now();
      return status;
    } catch (_) {
      return null;
    }
  }

  /// 解析接口响应；结构异常返回 null 而不是抛错。
  static CampusNetworkStatus? parseStatus(String body) {
    try {
      final decoded = PublicHttpClient.decodeJsonMap(body);
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;
      final ip = data['ip'];
      final inWhiteList = data['inWhiteList'];
      if (ip is! String || ip.trim().isEmpty || inWhiteList is! bool) {
        return null;
      }
      return CampusNetworkStatus(ip: ip.trim(), inWhiteList: inWhiteList);
    } catch (_) {
      return null;
    }
  }
}

class CampusNetworkStatus {
  final String ip;
  final bool inWhiteList;

  const CampusNetworkStatus({required this.ip, required this.inWhiteList});

  /// 展示文案：IP + 校园网/校外网。
  String get label => inWhiteList ? '$ip（校园网）' : '$ip（校外网）';
}
