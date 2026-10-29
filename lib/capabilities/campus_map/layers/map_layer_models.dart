/// 通用地图图层的 SDK 无关数据模型。
///
/// 业务应用（App）只通过这些类型向地图提供地理数据；地图引擎、渲染器
/// 与图层管理面板都不认识任何具体业务字段。
library;

import "../../campus_places/campus_places.dart";

/// 要素状态的通用语义。
///
/// 业务负责把自身状态映射到这四个取值，地图只据此决定默认配色，
/// 不解释任何业务字段名（例如空闲槽位计数、占用计数）。
enum MapLayerFeatureStatus {
  /// 未知：未查询、查询失败或状态过期。默认灰色，绝不当作“不可用”。
  unknown,

  /// 可用/正常（如“确认有空闲插座”）。
  positive,

  /// 不可用/已满（如“确认没有空闲插座”）。
  negative,

  /// 中性（如“维护中”“仅信息展示”）。
  neutral,
}

/// 支持的几何类型。本期 Point 必须完整可用，其余结合渲染器能力实现。
enum MapLayerGeometryType { point, lineString, polygon }

/// 一个业务要素的几何。坐标统一为 WGS84。
///
/// 三种构造都是 const：业务可以把静态点位、线段、面声明为编译期常量，
/// 不会因为地图反复加载而重复分配。
class MapLayerGeometry {
  final MapLayerGeometryType type;
  final CampusCoordinate? _single;
  final List<CampusCoordinate>? _multi;

  const MapLayerGeometry._point(this._single)
    : type = MapLayerGeometryType.point,
      _multi = null;

  const MapLayerGeometry._line(List<CampusCoordinate> coordinates)
    : type = MapLayerGeometryType.lineString,
      _single = null,
      _multi = coordinates;

  const MapLayerGeometry._polygon(List<CampusCoordinate> ring)
    : type = MapLayerGeometryType.polygon,
      _single = null,
      _multi = ring;

  /// 单点几何。
  const MapLayerGeometry.point(CampusCoordinate coordinate)
    : this._point(coordinate);

  /// 线段几何（至少两个坐标）。
  const MapLayerGeometry.lineString(List<CampusCoordinate> coordinates)
    : this._line(coordinates);

  /// 面几何（单外环，首尾可重复）。
  const MapLayerGeometry.polygon(List<CampusCoordinate> ring)
    : this._polygon(ring);

  /// 全部坐标；Point 恒为一个元素。
  List<CampusCoordinate> get coordinates =>
      _multi ?? <CampusCoordinate>[_single!];

  /// 丢弃非法坐标后的可渲染坐标；渲染器与点击命中都只使用这份数据。
  List<CampusCoordinate> get validCoordinates => coordinates
      .where((coordinate) => coordinate.isValidWgs84)
      .toList(growable: false);

  bool get hasRenderableGeometry => switch (type) {
    MapLayerGeometryType.point => validCoordinates.isNotEmpty,
    MapLayerGeometryType.lineString => validCoordinates.length >= 2,
    MapLayerGeometryType.polygon => validCoordinates.length >= 3,
  };

  /// 单点几何的坐标（其余类型返回第一个有效坐标）。
  CampusCoordinate? get primaryCoordinate {
    final valid = validCoordinates;
    return valid.isEmpty ? null : valid.first;
  }

  /// 几何外包框，用于“点击聚合点聚焦分组”等相机请求。
  CampusBounds? get bounds {
    final valid = validCoordinates;
    if (valid.isEmpty) return null;
    var west = valid.first.longitude;
    var east = west;
    var south = valid.first.latitude;
    var north = south;
    for (final coordinate in valid.skip(1)) {
      if (coordinate.longitude < west) west = coordinate.longitude;
      if (coordinate.longitude > east) east = coordinate.longitude;
      if (coordinate.latitude < south) south = coordinate.latitude;
      if (coordinate.latitude > north) north = coordinate.latitude;
    }
    return CampusBounds(west: west, south: south, east: east, north: north);
  }
}

/// 要素所属的展示分组。
///
/// 图层可声明 [MapLayerDefinition.aggregateBelowZoom]；低于该缩放时框架把同组
/// Point 要素合并成一个聚合标记，避免几十个点位互相重叠。
class MapLayerFeatureGroup {
  final String groupId;
  final String? label;

  const MapLayerFeatureGroup({required this.groupId, this.label});
}

/// 一个 SDK 无关的地理要素。
class MapLayerFeature {
  final String featureId;
  final MapLayerGeometry geometry;

  /// 主标题（详情卡标题、默认标记文本）。
  final String? label;

  /// 副标题（详情卡第二行）。
  final String? subtitle;

  /// 地图标记上的短文本；为空时使用 [label]。
  final String? badgeText;

  final MapLayerFeatureStatus status;

  /// 显式 ARGB 颜色；为空时按 [status] 使用图层样式默认色。
  final int? color;

  final MapLayerFeatureGroup? group;

  /// 业务附加数据（例如设备对象）。框架只透传，不解释其结构。
  final Object? payload;

  const MapLayerFeature({
    required this.featureId,
    required this.geometry,
    this.label,
    this.subtitle,
    this.badgeText,
    this.status = MapLayerFeatureStatus.unknown,
    this.color,
    this.group,
    this.payload,
  });

  /// 地图标记实际使用的文本。
  String? get resolvedBadgeText => badgeText ?? label;

  bool get isPoint => geometry.type == MapLayerGeometryType.point;

  CampusCoordinate? get primaryCoordinate => geometry.primaryCoordinate;
}

/// Provider 推送的一次数据变更。
///
/// 快照式替换与增量式更新都必须能用同一类型表达，地图侧不需要区分业务语义。
class MapLayerFeatureUpdate {
  /// true：用 [features] 整体替换；false：按 featureId 增量 upsert/删除。
  final bool replacesAll;
  final List<MapLayerFeature> features;
  final List<String> removedFeatureIds;

  const MapLayerFeatureUpdate.snapshot(List<MapLayerFeature> next)
    : replacesAll = true,
      features = next,
      removedFeatureIds = const <String>[];

  const MapLayerFeatureUpdate.upsert({
    this.features = const <MapLayerFeature>[],
    this.removedFeatureIds = const <String>[],
  }) : replacesAll = false;
}

/// 一次数据加载的取消凭证。
///
/// Provider 必须在发起网络/计算请求前检查，并在响应返回后再次检查，
/// 避免已停用图层的过期响应写回状态。
class MapLayerCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const MapLayerCancelledException();
  }
}

/// 加载因图层停用或校区切换被取消。Provider 应原样抛出或返回空集合。
class MapLayerCancelledException implements Exception {
  const MapLayerCancelledException();

  @override
  String toString() => "MapLayerCancelled";
}

/// Provider 加载请求。地图只提供上下文与取消凭证，不暴露任何 SDK 类型。
class MapLayerLoadRequest {
  final String campusId;

  /// 管理器维护的代次；Provider 无需比较，管理器只用它淘汰过期响应。
  final int generation;
  final MapLayerCancellation cancellation;

  /// 当前视口范围（可空：首次加载时相机可能还没就绪）。
  final CampusBounds? viewportBounds;
  final double? zoom;

  const MapLayerLoadRequest({
    required this.campusId,
    required this.generation,
    required this.cancellation,
    this.viewportBounds,
    this.zoom,
  });
}

/// 点击命中查询（屏幕坐标，单位与地图控件一致）。使用纯数值避免向业务层暴露 SDK 类型。
class MapLayerHitQuery {
  final double x;
  final double y;

  const MapLayerHitQuery({required this.x, required this.y});
}

/// 命中结果：哪个图层的哪个要素。
class MapLayerHit {
  final String layerId;
  final String featureId;

  const MapLayerHit({required this.layerId, required this.featureId});
}

/// 规范化的图层展示要素：颜色与标记文本已解析，渲染器只负责画。
class MapLayerDisplayFeature {
  final String featureId;
  final MapLayerGeometry geometry;
  final String? badgeText;

  /// ARGB 颜色，已按状态或图层样式解析完成。
  final int color;

  /// 当前选中或聚合标记，渲染器可放大显示。
  final bool emphasized;

  /// 是否为聚合标记（点击后聚焦分组，而不是打开要素详情）。
  final bool isAggregate;

  const MapLayerDisplayFeature({
    required this.featureId,
    required this.geometry,
    required this.color,
    this.badgeText,
    this.emphasized = false,
    this.isAggregate = false,
  });
}

/// 一次相机请求。管理器不直接持有引擎，由页面转成引擎调用。
class MapLayerCameraRequest {
  final CampusBounds? bounds;
  final CampusCoordinate? center;
  final double? zoom;
  final bool animate;

  const MapLayerCameraRequest({
    this.bounds,
    this.center,
    this.zoom,
    this.animate = true,
  });
}
