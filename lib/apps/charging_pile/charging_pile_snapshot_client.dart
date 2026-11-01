import 'dart:convert';

import 'charging_pile_http_client.dart';
import 'charging_pile_models.dart';

/// 一个分区的快照。
class ChargingPileSnapshotArea {
  const ChargingPileSnapshotArea({
    required this.key,
    required this.name,
    required this.expectedDevices,
    required this.devices,
    this.sampledAt,
    this.partial = false,
    this.degraded = false,
  });

  /// 站点分区键（`chaohui` / `zhu` …），与目录 `areas[].key` 一致。
  final String key;
  final String name;

  /// 这个分区**应该有**多少台桩。与 [devices] 的数量对不上就是 partial。
  final int expectedDevices;

  /// 逐台的插座状态，键是设备 id。
  final Map<String, List<ChargingPileSlot>> devices;

  /// 采样时刻（本机时区）。
  final DateTime? sampledAt;

  /// 部分设备这次没采到：它们的状态是「未知」，不是「占用」。
  final bool partial;

  /// 整个分区这次没取到（快照为空），调用方应保留上一次的结果。
  final bool degraded;

  bool get hasData => !degraded && devices.isNotEmpty;
}

/// `/api/snap?area=all` 的一次结果。
class ChargingPileSnapshot {
  const ChargingPileSnapshot({required this.areas});

  final List<ChargingPileSnapshotArea> areas;
}

/// 站点全校快照的只读客户端。
///
/// 这是最省请求的取数方式：一次拿到所有分区、所有桩的逐插座状态。
/// 代价是数据来自定时采样（白天分钟级、深夜小时级），比 `/api/pile` 旧，
/// 所以它负责「铺满首屏」，用户主动刷新仍走 `/api/pile`。
class ChargingPileSnapshotClient {
  ChargingPileSnapshotClient({
    ChargingPileHttpClient? httpClient,
    Uri? uri,
    this.timeout = const Duration(seconds: 10),
    this.ttl = const Duration(seconds: 60),
  }) : _http = httpClient ?? ChargingPileHttpClient(),
       _ownsClient = httpClient == null,
       _uri = uri ?? endpoint;

  /// 边缘缓存 60 秒，客户端也按 60 秒去重，避免连点。
  static final Uri endpoint = Uri.parse(
    'https://chd-charge.pages.dev/api/snap?area=all',
  );

  final ChargingPileHttpClient _http;
  final bool _ownsClient;
  final Uri _uri;
  final Duration timeout;
  final Duration ttl;

  ChargingPileSnapshot? _cached;
  DateTime? _cachedAt;

  Future<ChargingPileSnapshot> fetch({bool force = false}) async {
    final cached = _cached;
    final at = _cachedAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < ttl) {
      return cached;
    }
    final response = await _http.get(_uri, timeout: timeout);
    if (response.statusCode == 429) {
      throw const ChargingPileException(ChargingPileFailure.rateLimited);
    }
    if (response.statusCode != 200) {
      throw const ChargingPileException(ChargingPileFailure.network);
    }
    final parsed = parse(
      const Utf8Decoder(allowMalformed: true).convert(response.bodyBytes),
    );
    _cached = parsed;
    _cachedAt = DateTime.now();
    return parsed;
  }

  /// 解析快照响应。单个分区坏掉只丢那个分区，不让整份作废。
  static ChargingPileSnapshot parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    if (decoded['ok'] != true) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    final rawAreas = decoded['areas'];
    if (rawAreas is! List) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }

    final areas = <ChargingPileSnapshotArea>[];
    for (final raw in rawAreas) {
      if (raw is! Map) continue;
      final key = raw['key'];
      if (key is! String || key.isEmpty) continue;
      final snapshot = raw['snapshot'];
      final expected = _asInt(raw['count']) ?? 0;
      if (snapshot is! Map) {
        // 这个区这次没取到；保留调用方已有的数据。
        areas.add(
          ChargingPileSnapshotArea(
            key: key,
            name: _asString(raw['name']) ?? key,
            expectedDevices: expected,
            devices: const {},
            degraded: true,
          ),
        );
        continue;
      }
      final devices = <String, List<ChargingPileSlot>>{};
      final rawDevices = snapshot['devices'];
      if (rawDevices is Map) {
        for (final entry in rawDevices.entries) {
          final id = entry.key;
          final value = entry.value;
          if (id is! String || value is! Map) continue;
          final slots = _decodePorts(value['p'], _asInt(value['n']));
          if (slots == null) continue;
          devices[id] = slots;
        }
      }
      final error = snapshot['error'];
      final partial =
          (error is Map && error['code'] == 'partial') ||
          devices.length < expected;
      final sampledAt = _asInt(snapshot['at']);
      areas.add(
        ChargingPileSnapshotArea(
          key: key,
          name: _asString(raw['name']) ?? key,
          expectedDevices: expected,
          devices: devices,
          sampledAt: sampledAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(sampledAt * 1000),
          partial: partial,
        ),
      );
    }
    if (areas.isEmpty) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }

    return ChargingPileSnapshot(
      areas: List<ChargingPileSnapshotArea>.unmodifiable(areas),
    );
  }

  /// `p` 是「一个字符一个插座」的紧凑串：`0` 空闲，其余一律非空闲。
  ///
  /// 站点在这里把「占用」和「异常/离线」合并成了同一个字符，所以快照只能
  /// 区分空/不空；需要细分就补 `/api/pile`。
  static List<ChargingPileSlot>? _decodePorts(Object? raw, int? portCount) {
    if (raw is! String || raw.isEmpty || raw.length > 20) return null;
    final slots = <ChargingPileSlot>[];
    for (var index = 0; index < raw.length; index++) {
      slots.add(
        ChargingPileSlot(
          slotId: index + 1,
          status: raw[index] == '0' ? 0 : 1,
        ),
      );
    }
    if (portCount != null && portCount > slots.length) {
      // 平台标称口数比返回的多：多出来的口按「其他」补上，别少画格子。
      for (var index = slots.length; index < portCount; index++) {
        slots.add(ChargingPileSlot(slotId: index + 1, status: 2));
      }
    }
    return slots;
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    return null;
  }

  static String? _asString(Object? raw) => raw is String ? raw : null;

  void close() {
    if (_ownsClient) _http.close();
  }
}
