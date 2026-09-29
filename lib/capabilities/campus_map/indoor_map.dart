import "dart:convert";

import "package:flutter/services.dart";

import "../campus_places/campus_places.dart";

typedef IndoorAssetTextLoader = Future<String> Function(String path);

Future<String> _loadIndoorAsset(String path) => rootBundle.loadString(path);

const String wx3BuildingPlaceId = "weishui.osm.way.1234004781";
const String wx2BuildingPlaceId = "weishui.osm.way.1234004782";
const String wm2BuildingPlaceId = "weishui.osm.way.440689410";

/// True for semantic features that represent a physical building footprint.
bool isBuildingFootprint(CampusPlace place) =>
    place.enabled &&
    place.geometryType == CampusGeometryType.polygon &&
    (place.type == CampusPlaceType.building ||
        place.type == CampusPlaceType.buildingZone ||
        place.layerCategory == "building");

/// SDK-independent indoor building metadata loaded with its geometry on entry.
class IndoorMapContext {
  final String buildingId;
  final String campusId;
  final String buildingPlaceId;
  final String displayName;
  final List<int> floors;
  final int defaultFloor;
  final CampusBounds bounds;
  final int minZoom;
  final int maxZoom;
  final String georeferenceStatus;
  final bool publicationVerified;

  const IndoorMapContext({
    required this.buildingId,
    required this.campusId,
    required this.buildingPlaceId,
    required this.displayName,
    required this.floors,
    required this.defaultFloor,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.georeferenceStatus,
    required this.publicationVerified,
  });

  factory IndoorMapContext.fromJson(Map<String, dynamic> json) {
    final rawBounds = json["bounds"];
    final rawFloors = json["floors"];
    final camera = json["recommendedCamera"];
    final georeference = json["georeference"];
    if (json["schemaVersion"] != 1 ||
        rawBounds is! Map ||
        rawFloors is! List ||
        camera is! Map ||
        georeference is! Map) {
      throw const FormatException("室内地图清单结构无效");
    }

    final floors = <int>[];
    for (final value in rawFloors) {
      if (value is! num ||
          !value.toDouble().isFinite ||
          value.toInt() != value) {
        throw const FormatException("室内地图楼层列表无效");
      }
      floors.add(value.toInt());
    }
    if (floors.toSet().length != floors.length) {
      throw const FormatException("室内地图楼层重复");
    }
    floors.sort();
    final defaultFloor = _integer(json["defaultFloor"]);
    final bounds = CampusBounds.fromJson(Map<String, dynamic>.from(rawBounds));
    final minZoom = _integer(camera["minZoomIndoor"]);
    final maxZoom = _integer(camera["maxZoomIndoor"]);
    final buildingId = _string(json["buildingId"]);
    final campusId = _string(json["campusId"]);
    final buildingPlaceId = _string(json["buildingPlaceId"]);
    final displayName = _string(json["displayName"]);
    final georeferenceStatus = _string(georeference["status"]);
    if (buildingId.isEmpty ||
        campusId.isEmpty ||
        buildingPlaceId.isEmpty ||
        displayName.isEmpty ||
        floors.isEmpty ||
        floors.any((floor) => floor < 1) ||
        defaultFloor == null ||
        !floors.contains(defaultFloor) ||
        !bounds.isValidWgs84 ||
        minZoom == null ||
        maxZoom == null ||
        minZoom > maxZoom ||
        georeferenceStatus.isEmpty) {
      throw const FormatException("室内地图清单字段无效");
    }

    return IndoorMapContext(
      buildingId: buildingId,
      campusId: campusId,
      buildingPlaceId: buildingPlaceId,
      displayName: displayName,
      floors: List.unmodifiable(floors),
      defaultFloor: defaultFloor,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      georeferenceStatus: georeferenceStatus,
      publicationVerified: json["publicationVerified"] == true,
    );
  }
}

/// Runtime WGS84 data passed to a map engine only while indoor mode is active.
class IndoorBuildingData {
  final IndoorMapContext context;
  final Map<String, dynamic> runtimeGeoJson;
  final Map<String, int> _spaceFloors;
  final Map<String, String> _roomSpaceIdsByCode;
  final Map<String, CampusBounds> _roomBoundsBySpaceId;

  const IndoorBuildingData._({
    required this.context,
    required this.runtimeGeoJson,
    required Map<String, int> spaceFloors,
    required Map<String, String> roomSpaceIdsByCode,
    required Map<String, CampusBounds> roomBoundsBySpaceId,
  }) : _spaceFloors = spaceFloors,
       _roomSpaceIdsByCode = roomSpaceIdsByCode,
       _roomBoundsBySpaceId = roomBoundsBySpaceId;

  int? floorForSpace(String indoorSpaceId) => _spaceFloors[indoorSpaceId];

  bool containsSpace(String indoorSpaceId) =>
      _spaceFloors.containsKey(indoorSpaceId);

  String? spaceIdForRoomCode(String classroomCode) =>
      _roomSpaceIdsByCode[classroomCode.trim().toUpperCase()];

  CampusBounds? boundsForRoomSpace(String indoorSpaceId) =>
      _roomBoundsBySpaceId[indoorSpaceId];
}

/// Current indoor presentation state. Geometry stays in the data provider.
class IndoorViewState {
  final IndoorMapContext context;
  final int activeFloor;
  final String? selectedIndoorSpaceId;

  const IndoorViewState({
    required this.context,
    required this.activeFloor,
    this.selectedIndoorSpaceId,
  });

  IndoorViewState copyWith({
    int? activeFloor,
    String? selectedIndoorSpaceId,
    bool clearSelectedIndoorSpace = false,
  }) => IndoorViewState(
    context: context,
    activeFloor: activeFloor ?? this.activeFloor,
    selectedIndoorSpaceId:
        clearSelectedIndoorSpace
            ? null
            : (selectedIndoorSpaceId ?? this.selectedIndoorSpaceId),
  );
}

/// Bundled data provider for supported indoor buildings. Geometry is loaded
/// lazily when a building or one of its classrooms is selected.
class CampusIndoorMapRepository {
  static const Map<String, String> _manifestAssets = <String, String>{
    wx3BuildingPlaceId: "assets/maps/indoor/wx3/indoor_building_manifest.json",
    wx2BuildingPlaceId: "assets/maps/indoor/wx2/indoor_building_manifest.json",
    wm2BuildingPlaceId: "assets/maps/indoor/wm2/indoor_building_manifest.json",
  };

  final IndoorAssetTextLoader loadText;
  final Map<String, Future<IndoorBuildingData?>> _loads = {};

  CampusIndoorMapRepository({IndoorAssetTextLoader? loadText})
    : loadText = loadText ?? _loadIndoorAsset;

  bool supportsBuildingPlaceId(String buildingPlaceId) =>
      _manifestAssets.containsKey(buildingPlaceId);

  Future<IndoorBuildingData?> loadForBuildingPlaceId(String buildingPlaceId) {
    final path = _manifestAssets[buildingPlaceId];
    if (path == null) return Future<IndoorBuildingData?>.value(null);
    return _loads.putIfAbsent(buildingPlaceId, () => _load(path));
  }

  Future<IndoorBuildingData?> _load(String manifestPath) async {
    final manifestJson = _decodeObject(await loadText(manifestPath));
    final context = IndoorMapContext.fromJson(manifestJson);
    String? expectedPlaceId;
    for (final entry in _manifestAssets.entries) {
      if (entry.value == manifestPath) {
        expectedPlaceId = entry.key;
        break;
      }
    }
    if (expectedPlaceId == null || context.buildingPlaceId != expectedPlaceId) {
      throw const FormatException("室内地图建筑标识不匹配");
    }

    final runtimeGeometry = manifestJson["runtimeGeometry"];
    if (runtimeGeometry is! Map) {
      throw const FormatException("室内地图缺少运行时几何配置");
    }
    final relativePath = _string(runtimeGeometry["bundledGeoJson"]);
    final segments = relativePath.replaceAll("\\", "/").split("/");
    if (segments.isEmpty ||
        segments.any((part) => part.isEmpty || part == "." || part == "..")) {
      throw const FormatException("室内地图资源路径无效");
    }
    final basePath = manifestPath.substring(0, manifestPath.lastIndexOf("/"));
    final runtimeJson = _decodeObject(
      await loadText("$basePath/$relativePath"),
    );
    if (runtimeJson["type"] != "FeatureCollection" ||
        runtimeJson["features"] is! List) {
      throw const FormatException("室内地图 GeoJSON 格式无效");
    }

    final spaceFloors = <String, int>{};
    final roomSpaceIdsByCode = <String, String>{};
    final roomBoundsBySpaceId = <String, CampusBounds>{};
    final roomSpaceIds = <String>{};
    final roomCount = _integer(manifestJson["roomCount"]);
    for (final rawFeature in runtimeJson["features"] as List) {
      if (rawFeature is! Map) {
        throw const FormatException("室内地图要素格式无效");
      }
      final properties = rawFeature["properties"];
      if (properties is! Map) {
        throw const FormatException("室内地图要素属性格式无效");
      }
      final feature = Map<String, dynamic>.from(properties);
      final floor = _integer(feature["floor"]);
      final renderClass = _string(feature["render_class"]);
      if (feature["building_place_id"] != context.buildingPlaceId ||
          floor == null ||
          !context.floors.contains(floor) ||
          renderClass.isEmpty) {
        throw const FormatException("室内地图要素与清单不匹配");
      }
      final indoorSpaceId = _string(feature["indoor_space_id"]);
      if (renderClass == "room" && indoorSpaceId.isEmpty) {
        throw const FormatException("室内教室缺少稳定空间标识");
      }
      if (renderClass == "room" && !roomSpaceIds.add(indoorSpaceId)) {
        throw const FormatException("室内教室空间标识重复");
      }
      if (renderClass == "room") {
        final bounds = _boundsForGeoJsonGeometry(rawFeature["geometry"]);
        if (bounds != null) roomBoundsBySpaceId[indoorSpaceId] = bounds;
      }
      final roomCode = _string(feature["room_code"]).trim().toUpperCase();
      if (renderClass == "room" && roomCode.isNotEmpty) {
        final previousSpaceId = roomSpaceIdsByCode[roomCode];
        if (previousSpaceId != null && previousSpaceId != indoorSpaceId) {
          throw const FormatException("室内教室编号重复");
        }
        roomSpaceIdsByCode[roomCode] = indoorSpaceId;
      }
      if (indoorSpaceId.isNotEmpty) {
        final previousFloor = spaceFloors[indoorSpaceId];
        if (previousFloor != null && previousFloor != floor) {
          throw const FormatException("室内空间跨楼层重复");
        }
        spaceFloors[indoorSpaceId] = floor;
      }
    }
    if (roomCount != null && roomCount != roomSpaceIds.length) {
      throw const FormatException("室内地图房间数与空间标识数不匹配");
    }

    return IndoorBuildingData._(
      context: context,
      runtimeGeoJson: runtimeJson,
      spaceFloors: Map.unmodifiable(spaceFloors),
      roomSpaceIdsByCode: Map.unmodifiable(roomSpaceIdsByCode),
      roomBoundsBySpaceId: Map.unmodifiable(roomBoundsBySpaceId),
    );
  }
}

CampusBounds? _boundsForGeoJsonGeometry(Object? rawGeometry) {
  if (rawGeometry is! Map) return null;
  final coordinates = rawGeometry["coordinates"];
  if (coordinates is! List) return null;

  var west = double.infinity;
  var south = double.infinity;
  var east = double.negativeInfinity;
  var north = double.negativeInfinity;
  void includeCoordinates(Object? value) {
    if (value is! List) return;
    if (value.length >= 2 && value[0] is num && value[1] is num) {
      final longitude = (value[0] as num).toDouble();
      final latitude = (value[1] as num).toDouble();
      final coordinate = CampusCoordinate(
        longitude: longitude,
        latitude: latitude,
      );
      if (!coordinate.isValidWgs84) return;
      if (longitude < west) west = longitude;
      if (longitude > east) east = longitude;
      if (latitude < south) south = latitude;
      if (latitude > north) north = latitude;
      return;
    }
    for (final child in value) {
      includeCoordinates(child);
    }
  }

  includeCoordinates(coordinates);
  final bounds = CampusBounds(
    west: west,
    south: south,
    east: east,
    north: north,
  );
  return bounds.isValidWgs84 ? bounds : null;
}

Map<String, dynamic> _decodeObject(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map) throw const FormatException("室内地图 JSON 格式无效");
  return Map<String, dynamic>.from(decoded);
}

String _string(Object? value) => value is String ? value.trim() : "";

int? _integer(Object? value) =>
    value is num && value.toDouble().isFinite ? value.toInt() : null;
