/// 内置地图图层的统一注册入口。
///
/// 新增一个带地图能力的业务 App 时只需要：
/// 1. 在该 App 目录内提供 `MapLayerDefinition` 与 `MapLayerProvider`；
/// 2. 在本文件的 [builtInMapLayerDefinitions] 中追加一条；
/// 3. 在应用启动阶段调用 [registerBuiltInMapLayers]（已由 `main` 完成）。
///
/// 地图引擎、地图页面与图层面板都不需要修改。
library;

import "package:flutter/foundation.dart";

import "../capabilities/campus_map/campus_map_capability.dart";
import "app_registry.dart";
import "charging_pile/charging_pile_map_layer.dart";

/// 编译期注册的地图图层定义。
///
/// 与 `AppRegistry.builtIns` 一样是编译期清单：仓库不支持运行时加载或远程图层。
List<MapLayerDefinition> builtInMapLayerDefinitions() => <MapLayerDefinition>[
  chargingPileMapLayerDefinition(),
];

bool _registered = false;

/// 注册全部内置图层，并注入“所属应用必须存在”的校验器。
///
/// 重复调用是安全的：已注册的图层会被跳过。注册失败只记录，不影响应用启动。
void registerBuiltInMapLayers({MapLayerRegistry? registry}) {
  if (_registered) return;
  _registered = true;
  final target = registry ?? MapLayerRegistry.shared;
  target.configureOwnerAppResolver(
    (ownerAppId) => AppRegistry.builtInById(ownerAppId) != null,
  );
  for (final definition in builtInMapLayerDefinitions()) {
    if (target.byId(definition.layerId) != null) continue;
    try {
      target.register(definition);
    } on MapLayerRegistrationException catch (error) {
      debugPrint(
        "map layer registration failed: ${definition.layerId} (${error.error.name})",
      );
    }
  }
}

/// 仅供测试重置注册状态。
@visibleForTesting
void resetBuiltInMapLayerRegistration() {
  _registered = false;
}
