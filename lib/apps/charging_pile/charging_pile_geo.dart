import 'dart:convert';

import 'package:flutter/services.dart';

/// 充电桩点位精度分级，语义与 assets/charging_pile/charging_pile_locations.json 一致：
///
/// * [measured] —— 直接实测的点位（当前数据没有使用这一级）。
/// * [derived] —— 由实测基准经明确的标定或几何换算得到（北门地块标定、朝晖外接框配准）。
/// * [schematic] —— 沿实测线段两端等分推算，只保证点在线上的相对次序（20号楼、物业服务中心）。
enum ChargingPileLocationPrecision { measured, derived, schematic }

/// 点位资源解析失败的原因。上层可按原因区分「资源损坏」与「资源版本过新」。
enum ChargingPileGeoFailure {
  /// JSON 本身无法解析。
  malformedJson,

  /// `schemaVersion` 不是当前代码认识的版本。
  unsupportedSchemaVersion,

  /// 必需字段缺失。
  missingField,

  /// 字段存在但类型/取值非法（含未知 precision、重复 id、未知 areaId）。
  invalidValue,
}

/// 点位资源解析失败时抛出；绝不静默返回空目录。
class ChargingPileGeoException implements Exception {
  const ChargingPileGeoException(this.failure, this.detail);

  final ChargingPileGeoFailure failure;

  /// 面向开发者的定位信息（JSON 路径 + 期望值），不含业务凭证。
  final String detail;

  @override
  String toString() => 'ChargingPileGeoException(${failure.name}): $detail';
}

/// 一台设备的一个点位（WGS84）。
class ChargingPileLocation {
  const ChargingPileLocation({
    required this.deviceId,
    required this.code,
    required this.areaId,
    required this.latitude,
    required this.longitude,
    required this.precision,
    this.sourceNote,
  });

  final String deviceId;

  /// 站点桩号，例如 `TY-01` / `A03` / `E-24`。
  final String code;

  /// 分区 id，与 `ChargingPileDevice.location` 同源（例如 `渭水-北门`）。
  final String areaId;

  /// WGS84 纬度。
  final double latitude;

  /// WGS84 经度。
  final double longitude;

  final ChargingPileLocationPrecision precision;

  /// 该点的换算说明（像素/等分档位 → WGS84），便于核对与排查。
  final String? sourceNote;
}

/// 分区级元数据：分区名、精度分级与来源说明。
class ChargingPileLocationArea {
  const ChargingPileLocationArea({
    required this.areaId,
    required this.name,
    required this.precision,
    this.sourceNote,
  });

  final String areaId;
  final String name;
  final ChargingPileLocationPrecision precision;
  final String? sourceNote;
}

/// `assets/charging_pile/charging_pile_locations.json` 的内存模型。
///
/// 解析是纯函数（[parse]），读取资源可注入 [AssetBundle]（[load]），
/// 进程内缓存见 [shared]。
class ChargingPileLocationCatalog {
  ChargingPileLocationCatalog._({
    required this.campusId,
    required List<ChargingPileLocation> sites,
    required List<ChargingPileLocationArea> areas,
  }) : _sites = List<ChargingPileLocation>.unmodifiable(sites),
       _areas = List<ChargingPileLocationArea>.unmodifiable(areas),
       _siteById = <String, ChargingPileLocation>{
         for (final site in sites) site.deviceId: site,
       },
       _areaById = <String, ChargingPileLocationArea>{
         for (final area in areas) area.areaId: area,
       };

  static const String assetPath =
      'assets/charging_pile/charging_pile_locations.json';

  /// 本代码认识的资源版本；未知版本视为解析失败。
  static const int schemaVersion = 1;

  /// 资源所属校区 id（当前只有 `weishui`）。
  final String campusId;

  final List<ChargingPileLocation> _sites;
  final List<ChargingPileLocationArea> _areas;
  final Map<String, ChargingPileLocation> _siteById;
  final Map<String, ChargingPileLocationArea> _areaById;

  static ChargingPileLocationCatalog? _sharedCatalog;
  static Future<ChargingPileLocationCatalog>? _sharedLoad;

  List<ChargingPileLocation> get sites => _sites;

  List<ChargingPileLocationArea> get areas => _areas;

  /// 该实例是否持有点位数据。解析成功即为 `true`；保留这个 getter
  /// 是为了让上层在「可空目录 + 已加载状态」两种写法之间保持一致。
  bool get isLoaded => true;

  /// 进程内是否已有缓存目录（[shared] 成功过）。
  static bool get sharedLoaded => _sharedCatalog != null;

  ChargingPileLocation? siteFor(String deviceId) => _siteById[deviceId];

  List<ChargingPileLocation> sitesForArea(String areaId) =>
      List<ChargingPileLocation>.unmodifiable(
        _sites.where((site) => site.areaId == areaId),
      );

  ChargingPileLocationArea? areaFor(String areaId) => _areaById[areaId];

  /// 解析资源 JSON。失败抛 [ChargingPileGeoException]，不会返回空目录。
  static ChargingPileLocationCatalog parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw ChargingPileGeoException(
        ChargingPileGeoFailure.malformedJson,
        'JSON 无法解析：${error.message}',
      );
    }

    final root = _map(decoded, r'$');
    final version = _integer(root, 'schemaVersion', r'$');
    if (version != schemaVersion) {
      throw ChargingPileGeoException(
        ChargingPileGeoFailure.unsupportedSchemaVersion,
        '\$.schemaVersion=$version，本代码只支持 $schemaVersion',
      );
    }
    final campusId = _text(root, 'campusId', r'$');

    final rawAreas = _list(root, 'areas', r'$');
    if (rawAreas.isEmpty) {
      throw const ChargingPileGeoException(
        ChargingPileGeoFailure.invalidValue,
        r'$.areas 为空',
      );
    }
    final areas = <ChargingPileLocationArea>[
      for (final (index, raw) in rawAreas.indexed)
        _parseArea(raw, '\$.areas[$index]'),
    ];
    final areaIds = <String>{};
    for (final area in areas) {
      if (!areaIds.add(area.areaId)) {
        throw ChargingPileGeoException(
          ChargingPileGeoFailure.invalidValue,
          '分区 id 重复：${area.areaId}',
        );
      }
    }

    final rawSites = _list(root, 'sites', r'$');
    if (rawSites.isEmpty) {
      throw const ChargingPileGeoException(
        ChargingPileGeoFailure.invalidValue,
        r'$.sites 为空',
      );
    }
    final sites = <ChargingPileLocation>[
      for (final (index, raw) in rawSites.indexed)
        _parseSite(raw, '\$.sites[$index]'),
    ];
    final deviceIds = <String>{};
    for (final site in sites) {
      if (!deviceIds.add(site.deviceId)) {
        throw ChargingPileGeoException(
          ChargingPileGeoFailure.invalidValue,
          'deviceId 重复：${site.deviceId}',
        );
      }
      if (!areaIds.contains(site.areaId)) {
        throw ChargingPileGeoException(
          ChargingPileGeoFailure.invalidValue,
          '${site.deviceId} 的 areaId「${site.areaId}」不在 areas 里',
        );
      }
    }

    return ChargingPileLocationCatalog._(
      campusId: campusId,
      sites: sites,
      areas: areas,
    );
  }

  /// 从资源包读取并解析。默认 `rootBundle`，测试可传入 `rootBundle` 或自建 bundle。
  static Future<ChargingPileLocationCatalog> load({AssetBundle? bundle}) async {
    final text = await (bundle ?? rootBundle).loadString(assetPath);
    return parse(text);
  }

  /// 进程内共享一份目录；并发调用共享同一个 Future，失败后可重试。
  static Future<ChargingPileLocationCatalog> shared({AssetBundle? bundle}) {
    final cached = _sharedCatalog;
    if (cached != null) {
      return Future<ChargingPileLocationCatalog>.value(cached);
    }
    return _sharedLoad ??= _loadShared(bundle);
  }

  static Future<ChargingPileLocationCatalog> _loadShared(
    AssetBundle? bundle,
  ) async {
    try {
      final catalog = await load(bundle: bundle);
      _sharedCatalog = catalog;
      return catalog;
    } finally {
      _sharedLoad = null;
    }
  }

  static ChargingPileLocationArea _parseArea(Object? raw, String path) {
    final map = _map(raw, path);
    return ChargingPileLocationArea(
      areaId: _text(map, 'areaId', path),
      name: _text(map, 'name', path),
      precision: _precision(map, 'precision', path),
      sourceNote: _optionalText(map, 'sourceNote', path),
    );
  }

  static ChargingPileLocation _parseSite(Object? raw, String path) {
    final map = _map(raw, path);
    final latitude = _decimal(map, 'latitude', path);
    if (latitude < -90 || latitude > 90) {
      throw ChargingPileGeoException(
        ChargingPileGeoFailure.invalidValue,
        '$path.latitude=$latitude 超出 [-90, 90]',
      );
    }
    final longitude = _decimal(map, 'longitude', path);
    if (longitude < -180 || longitude > 180) {
      throw ChargingPileGeoException(
        ChargingPileGeoFailure.invalidValue,
        '$path.longitude=$longitude 超出 [-180, 180]',
      );
    }
    return ChargingPileLocation(
      deviceId: _text(map, 'deviceId', path),
      code: _text(map, 'code', path),
      areaId: _text(map, 'areaId', path),
      latitude: latitude,
      longitude: longitude,
      precision: _precision(map, 'precision', path),
      sourceNote: _optionalText(map, 'sourceNote', path),
    );
  }
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw ChargingPileGeoException(
    ChargingPileGeoFailure.invalidValue,
    '$path 期望对象，实际 ${value.runtimeType}',
  );
}

Object? _field(Map<String, Object?> map, String key, String path) {
  if (!map.containsKey(key)) {
    throw ChargingPileGeoException(
      ChargingPileGeoFailure.missingField,
      '$path.$key 缺失',
    );
  }
  return map[key];
}

String _text(Map<String, Object?> map, String key, String path) {
  final value = _field(map, key, path);
  if (value is! String || value.trim().isEmpty) {
    throw ChargingPileGeoException(
      ChargingPileGeoFailure.invalidValue,
      '$path.$key 期望非空字符串，实际 $value',
    );
  }
  return value;
}

String? _optionalText(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw ChargingPileGeoException(
      ChargingPileGeoFailure.invalidValue,
      '$path.$key 期望字符串，实际 ${value.runtimeType}',
    );
  }
  return value;
}

double _decimal(Map<String, Object?> map, String key, String path) {
  final value = _field(map, key, path);
  if (value is num && value.isFinite) return value.toDouble();
  throw ChargingPileGeoException(
    ChargingPileGeoFailure.invalidValue,
    '$path.$key 期望有限数字，实际 $value',
  );
}

int _integer(Map<String, Object?> map, String key, String path) {
  final value = _field(map, key, path);
  if (value is int) return value;
  if (value is double && value == value.truncateToDouble() && value.isFinite) {
    return value.toInt();
  }
  throw ChargingPileGeoException(
    ChargingPileGeoFailure.invalidValue,
    '$path.$key 期望整数，实际 $value',
  );
}

List<Object?> _list(Map<String, Object?> map, String key, String path) {
  final value = _field(map, key, path);
  if (value is List) return value.cast<Object?>();
  throw ChargingPileGeoException(
    ChargingPileGeoFailure.invalidValue,
    '$path.$key 期望数组，实际 ${value.runtimeType}',
  );
}

ChargingPileLocationPrecision _precision(
  Map<String, Object?> map,
  String key,
  String path,
) {
  final raw = _text(map, key, path);
  for (final precision in ChargingPileLocationPrecision.values) {
    if (precision.name == raw) return precision;
  }
  throw ChargingPileGeoException(
    ChargingPileGeoFailure.invalidValue,
    '$path.$key 未知 precision「$raw」',
  );
}
