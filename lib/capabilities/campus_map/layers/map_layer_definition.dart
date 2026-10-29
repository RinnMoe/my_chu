/// 图层声明：业务应用注册到地图的全部元数据与能力。
library;

import "package:flutter/widgets.dart";

import "map_layer_models.dart";
import "map_layer_provider.dart";

/// 图层通用样式。业务只在必要处覆盖，地图不解释业务字段。
class MapLayerStyle {
  /// 未知状态默认灰色：未查询、查询失败或状态过期都必须落在这里。
  final int unknownColor;
  final int positiveColor;
  final int negativeColor;
  final int neutralColor;

  final double circleRadius;
  final double emphasizedCircleRadius;
  final double strokeWidth;
  final int strokeColor;

  /// 是否在地图上显示标记文本。
  final bool showLabels;

  /// 低于该缩放只显示标记、不显示文本，避免文字互相压盖。
  final double labelMinZoom;

  /// 图层自身可见的缩放区间。
  final double minZoom;
  final double maxZoom;

  const MapLayerStyle({
    this.unknownColor = 0xFF9E9E9E,
    this.positiveColor = 0xFF1D9E75,
    this.negativeColor = 0xFFE24B4A,
    this.neutralColor = 0xFF1A73E8,
    this.circleRadius = 7,
    this.emphasizedCircleRadius = 10,
    this.strokeWidth = 2,
    this.strokeColor = 0xFFFFFFFF,
    this.showLabels = true,
    this.labelMinZoom = 15.5,
    this.minZoom = 0,
    this.maxZoom = 24,
  });

  int colorFor(MapLayerFeatureStatus status) => switch (status) {
    MapLayerFeatureStatus.positive => positiveColor,
    MapLayerFeatureStatus.negative => negativeColor,
    MapLayerFeatureStatus.neutral => neutralColor,
    MapLayerFeatureStatus.unknown => unknownColor,
  };
}

/// 要素被选中后交给业务应用的信息。
class MapLayerFeatureSelection {
  final MapLayerDefinition definition;
  final MapLayerFeature feature;
  final String campusId;

  const MapLayerFeatureSelection({
    required this.definition,
    required this.feature,
    required this.campusId,
  });

  MapLayerFeatureStatus get status => feature.status;
  Object? get payload => feature.payload;
}

/// 点击交互策略。地图只负责命中与转发，业务决定后续行为。
class MapLayerInteraction {
  /// 是否参与点击命中查询。false 的图层只做展示。
  final bool tapSelectable;

  /// 点击后是否由地图展示通用详情卡（标题/副标题 + 打开应用）。
  final bool showsDetailCard;

  /// 业务详情构建器；提供后优先于通用详情卡。返回 null 时回退到通用卡。
  final Widget Function(
    BuildContext context,
    MapLayerFeatureSelection selection,
  )?
  detailBuilder;

  /// 从地图跳转到业务应用（通常定位到对应要素）。
  final Future<bool> Function(
    BuildContext context,
    MapLayerFeatureSelection selection,
  )?
  openOwnerApp;

  const MapLayerInteraction({
    this.tapSelectable = true,
    this.showsDetailCard = false,
    this.detailBuilder,
    this.openOwnerApp,
  });
}

/// 一个可注册的地图图层。
///
/// 注册与业务页面生命周期解耦：只要业务应用注册了定义，图层面板就能发现它，
/// 用户不需要先打开该应用。
class MapLayerDefinition {
  /// 全局唯一稳定 ID，建议使用 `owner.layer` 形式（如 `transit.routes`）。
  final String layerId;

  /// 所属业务应用 ID，必须存在于宿主应用注册表。
  final String ownerAppId;

  final String name;
  final String? description;

  /// 图层面板图标。
  final IconData icon;

  /// 支持该图层的校区；为空表示所有校区。
  final Set<String> campusIds;

  /// 首次使用时的默认可见性。
  final bool defaultVisible;

  /// 展示优先级，数值越大越靠上（聚合后的图层排序依据）。
  final int priority;

  final MapLayerStyle style;

  /// 低于该缩放时按 [MapLayerFeature.group] 聚合成一个标记；null 表示不聚合。
  final double? aggregateBelowZoom;

  final MapLayerInteraction interaction;

  /// Provider 工厂。注册时不创建实例，图层首次可见时才调用，避免常驻内存。
  final MapLayerProvider Function() providerFactory;

  const MapLayerDefinition({
    required this.layerId,
    required this.ownerAppId,
    required this.name,
    required this.providerFactory,
    this.description,
    this.icon = const IconData(0xe55f, fontFamily: "MaterialIcons"),
    this.campusIds = const <String>{},
    this.defaultVisible = false,
    this.priority = 0,
    this.style = const MapLayerStyle(),
    this.aggregateBelowZoom,
    this.interaction = const MapLayerInteraction(),
  });

  bool supportsCampus(String campusId) =>
      campusIds.isEmpty || campusIds.contains(campusId);

  /// 注册前的最小校验；抛 [ArgumentError] 表示定义本身不合法。
  void validate() {
    if (layerId.trim().isEmpty) {
      throw ArgumentError.value(layerId, "layerId", "图层 ID 不能为空");
    }
    if (layerId != layerId.trim()) {
      throw ArgumentError.value(layerId, "layerId", "图层 ID 不能包含首尾空白");
    }
    if (ownerAppId.trim().isEmpty) {
      throw ArgumentError.value(ownerAppId, "ownerAppId", "所属应用 ID 不能为空");
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, "name", "图层名称不能为空");
    }
    final aggregateZoom = aggregateBelowZoom;
    if (aggregateZoom != null && !aggregateZoom.isFinite) {
      throw ArgumentError.value(
        aggregateZoom,
        "aggregateBelowZoom",
        "聚合阈值必须是有限数值",
      );
    }
  }
}
