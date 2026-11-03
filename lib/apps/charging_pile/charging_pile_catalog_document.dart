import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'charging_pile_models.dart';

/// 把站点分区名的前缀（`渭水`）解析成本仓库的校区 ID；认不出返回 null。
typedef ChargingPileCampusResolver = String? Function(String prefix);

/// 目录文档解析失败的原因。上层据此区分「资源损坏」「版本过新」「单条脏数据」。
enum ChargingPileCatalogFailure {
  /// JSON 本身无法解析。
  malformedJson,

  /// `schema` 不是当前代码认识的版本（通常意味着文档比客户端新）。
  unsupportedSchema,

  /// 必需字段缺失或整体结构不符。
  missingField,

  /// 字段存在但类型/取值非法。
  invalidValue,
}

class ChargingPileCatalogException implements Exception {
  const ChargingPileCatalogException(this.failure, this.detail);

  final ChargingPileCatalogFailure failure;

  /// 面向开发者的定位信息（JSON 路径 + 期望值），不含任何凭证。
  final String detail;

  @override
  String toString() =>
      'ChargingPileCatalogException(${failure.name}): $detail';
}

/// 解析严格度。
///
/// * [strict] —— 随包内置快照用。任何不一致都抛错，保证随包数据是对的。
/// * [tolerant] —— 远端/缓存快照用。远端数据**永远可能比客户端新**：
///   未知字段忽略、未知分区降级到「未分区」、单条脏数据丢弃，
///   只有「结构不认识」或「丢得太多」才整份拒绝。
enum ChargingPileCatalogStrictness { strict, tolerant }

/// 站点 `catalog.json`（schema 1）的内存模型。
///
/// 这份文档是**站点发布的公开数据**，不是 MyCHU 自有格式：设备清单、分区、
/// 每台桩的坐标都在里面。客户端只做两件事 —— 解析，以及把 GCJ-02 转成
/// WGS84（本仓库的地图资源是 WGS84）。
class ChargingPileCatalogDocument {
  ChargingPileCatalogDocument._({
    required this.siteVersion,
    required this.catalogVersion,
    required this.campusIds,
    required this.areas,
    required this.devices,
  }) : _deviceById = {for (final device in devices) device.id: device};

  /// 站点 `catalog.json` 的 `schema`；不认识就整份拒绝。
  static const int supportedSchema = 1;

  /// 随包内置快照的资源路径。
  static const String assetPath =
      'assets/charging_pile/charging_pile_catalog.json';

  /// 站点发布的目录地址。远端刷新只打这一个请求。
  static final Uri remoteUri = Uri.parse(
    'https://chd-charge.pages.dev/catalog.json',
  );

  /// 宽容解析允许丢弃的单条脏数据比例上限；超过即整份拒绝。
  static const double _maxDroppedRatio = 0.1;

  /// 目录为空、需要一个「随便哪个校区」时的兜底。
  static const String defaultCampusId = 'weishui';

  /// 认不出校区的分区用它标记：这类设备进列表但不落图，绝不硬塞到某个校区底图上。
  static const String unknownCampusId = '';

  /// 内置兜底表：站点 `location` 前缀 → 本仓库校区 ID。
  ///
  /// 正常路径是 [parse] 的 `campusResolver`，由校区清单（`assets/maps/campuses.json`
  /// 的 display_name 与 aliases）动态匹配，站点新增校区时不用改代码。这张表只在
  /// 清单读不出来时兜底。
  static const Map<String, String> campusByLocationPrefix = <String, String>{
    '渭水': 'weishui',
    '北院': 'beiyuan',
    '雁塔': 'yanta',
    '小寨': 'xiaozhai',
  };

  /// 由站点分区全名（`渭水-北门`）派生校区 ID。
  ///
  /// 先问 [resolver]（通常是校区清单派生的匹配器），再退回内置表；都认不出时返回
  /// [unknownCampusId]。**不能**回落到 [defaultCampusId]：那会把雁塔的桩画到渭水
  /// 校区的底图上，比不显示更糟。
  static String campusIdFor(
    String location, {
    ChargingPileCampusResolver? resolver,
  }) {
    final prefix = _prefixOf(location);
    if (prefix.isEmpty) return unknownCampusId;
    final resolved = resolver?.call(prefix);
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return campusByLocationPrefix[prefix] ?? unknownCampusId;
  }

  /// `渭水-北门` → `渭水`。
  static String _prefixOf(String location) {
    final index = location.indexOf('-');
    final prefix = (index < 0 ? location : location.substring(0, index)).trim();
    return prefix;
  }

  /// 站点页脚版本（例如 `v2.67`），仅用于诊断与变更提示。
  final String siteVersion;

  /// 内容指纹：原文 SHA-256 的前 12 位。站点不提供数据版本号，
  /// 用它判断「拉到的这份和本机那份是不是同一份」。
  final String catalogVersion;

  /// 目录里出现过的校区（由分区前缀派生）。
  final Set<String> campusIds;

  /// 按站点给出的顺序排列。
  final List<ChargingPileArea> areas;
  final List<ChargingPileDevice> devices;

  final Map<String, ChargingPileDevice> _deviceById;

  int get deviceCount => devices.length;

  ChargingPileDevice? deviceFor(String deviceId) => _deviceById[deviceId];

  List<ChargingPileDevice> devicesInArea(String areaId) =>
      List<ChargingPileDevice>.unmodifiable(
        devices.where((device) => device.area.areaId == areaId),
      );

  /// 落图设备（有坐标的）。没有坐标的设备只进列表，不编造位置。
  Iterable<ChargingPileDevice> get mappableDevices =>
      devices.where((device) => device.point != null);

  /// 由设备列表直接构造一份目录（测试与离线场景用，不经过站点 JSON）。
  ///
  /// 分区按设备首次出现的顺序去重；没有坐标的设备照常保留，只是不落图。
  factory ChargingPileCatalogDocument.fromDevices(
    List<ChargingPileDevice> devices, {
    String catalogVersion = 'test',
    String siteVersion = '',
  }) {
    final areas = <ChargingPileArea>[];
    for (final device in devices) {
      if (!areas.contains(device.area)) areas.add(device.area);
    }
    return ChargingPileCatalogDocument._(
      siteVersion: siteVersion,
      catalogVersion: catalogVersion,
      campusIds: Set<String>.unmodifiable(
        areas.map((area) => area.campusId),
      ),
      areas: List<ChargingPileArea>.unmodifiable(areas),
      devices: List<ChargingPileDevice>.unmodifiable(devices),
    );
  }

  /// 解析站点目录。失败抛 [ChargingPileCatalogException]。
  static ChargingPileCatalogDocument parse(
    String jsonText, {
    ChargingPileCatalogStrictness strictness =
        ChargingPileCatalogStrictness.strict,
    ChargingPileCampusResolver? campusResolver,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.malformedJson,
        'JSON 无法解析：${error.message}',
      );
    }
    final root = _asMap(decoded, r'$');

    final schema = _asInt(root['schema'], r'$.schema');
    if (schema != supportedSchema) {
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.unsupportedSchema,
        '\$.schema=$schema，本代码只支持 $supportedSchema',
      );
    }
    final coordSystem = _asString(root['coordSystem'], r'$.coordSystem');
    if (coordSystem != null && coordSystem != 'GCJ-02') {
      // 站点换坐标系等于换了语义，不能猜。
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.unsupportedSchema,
        '\$.coordSystem=$coordSystem，本代码只支持 GCJ-02',
      );
    }

    final rawAreas = _asList(root['areas'], r'$.areas');
    if (rawAreas.isEmpty) {
      throw const ChargingPileCatalogException(
        ChargingPileCatalogFailure.invalidValue,
        r'$.areas 为空',
      );
    }
    final areas = <ChargingPileArea>[];
    final seenAreas = <String>{};
    for (final (index, raw) in rawAreas.indexed) {
      final area = _parseArea(raw, '\$.areas[$index]', campusResolver);
      if (!seenAreas.add(area.areaId)) {
        if (strictness == ChargingPileCatalogStrictness.strict) {
          throw ChargingPileCatalogException(
            ChargingPileCatalogFailure.invalidValue,
            '分区 id 重复：${area.areaId}',
          );
        }
        continue;
      }
      areas.add(area);
    }

    final rawDevices = _asList(root['devices'], r'$.devices');
    if (rawDevices.isEmpty) {
      throw const ChargingPileCatalogException(
        ChargingPileCatalogFailure.invalidValue,
        r'$.devices 为空',
      );
    }

    final areaById = {for (final area in areas) area.areaId: area};
    final devices = <ChargingPileDevice>[];
    final seenDevices = <String>{};
    var dropped = 0;
    for (final (index, raw) in rawDevices.indexed) {
      final path = '\$.devices[$index]';
      try {
        final map = _asMap(raw, path);
        final id = _asString(map['id'], '$path.id');
        final code = _asString(map['code'], '$path.code');
        final name = _asString(map['name'], '$path.name');
        final areaKey = _asString(map['area'], '$path.area');
        final location = _asString(map['location'], '$path.location');
        if (id == null || id.isEmpty || code == null || code.isEmpty) {
          throw ChargingPileCatalogException(
            ChargingPileCatalogFailure.missingField,
            '$path 缺少 id/code',
          );
        }
        if (!seenDevices.add(id)) {
          throw ChargingPileCatalogException(
            ChargingPileCatalogFailure.invalidValue,
            '设备 id 重复：$id',
          );
        }
        // `area` 是分区键，`location` 是分区全名；两者任一命中即可。
        var area = areaById[location];
        if (area == null) {
          for (final candidate in areas) {
            if (candidate.key == areaKey) {
              area = candidate;
              break;
            }
          }
        }
        if (area == null) {
          if (strictness == ChargingPileCatalogStrictness.strict) {
            throw ChargingPileCatalogException(
              ChargingPileCatalogFailure.invalidValue,
              '$id 的分区「$areaKey / $location」不在 areas 里',
            );
          }
          // 远端目录里的新分区客户端还不认识：保留设备，归入「未分区」。
          area = ChargingPileArea.unknown;
        }
        final source = ChargingPileSource.tryParse(
          _asString(map['src'], '$path.src'),
        );
        if (source == null &&
            strictness == ChargingPileCatalogStrictness.strict) {
          throw ChargingPileCatalogException(
            ChargingPileCatalogFailure.invalidValue,
            '$id 的 src 未知',
          );
        }
        devices.add(
          ChargingPileDevice(
            id: id,
            code: code,
            name: name ?? code,
            area: area,
            source: source ?? ChargingPileSource.zhumang,
            portCount: _asIntOrNull(map['ports'], '$path.ports'),
            point: _parsePoint(map['lng'], map['lat'], path, strictness),
          ),
        );
      } on ChargingPileCatalogException {
        if (strictness == ChargingPileCatalogStrictness.strict) rethrow;
        dropped += 1;
      }
    }

    if (devices.isEmpty) {
      throw const ChargingPileCatalogException(
        ChargingPileCatalogFailure.invalidValue,
        '所有设备条目都不可用',
      );
    }
    if (dropped > devices.length * _maxDroppedRatio) {
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.invalidValue,
        '丢弃了 $dropped 条设备，超过容差',
      );
    }

    return ChargingPileCatalogDocument._(
      siteVersion: _asString(root['siteVersion'], r'$.siteVersion') ?? '',
      catalogVersion: sha256
          .convert(utf8.encode(jsonText))
          .toString()
          .substring(0, 12),
      campusIds: Set<String>.unmodifiable(
        areas.map((area) => area.campusId),
      ),
      areas: List<ChargingPileArea>.unmodifiable(areas),
      devices: List<ChargingPileDevice>.unmodifiable(devices),
    );
  }

  static ChargingPileArea _parseArea(
    Object? raw,
    String path,
    ChargingPileCampusResolver? campusResolver,
  ) {
    final map = _asMap(raw, path);
    final location = _asString(map['location'], '$path.location');
    final key = _asString(map['key'], '$path.key');
    final name = _asString(map['name'], '$path.name');
    if (location == null || location.isEmpty) {
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.missingField,
        '$path.location 缺失',
      );
    }
    return ChargingPileArea(
      areaId: location,
      key: key ?? location,
      name: (name == null || name.isEmpty) ? location : name,
      campusId: campusIdFor(location, resolver: campusResolver),
      statsKey: key,
    );
  }

  /// 设备点位：`lng` / `lat` 两个数字。
  static ChargingPileGeoPoint? _parsePoint(
    Object? rawLng,
    Object? rawLat,
    String path,
    ChargingPileCatalogStrictness strictness,
  ) {
    if (rawLng == null || rawLat == null) return null;
    try {
      final lng = _asNum(rawLng, '$path.lng');
      final lat = _asNum(rawLat, '$path.lat');
      if (lng.abs() > 180 || lat.abs() > 90) {
        throw ChargingPileCatalogException(
          ChargingPileCatalogFailure.invalidValue,
          '$path 坐标越界',
        );
      }
      final wgs = gcj02ToWgs84(lng, lat);
      return ChargingPileGeoPoint(
        latitude: wgs.latitude,
        longitude: wgs.longitude,
      );
    } on ChargingPileCatalogException {
      // 坐标坏掉只影响「能不能落图」，不该让整份目录作废。
      if (strictness == ChargingPileCatalogStrictness.strict) rethrow;
      return null;
    }
  }

  static Map<Object?, Object?> _asMap(Object? raw, String path) {
    if (raw is Map) return raw;
    throw ChargingPileCatalogException(
      ChargingPileCatalogFailure.missingField,
      '$path 不是对象',
    );
  }

  static List<Object?> _asList(Object? raw, String path) {
    if (raw is List) return raw;
    throw ChargingPileCatalogException(
      ChargingPileCatalogFailure.missingField,
      '$path 不是数组',
    );
  }

  static String? _asString(Object? raw, String path) {
    if (raw == null) return null;
    if (raw is String) return raw;
    throw ChargingPileCatalogException(
      ChargingPileCatalogFailure.invalidValue,
      '$path 不是字符串',
    );
  }

  static int _asInt(Object? raw, String path) {
    final value = _asIntOrNull(raw, path);
    if (value == null) {
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.missingField,
        '$path 缺失',
      );
    }
    return value;
  }

  static int? _asIntOrNull(Object? raw, String path) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double && raw == raw.roundToDouble()) return raw.toInt();
    throw ChargingPileCatalogException(
      ChargingPileCatalogFailure.invalidValue,
      '$path 不是整数',
    );
  }

  static double _asNum(Object? raw, String path) {
    if (raw is num) return raw.toDouble();
    throw ChargingPileCatalogException(
      ChargingPileCatalogFailure.invalidValue,
      '$path 不是数字',
    );
  }
}

/// GCJ-02 → WGS84。
///
/// 站点与高德/腾讯底图用 GCJ-02，本仓库的地图资源是 WGS84；直接叠加会偏
/// 400~600 米。这里做标准逆变换（Krasovsky 1940 椭球，定点迭代 3 次），
/// 与站点生成坐标时用的正变换互为逆运算。
({double latitude, double longitude}) gcj02ToWgs84(
  double lng,
  double lat,
) {
  var wgsLng = lng;
  var wgsLat = lat;
  for (var i = 0; i < 3; i++) {
    final delta = _gcjDelta(wgsLng, wgsLat);
    wgsLng = lng - delta.longitude;
    wgsLat = lat - delta.latitude;
  }
  return (latitude: wgsLat, longitude: wgsLng);
}

/// GCJ-02 相对 WGS84 的偏移量（度）。
({double latitude, double longitude}) _gcjDelta(double lng, double lat) {
  const a = 6378245.0;
  const ee = 0.00669342162296594323;
  final dLat = _transformLat(lng - 105.0, lat - 35.0);
  final dLng = _transformLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  return (
    latitude: (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi),
    longitude: (dLng * 180.0) / (a / sqrtMagic * math.cos(radLat) * math.pi),
  );
}

double _transformLat(double x, double y) {
  var ret =
      -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret +=
      (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (160.0 * math.sin(y / 12.0 * math.pi) +
          320 * math.sin(y * math.pi / 30.0)) *
      2.0 /
      3.0;
  return ret;
}

double _transformLng(double x, double y) {
  var ret =
      300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret +=
      (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (150.0 * math.sin(x / 12.0 * math.pi) +
          300.0 * math.sin(x / 30.0 * math.pi)) *
      2.0 /
      3.0;
  return ret;
}
