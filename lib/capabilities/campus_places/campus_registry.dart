import "dart:convert";
import "package:flutter/services.dart";
import "campus_places_models.dart";

/// 资产文本加载器（测试可注入）。
typedef AssetTextLoader = Future<String> Function(String path);

Future<String> _rootBundleLoad(String path) => rootBundle.loadString(path);

/// 校区注册表条目。
class CampusEntry {
  final String campusId;
  final String officialGroup;
  final String displayName;
  final List<String> aliases;
  final String? address;
  final bool enabled;
  final String? placesPath;
  final CampusBounds? bounds;
  final CampusCoordinate? initialCenter;
  final double? initialZoom;
  final double? minZoom;
  final double? maxZoom;
  final int sortOrder;
  final String? defaultPlaceId;
  final String coordinateSystem;
  final String? boundaryOsmType;
  final String? boundaryOsmId;

  const CampusEntry({
    required this.campusId,
    this.officialGroup = "",
    required this.displayName,
    this.aliases = const [],
    this.address,
    this.enabled = true,
    this.placesPath,
    this.bounds,
    this.initialCenter,
    this.initialZoom,
    this.minZoom,
    this.maxZoom,
    this.sortOrder = 0,
    this.defaultPlaceId,
    this.coordinateSystem = "WGS84",
    this.boundaryOsmType,
    this.boundaryOsmId,
  });

  bool get hasValidViewport {
    if (coordinateSystem.trim().toUpperCase() != "WGS84") return false;
    if (bounds == null || !bounds!.isValidWgs84) return false;
    if (initialCenter != null && !initialCenter!.isValidWgs84) return false;
    if (initialCenter != null && !bounds!.contains(initialCenter!)) {
      return false;
    }
    final zooms = <double?>[initialZoom, minZoom, maxZoom];
    if (zooms.any(
      (zoom) => zoom != null && (!zoom.isFinite || zoom < 0 || zoom > 19),
    )) {
      return false;
    }
    if (minZoom != null && maxZoom != null && minZoom! > maxZoom!) {
      return false;
    }
    if (initialZoom != null &&
        ((minZoom != null && initialZoom! < minZoom!) ||
            (maxZoom != null && initialZoom! > maxZoom!))) {
      return false;
    }
    return true;
  }

  factory CampusEntry.fromJson(Map<String, dynamic> json) {
    final rawBounds = json["bounds"];
    final rawCenter = json["initial_center"];
    if (rawBounds != null && rawBounds is! Map) {
      throw const FormatException("校区边界格式无效");
    }
    if (rawCenter != null && rawCenter is! List<dynamic>) {
      throw const FormatException("校区初始中心格式无效");
    }
    return CampusEntry(
      campusId: json["campus_id"] as String? ?? "",
      officialGroup: json["official_group"] as String? ?? "",
      displayName: json["display_name"] as String? ?? "",
      aliases: _stringList(json["aliases"]),
      address: json["address"] as String?,
      enabled: json["enabled"] as bool? ?? true,
      placesPath: json["places_path"] as String?,
      bounds:
          rawBounds is Map
              ? CampusBounds.fromJson(Map<String, dynamic>.from(rawBounds))
              : null,
      initialCenter:
          rawCenter is List<dynamic>
              ? CampusCoordinate.fromJson(rawCenter)
              : null,
      initialZoom: _optionalFiniteNumber(json["initial_zoom"], "initial_zoom"),
      minZoom: _optionalFiniteNumber(json["min_zoom"], "min_zoom"),
      maxZoom: _optionalFiniteNumber(json["max_zoom"], "max_zoom"),
      sortOrder: (json["sort_order"] as num?)?.toInt() ?? 0,
      defaultPlaceId: json["default_place_id"] as String?,
      coordinateSystem: json["coordinate_system"] as String? ?? "WGS84",
      boundaryOsmType: json["boundary_osm_type"] as String?,
      boundaryOsmId: json["boundary_osm_id"] as String?,
    );
  }
}

double? _optionalFiniteNumber(Object? value, String field) {
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException("$field 数值无效");
  }
  return value.toDouble();
}

List<String> _stringList(Object? value) =>
    value is List<dynamic>
        ? value.whereType<String>().toList(growable: false)
        : const [];

/// 校区注册表（assets/maps/campuses.json）。
class CampusRegistry {
  static const int maxCampuses = 64;

  final List<CampusEntry> campuses;

  const CampusRegistry({required this.campuses});

  factory CampusRegistry.fromJson(Map<String, dynamic> json) {
    final rawCampuses = json["campuses"];
    if (rawCampuses != null && rawCampuses is! List) {
      throw const FormatException("校区列表格式无效");
    }
    final records = rawCampuses as List<dynamic>? ?? const [];
    if (records.length > maxCampuses) {
      throw const FormatException("校区数量超出上限");
    }
    final campuses = <CampusEntry>[];
    final campusIds = <String>{};
    for (final raw in records) {
      if (raw is! Map) throw const FormatException("校区记录格式无效");
      final campus = CampusEntry.fromJson(Map<String, dynamic>.from(raw));
      if (campus.campusId.trim().isEmpty || !campusIds.add(campus.campusId)) {
        throw const FormatException("校区 ID 为空或重复");
      }
      if (campus.enabled && !campus.hasValidViewport) {
        throw FormatException("校区视野配置无效：${campus.campusId}");
      }
      campuses.add(campus);
    }
    return CampusRegistry(campuses: List.unmodifiable(campuses));
  }

  List<CampusEntry> get enabledCampuses {
    final list = campuses.where((c) => c.enabled).toList(growable: false);
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  CampusEntry? byId(String campusId) {
    for (final campus in campuses) {
      if (campus.campusId == campusId) return campus;
    }
    return null;
  }
}

/// 从资产加载注册表。
class CampusRegistryLoader {
  static const String defaultAsset = "assets/maps/campuses.json";

  final AssetTextLoader loadText;

  CampusRegistryLoader({AssetTextLoader? loadText})
    : loadText = loadText ?? _rootBundleLoad;

  Future<CampusRegistry> load({String asset = defaultAsset}) async {
    final text = await loadText(asset);
    return CampusRegistry.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }
}

/// 地点数据仓库：按校区加载 places.json。
class PlacesRepository {
  final AssetTextLoader loadText;

  PlacesRepository({AssetTextLoader? loadText})
    : loadText = loadText ?? _rootBundleLoad;

  /// 返回 null 表示未配置地点数据或解析失败（调用方进入错误态）。
  Future<CampusPlacesData?> loadForCampus(CampusEntry campus) async {
    final path = campus.placesPath;
    if (path == null || path.isEmpty) return null;
    try {
      final text = await loadText(path);
      final json = jsonDecode(text) as Map<String, dynamic>;
      return CampusPlacesData.fromJson(json, expectedCampusId: campus.campusId);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } catch (_) {
      return null;
    }
  }
}
