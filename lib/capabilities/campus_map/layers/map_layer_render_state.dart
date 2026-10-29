/// 渲染状态：图层管理器交给渲染器的、已解析完成的展示数据。
///
/// 渲染器只读取本文件与 `map_layer_models.dart`，不认识任何业务定义或数据源。
library;

import "map_layer_definition.dart";
import "map_layer_models.dart";

/// 一个可见图层交给渲染器的完整描述。
class MapLayerRenderState {
  final String layerId;
  final int priority;
  final MapLayerStyle style;

  /// 是否参与点击命中。false 的图层只做展示。
  final bool interactive;

  final List<MapLayerDisplayFeature> features;

  /// 当前选中要素 ID（渲染器据此加粗/高亮，不参与业务逻辑）。
  final String? selectedFeatureId;

  const MapLayerRenderState({
    required this.layerId,
    required this.priority,
    required this.style,
    required this.features,
    this.interactive = false,
    this.selectedFeatureId,
  });

  bool get isEmpty => features.isEmpty;
}
