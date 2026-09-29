import 'dart:convert';

/// 教室占用状态归一化后的展示枚举。
enum RoomUsageStatus { free, occupied, unknown }

/// 楼栋（建筑表条目）。
class RoomBuilding {
  final String id;
  final String name;

  const RoomBuilding({required this.id, required this.name});

  factory RoomBuilding.fromJson(Map<String, dynamic> json) {
    final id = _stringField(json, 'id') ?? _stringField(json, 'locationId');
    final name =
        _stringField(json, 'name') ??
        _stringField(json, 'buildingName') ??
        _stringField(json, 'title');
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      throw const FormatException('楼栋条目缺少 id/name');
    }
    return RoomBuilding(id: id, name: name);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// 楼栋列表的持久缓存条目（按账号冷缓存，与首页学期缓存同一机制）。
class RoomBuildingsCacheEntry {
  final List<RoomBuilding> buildings;

  const RoomBuildingsCacheEntry({required this.buildings});

  Map<String, dynamic> toJson() => {
    'buildings': [for (final building in buildings) building.toJson()],
  };

  factory RoomBuildingsCacheEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['buildings'];
    if (raw is! List) throw const FormatException('楼栋缓存缺少 buildings');
    return RoomBuildingsCacheEntry(
      buildings: [
        for (final item in raw)
          if (item is Map)
            RoomBuilding.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

/// 教室占用条目。
class RoomUsageItem {
  final String id;
  final String name;
  final String? buildingName;
  final String status;
  final String? beginTime;
  final String? endTime;
  final String? capacity;

  const RoomUsageItem({
    required this.id,
    required this.name,
    required this.status,
    this.buildingName,
    this.beginTime,
    this.endTime,
    this.capacity,
  });

  RoomUsageStatus get displayStatus {
    final normalized = status.toLowerCase();
    if (normalized.contains('free') ||
        normalized.contains('available') ||
        normalized.contains('idle') ||
        normalized.contains('空闲') ||
        normalized.contains('未使用') ||
        normalized.contains('未预约') ||
        normalized.contains('可预约')) {
      return RoomUsageStatus.free;
    }
    if (normalized.contains('booked') ||
        normalized.contains('busy') ||
        normalized.contains('占用') ||
        normalized.contains('使用中')) {
      return RoomUsageStatus.occupied;
    }
    return RoomUsageStatus.unknown;
  }

  factory RoomUsageItem.fromJson(Map<String, dynamic> json) {
    final id =
        _stringField(json, 'id') ??
        _stringField(json, 'roomId') ??
        _stringField(json, 'locationId');
    final name =
        _stringField(json, 'name') ??
        _stringField(json, 'roomName') ??
        _stringField(json, 'title');
    final status = _stringField(json, 'status') ?? '';
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      throw const FormatException('教室条目缺少 id/name');
    }
    return RoomUsageItem(
      id: id,
      name: name,
      status: status,
      buildingName:
          _stringField(json, 'buildingName') ??
          _stringField(json, 'locationName') ??
          _stringField(json, 'level2Location'),
      beginTime:
          _stringField(json, 'beginTime') ?? _stringField(json, 'startTime'),
      endTime: _stringField(json, 'endTime'),
      capacity: _stringField(json, 'capacity') ?? _stringField(json, 'num'),
    );
  }
}

/// 从响应体安全提取教室条目列表：兼容 `{code,data:[...]}`、
/// `{data:{list/records:[...]}}` 与裸数组三种常见外层。
List<RoomUsageItem> parseRoomUsageItems(String body) {
  final decoded = _decodeJson(body);
  final raw = _extractList(decoded);
  return raw
      .whereType<Map<String, dynamic>>()
      .map(RoomUsageItem.fromJson)
      .toList(growable: false);
}

/// 从响应体安全提取楼栋列表（外层结构同上）。
List<RoomBuilding> parseRoomBuildings(String body) {
  final decoded = _decodeJson(body);
  final raw = _extractList(decoded);
  return raw
      .whereType<Map<String, dynamic>>()
      .map(RoomBuilding.fromJson)
      .toList(growable: false);
}

Object? _decodeJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw const FormatException('教室接口未返回 JSON');
  }
}

List<dynamic> _extractList(Object? decoded) {
  if (decoded is List) return decoded;
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('教室接口返回结构异常');
  }
  final data = decoded['data'];
  if (data is List) return data;
  if (data is Map<String, dynamic>) {
    final nested =
        data['list'] ?? data['records'] ?? data['rows'] ?? data['items'];
    if (nested is List) return nested;
  }
  // roomis 实际返回 `{pagination:{...}, list:[...], empty:...}` 顶层结构。
  final topLevel =
      decoded['list'] ??
      decoded['records'] ??
      decoded['rows'] ??
      decoded['items'];
  if (topLevel is List) return topLevel;
  throw const FormatException('教室接口缺少 data 列表');
}

String? _stringField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  if (value is num) return value.toString();
  return null;
}
