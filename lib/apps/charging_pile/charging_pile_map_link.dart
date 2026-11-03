/// 充电桩 App → 地图 的通用图层导航入口。
///
/// 只依赖地图公开 Capability，不接触 Mapbox；地图侧的图层实现（Provider、
/// 要素映射、详情卡）在 `charging_pile_map_layer.dart` 中，二者通过本文件的
/// 稳定 ID 关联，避免页面与图层定义互相 import 形成环。
library;

import "package:flutter/material.dart";

import "../../capabilities/campus_map/campus_map_capability.dart";

/// 图层 ID（跨版本稳定）。
const String chargingPileLayerId = "charging.piles";

/// 所属业务应用 ID。
const String chargingPileMapOwnerAppId = "feature.charging.pile";

/// 充电桩图层覆盖的校区：应用认识的四个校区。
///
/// 源站会陆续接入新校区，分区到校区的归属由目录解析时的校区清单匹配决定，
/// 这里给全集，避免新增校区后图层在对应地图上直接不出现。
const Set<String> chargingPileMapCampusIds = {
  "weishui",
  "beiyuan",
  "yanta",
  "xiaozhai",
};

/// 打开校园地图、切到该设备所属校区、显示充电桩图层并聚焦该设备。
Future<MapLayerOpenResult> openChargingPileOnMap(
  BuildContext context, {
  required String deviceId,
  required String campusId,
}) => campusMapCapability.openLayerFocus(
  context,
  MapLayerFocusRequest(
    layerId: chargingPileLayerId,
    featureId: deviceId,
    campusId: campusId,
  ),
);
