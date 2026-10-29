/// 业务 App → 地图 的图层导航请求与结果。
///
/// 这些类型是公开 API 的一部分：业务只能表达“显示哪个图层、聚焦哪个要素”，
/// 不能拿到 Mapbox 控制器，也不能覆盖用户的长期图层偏好。
library;

/// 业务导航请求。
///
/// 语义区分：
/// - 图层可见性偏好由用户在图层面板设置并持久化；
/// - 本请求只是“这一次”的临时显示/定位/选中，不写入偏好。
class MapLayerFocusRequest {
  final String layerId;

  /// 需要定位并选中的要素；为空时只显示图层（并按图层范围取景）。
  final String? featureId;

  /// 目标校区；为空时使用地图当前校区。
  final String? campusId;

  /// 是否选中要素并展示详情（业务可关闭，只做定位）。
  final bool select;

  const MapLayerFocusRequest({
    required this.layerId,
    this.featureId,
    this.campusId,
    this.select = true,
  });
}

/// 打开地图并显示图层的结果。
enum MapLayerOpenResult { opened, unknownLayer, unsupportedCampus, openFailed }
