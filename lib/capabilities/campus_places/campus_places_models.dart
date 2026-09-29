// 统一地点层数据模型（SDK 无关）。
//
// 业务模块与地图能力抽象层只依赖本文件中的类型；
// 地图适配实现不得把 SDK 类型泄漏到业务模块。

/// 坐标（权威 WGS84 经纬度）。
class CampusCoordinate {
  final double longitude;
  final double latitude;

  const CampusCoordinate({required this.longitude, required this.latitude});

  /// WGS84 合法性：经纬度必须在现实范围内。
  bool get isValidWgs84 =>
      longitude.isFinite &&
      latitude.isFinite &&
      longitude >= -180 &&
      longitude <= 180 &&
      latitude >= -90 &&
      latitude <= 90;

  /// 是否落在 (0,0)。外部导航与地点校验都禁止使用该坐标。
  bool get isOrigin => longitude == 0 && latitude == 0;

  factory CampusCoordinate.fromJson(List<dynamic> value) {
    if (value.length < 2 || value[0] is! num || value[1] is! num) {
      throw const FormatException("坐标格式无效");
    }
    final coordinate = CampusCoordinate(
      longitude: (value[0] as num).toDouble(),
      latitude: (value[1] as num).toDouble(),
    );
    if (!coordinate.isValidWgs84) {
      throw const FormatException("坐标超出 WGS84 范围");
    }
    return coordinate;
  }

  @override
  bool operator ==(Object other) =>
      other is CampusCoordinate &&
      other.longitude == longitude &&
      other.latitude == latitude;

  @override
  int get hashCode => Object.hash(longitude, latitude);

  @override
  String toString() => "CampusCoordinate($longitude, $latitude)";
}

/// 可浏览范围（WGS84）。
class CampusBounds {
  final double west;
  final double south;
  final double east;
  final double north;

  const CampusBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  factory CampusBounds.fromJson(Map<String, dynamic> json) {
    double value(Object? raw) => raw is num ? raw.toDouble() : double.nan;
    return CampusBounds(
      west: value(json["west"]),
      south: value(json["south"]),
      east: value(json["east"]),
      north: value(json["north"]),
    );
  }

  bool get isValidWgs84 =>
      west.isFinite &&
      south.isFinite &&
      east.isFinite &&
      north.isFinite &&
      west >= -180 &&
      east <= 180 &&
      south >= -90 &&
      north <= 90 &&
      west < east &&
      south < north;

  double get longitudeSpan => east - west;

  double get latitudeSpan => north - south;

  bool contains(CampusCoordinate c) =>
      isValidWgs84 &&
      c.isValidWgs84 &&
      c.longitude >= west &&
      c.longitude <= east &&
      c.latitude >= south &&
      c.latitude <= north;
}

/// 地点类型。
enum CampusPlaceType {
  building,
  buildingZone,
  entrance,
  gate,
  library,
  lab,
  canteen,
  dorm,
  stadium,
  courier,
  busStop,
  service,
  temporary,
  poi;

  static CampusPlaceType fromWire(String value) => switch (value) {
    "building" => building,
    "building_zone" => buildingZone,
    "entrance" => entrance,
    "gate" => gate,
    "library" => library,
    "lab" => lab,
    "canteen" => canteen,
    "dorm" => dorm,
    "stadium" => stadium,
    "courier" => courier,
    "bus_stop" => busStop,
    "service" => service,
    "temporary" => temporary,
    _ => poi,
  };

  String get wire => switch (this) {
    building => "building",
    buildingZone => "building_zone",
    entrance => "entrance",
    gate => "gate",
    library => "library",
    lab => "lab",
    canteen => "canteen",
    dorm => "dorm",
    stadium => "stadium",
    courier => "courier",
    busStop => "bus_stop",
    service => "service",
    temporary => "temporary",
    poi => "poi",
  };
}

/// 几何类型。
enum CampusGeometryType {
  point,
  polygon,
  lineString;

  static CampusGeometryType fromWire(String value) => switch (value) {
    "point" => point,
    "polygon" => polygon,
    "linestring" => lineString,
    _ => throw FormatException("未知几何类型：$value"),
  };

  String get wire => switch (this) {
    point => "point",
    polygon => "polygon",
    lineString => "linestring",
  };
}

/// 入口类型。
enum CampusEntranceKind {
  default_,
  walking,
  cycling,
  driving,
  wheelchair;

  static CampusEntranceKind fromWire(String value) => switch (value) {
    "walking" => walking,
    "cycling" => cycling,
    "driving" => driving,
    "wheelchair" => wheelchair,
    _ => default_,
  };

  String get wire => switch (this) {
    default_ => "default",
    walking => "walking",
    cycling => "cycling",
    driving => "driving",
    wheelchair => "wheelchair",
  };
}

/// 地点入口（人工核验坐标）。
class CampusEntrance {
  final String id;
  final String label;
  final CampusEntranceKind kind;
  final CampusCoordinate coordinate;
  final bool verified;

  const CampusEntrance({
    required this.id,
    required this.label,
    required this.kind,
    required this.coordinate,
    this.verified = false,
  });

  factory CampusEntrance.fromJson(Map<String, dynamic> json) => CampusEntrance(
    id: json["id"] as String? ?? "",
    label: json["label"] as String? ?? "",
    kind: CampusEntranceKind.fromWire(json["kind"] as String? ?? "default"),
    coordinate: CampusCoordinate.fromJson(json["coordinate"] as List<dynamic>),
    verified: json["verified"] as bool? ?? false,
  );
}

/// 地点（建筑/分区/入口/POI 等），对应 places.json 的 places 数组。
class CampusPlace {
  final String placeId;
  final String campusId;
  final CampusPlaceType type;
  final String name;
  final String? shortName;
  final List<String> aliases;
  final List<String> externalCodes;
  final String? parentPlaceId;
  final bool enabled;
  final CampusGeometryType geometryType;

  /// point=单点；linestring=折线；polygon=环（首尾闭合）。
  final List<CampusCoordinate> geometry;
  final CampusCoordinate? displayCoordinate;
  final String coordinateSystem;
  final String layerCategory;
  final String? iconClass;
  final int zOrder;
  final bool searchable;
  final bool navEnabled;
  final bool verified;
  final List<CampusEntrance> entrances;
  final String? description;

  const CampusPlace({
    required this.placeId,
    required this.campusId,
    required this.type,
    required this.name,
    this.shortName,
    this.aliases = const [],
    this.externalCodes = const [],
    this.parentPlaceId,
    this.enabled = true,
    this.geometryType = CampusGeometryType.point,
    this.geometry = const [],
    this.displayCoordinate,
    this.coordinateSystem = "WGS84",
    this.layerCategory = "poi",
    this.iconClass,
    this.zOrder = 0,
    this.searchable = true,
    this.navEnabled = false,
    this.verified = false,
    this.entrances = const [],
    this.description,
  });

  factory CampusPlace.fromJson(Map<String, dynamic> json) {
    final coordinateSystem = json["coordinate_system"] as String? ?? "WGS84";
    if (coordinateSystem.trim().toUpperCase() != "WGS84") {
      throw const FormatException("地点坐标系必须为 WGS84");
    }
    final rawGeometryValue = json["geometry"];
    if (rawGeometryValue != null && rawGeometryValue is! List) {
      throw const FormatException("地点几何数据格式无效");
    }
    final rawGeometry = rawGeometryValue as List<dynamic>? ?? const [];
    final geometry = <CampusCoordinate>[];
    for (final rawCoordinate in rawGeometry) {
      if (rawCoordinate is! List<dynamic>) {
        throw const FormatException("地点几何坐标格式无效");
      }
      geometry.add(CampusCoordinate.fromJson(rawCoordinate));
    }
    final rawDisplay = json["display_coordinate"];
    if (rawDisplay != null && rawDisplay is! List<dynamic>) {
      throw const FormatException("地点显示坐标格式无效");
    }
    final rawEntrances = json["entrances"];
    if (rawEntrances != null && rawEntrances is! List) {
      throw const FormatException("地点入口数据格式无效");
    }
    final geometryTypeWire = json["geometry_type"] as String? ?? "point";
    final geometryType = CampusGeometryType.fromWire(geometryTypeWire);
    final geometryMinimum = switch (geometryType) {
      CampusGeometryType.point => 1,
      CampusGeometryType.polygon => 3,
      CampusGeometryType.lineString => 2,
    };
    if (geometry.length < geometryMinimum) {
      throw FormatException("${geometryType.wire} 几何坐标数量不足");
    }
    return CampusPlace(
      placeId: json["place_id"] as String? ?? "",
      campusId: json["campus_id"] as String? ?? "",
      type: CampusPlaceType.fromWire(json["type"] as String? ?? "poi"),
      name: json["name"] as String? ?? "",
      shortName: json["short_name"] as String?,
      aliases: _stringList(json["aliases"]),
      externalCodes: _stringList(json["external_codes"]),
      parentPlaceId: json["parent_place_id"] as String?,
      enabled: json["enabled"] as bool? ?? true,
      geometryType: geometryType,
      geometry: List.unmodifiable(geometry),
      displayCoordinate:
          rawDisplay is List<dynamic>
              ? CampusCoordinate.fromJson(rawDisplay)
              : null,
      coordinateSystem: coordinateSystem,
      layerCategory: json["layer_category"] as String? ?? "poi",
      iconClass: json["icon_class"] as String?,
      zOrder: (json["z_order"] as num?)?.toInt() ?? 0,
      searchable: json["searchable"] as bool? ?? true,
      navEnabled: json["nav_enabled"] as bool? ?? false,
      verified: json["verified"] as bool? ?? false,
      entrances: _entranceList(rawEntrances),
      description: json["description"] as String?,
    );
  }
}

/// 教室（逻辑地点）：无独立室外坐标，绑定建筑/分区与入口。
class CampusClassroom {
  final String classroomId;
  final String campusId;
  final String buildingPlaceId;
  final String? zonePlaceId;
  final String? block;
  final int? zone;
  final int? floor;
  final String roomNo;

  /// Optional non-numeric room description, for example 西侧大阶梯.
  final String? roomLabel;

  /// Stable indoor-map space identity for a semantic geometry binding
  /// candidate. This is never a renderer feature ID.
  final String? indoorSpaceId;
  final bool verified;

  const CampusClassroom({
    required this.classroomId,
    required this.campusId,
    required this.buildingPlaceId,
    this.zonePlaceId,
    this.block,
    this.zone,
    this.floor,
    required this.roomNo,
    this.roomLabel,
    this.indoorSpaceId,
    this.verified = false,
  });

  factory CampusClassroom.fromJson(Map<String, dynamic> json) =>
      CampusClassroom(
        classroomId: json["classroom_id"] as String? ?? "",
        campusId: json["campus_id"] as String? ?? "",
        buildingPlaceId: json["building_place_id"] as String? ?? "",
        zonePlaceId: json["zone_place_id"] as String?,
        block: json["block"] as String?,
        zone: (json["zone"] as num?)?.toInt(),
        floor: (json["floor"] as num?)?.toInt(),
        roomNo: json["room_no"] as String? ?? "",
        roomLabel: json["room_label"] as String?,
        indoorSpaceId: json["indoor_space_id"] as String?,
        verified: json["verified"] as bool? ?? false,
      );
}

/// 校区地点数据文件（每校区 places.json）。
class CampusPlacesData {
  final String campusId;
  final List<CampusPlace> places;
  final List<CampusClassroom> classrooms;

  const CampusPlacesData({
    required this.campusId,
    this.places = const [],
    this.classrooms = const [],
  });

  factory CampusPlacesData.fromJson(
    Map<String, dynamic> json, {
    String? expectedCampusId,
  }) {
    final campusId = json["campus_id"] as String? ?? "";
    if (campusId.trim().isEmpty) {
      throw const CampusPlacesDataParseException("地点数据缺少 campus_id");
    }
    if (expectedCampusId != null && campusId != expectedCampusId) {
      throw CampusPlacesDataParseException("地点数据校区不匹配：$expectedCampusId");
    }
    final rawPlaces = json["places"];
    final rawClassrooms = json["classrooms"];
    if (rawPlaces != null && rawPlaces is! List) {
      throw const CampusPlacesDataParseException("地点列表格式无效");
    }
    if (rawClassrooms != null && rawClassrooms is! List) {
      throw const CampusPlacesDataParseException("教室列表格式无效");
    }

    final placeRecords = rawPlaces as List<dynamic>? ?? const [];
    final classroomRecords = rawClassrooms as List<dynamic>? ?? const [];
    if (placeRecords.length > CampusPlacesDataLimits.maxPlaces) {
      throw const CampusPlacesDataParseException("地点数量超出上限");
    }
    if (classroomRecords.length > CampusPlacesDataLimits.maxClassrooms) {
      throw const CampusPlacesDataParseException("教室数量超出上限");
    }

    final places = <CampusPlace>[];
    final placeIds = <String>{};
    var totalVertices = 0;
    for (final raw in placeRecords) {
      if (raw is! Map) {
        throw const CampusPlacesDataParseException("地点记录格式无效");
      }
      final record = Map<String, dynamic>.from(raw);
      final rawGeometry = record["geometry"];
      if (rawGeometry is List &&
          rawGeometry.length > CampusPlacesDataLimits.maxGeometryVertices) {
        throw const CampusPlacesDataParseException("地点几何顶点数超出上限");
      }
      final place = CampusPlace.fromJson(record);
      if (place.placeId.trim().isEmpty || !placeIds.add(place.placeId)) {
        throw const CampusPlacesDataParseException("地点 ID 为空或重复");
      }
      if (place.campusId != campusId) {
        throw CampusPlacesDataParseException("地点记录校区不匹配：${place.placeId}");
      }
      totalVertices += place.geometry.length;
      if (totalVertices > CampusPlacesDataLimits.maxTotalGeometryVertices) {
        throw const CampusPlacesDataParseException("语义几何总顶点数超出上限");
      }
      places.add(place);
    }

    final classrooms = <CampusClassroom>[];
    final classroomIds = <String>{};
    for (final raw in classroomRecords) {
      if (raw is! Map) {
        throw const CampusPlacesDataParseException("教室记录格式无效");
      }
      final classroom = CampusClassroom.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (classroom.classroomId.trim().isEmpty ||
          !classroomIds.add(classroom.classroomId)) {
        throw const CampusPlacesDataParseException("教室 ID 为空或重复");
      }
      if (classroom.campusId != campusId) {
        throw CampusPlacesDataParseException(
          "教室记录校区不匹配：${classroom.classroomId}",
        );
      }
      classrooms.add(classroom);
    }

    for (final place in places) {
      final parentId = place.parentPlaceId;
      if (parentId != null &&
          parentId.isNotEmpty &&
          !placeIds.contains(parentId)) {
        throw CampusPlacesDataParseException("地点父级不存在：${place.placeId}");
      }
    }
    for (final classroom in classrooms) {
      if (classroom.buildingPlaceId.isNotEmpty &&
          !placeIds.contains(classroom.buildingPlaceId)) {
        throw CampusPlacesDataParseException(
          "教室建筑不存在：${classroom.classroomId}",
        );
      }
      final zonePlaceId = classroom.zonePlaceId;
      if (zonePlaceId != null &&
          zonePlaceId.isNotEmpty &&
          !placeIds.contains(zonePlaceId)) {
        throw CampusPlacesDataParseException(
          "教室分区不存在：${classroom.classroomId}",
        );
      }
    }

    return CampusPlacesData(
      campusId: campusId,
      places: List.unmodifiable(places),
      classrooms: List.unmodifiable(classrooms),
    );
  }

  CampusPlace? placeById(String placeId) {
    for (final place in places) {
      if (place.placeId == placeId && place.enabled) return place;
    }
    return null;
  }

  CampusClassroom? classroomById(String classroomId) {
    for (final classroom in classrooms) {
      if (classroom.classroomId == classroomId) return classroom;
    }
    return null;
  }

  /// 按标准化后的编码精确查找人工教室记录。
  CampusClassroom? classroomByNormalizedCode(String normalizedCode) {
    for (final classroom in classrooms) {
      if (classroom.classroomId.toLowerCase() == normalizedCode) {
        return classroom;
      }
    }
    return null;
  }
}

class CampusPlacesDataLimits {
  static const int maxPlaces = 10000;
  static const int maxClassrooms = 20000;
  static const int maxGeometryVertices = 4096;
  static const int maxTotalGeometryVertices = 100000;

  const CampusPlacesDataLimits._();
}

class CampusPlacesDataParseException implements Exception {
  final String message;

  const CampusPlacesDataParseException(this.message);

  @override
  String toString() => "CampusPlacesDataParseException: $message";
}

List<String> _stringList(Object? value) =>
    value is List<dynamic>
        ? value.whereType<String>().toList(growable: false)
        : const [];

List<CampusEntrance> _entranceList(Object? value) =>
    value is List<dynamic>
        ? value
            .map((raw) {
              if (raw is! Map) {
                throw const FormatException("地点入口记录格式无效");
              }
              return CampusEntrance.fromJson(Map<String, dynamic>.from(raw));
            })
            .toList(growable: false)
        : const [];
