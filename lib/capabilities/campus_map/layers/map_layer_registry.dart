/// 地图图层注册表：统一注册、发现与注销。
///
/// 依赖方向为「业务 App → 地图公开 Capability → 图层管理层」，
/// 因此注册表不认识任何具体业务模块，也不依赖具体地图 SDK。
library;

import "package:flutter/foundation.dart";

import "map_layer_definition.dart";

/// 注册失败原因。
enum MapLayerRegistrationError {
  duplicateLayerId,
  unknownOwnerApp,
  invalidDefinition,
}

/// 注册失败异常；调用方按 [error] 分类处理，不需要解析文案。
class MapLayerRegistrationException implements Exception {
  final MapLayerRegistrationError error;
  final String message;

  const MapLayerRegistrationException(this.error, this.message);

  @override
  String toString() => "MapLayerRegistrationException(${error.name}): $message";
}

/// 图层注册表。
///
/// 典型的接入方式：业务应用提供 [MapLayerDefinition]，在应用启动时注册一次。
/// 注册与业务页面生命周期无关，图层面板因此能看到用户从未打开过的 App 的图层。
class MapLayerRegistry extends ChangeNotifier {
  MapLayerRegistry({bool Function(String ownerAppId)? ownerAppExists})
    : _ownerAppExists = ownerAppExists;

  /// 进程内共享实例，由宿主在启动阶段注入应用注册表校验器。
  static final MapLayerRegistry shared = MapLayerRegistry();

  final Map<String, MapLayerDefinition> _definitions =
      <String, MapLayerDefinition>{};
  bool Function(String ownerAppId)? _ownerAppExists;

  /// 注入宿主应用注册表校验器（能力层不能反向依赖应用层）。
  void configureOwnerAppResolver(bool Function(String ownerAppId) resolver) {
    _ownerAppExists = resolver;
  }

  MapLayerDefinition? byId(String layerId) => _definitions[layerId];

  Iterable<MapLayerDefinition> get definitions => _definitions.values;

  int get length => _definitions.length;

  bool get isEmpty => _definitions.isEmpty;

  /// 适用于指定校区的图层，按展示优先级降序、再按名称排序。
  List<MapLayerDefinition> forCampus(String campusId) {
    final result = _definitions.values
        .where((definition) => definition.supportsCampus(campusId))
        .toList(growable: false);
    return result..sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
    });
  }

  /// 注册一个图层。
  ///
  /// 重复的 [MapLayerDefinition.layerId] 视为错误而不是静默覆盖：两个业务模块
  /// 抢同一个 ID 时必须暴露出来。注销后重新注册同一 ID 是允许的。
  void register(MapLayerDefinition definition) {
    try {
      definition.validate();
    } on ArgumentError catch (error) {
      throw MapLayerRegistrationException(
        MapLayerRegistrationError.invalidDefinition,
        "${definition.layerId}: ${error.message}",
      );
    }
    final exists = _ownerAppExists;
    if (exists != null && !exists(definition.ownerAppId)) {
      throw MapLayerRegistrationException(
        MapLayerRegistrationError.unknownOwnerApp,
        "${definition.layerId}: 未注册的应用 ${definition.ownerAppId}",
      );
    }
    if (_definitions.containsKey(definition.layerId)) {
      throw MapLayerRegistrationException(
        MapLayerRegistrationError.duplicateLayerId,
        "图层 ${definition.layerId} 已注册",
      );
    }
    _definitions[definition.layerId] = definition;
    notifyListeners();
  }

  /// 批量注册。任一失败时回滚本批已注册项，避免半注册状态。
  void registerAll(Iterable<MapLayerDefinition> definitions) {
    final added = <String>[];
    try {
      for (final definition in definitions) {
        register(definition);
        added.add(definition.layerId);
      }
    } catch (_) {
      for (final layerId in added) {
        _definitions.remove(layerId);
      }
      notifyListeners();
      rethrow;
    }
  }

  /// 注销图层；返回是否存在过。Provider 生命周期由管理器负责。
  bool unregister(String layerId) {
    final removed = _definitions.remove(layerId);
    if (removed != null) notifyListeners();
    return removed != null;
  }

  @visibleForTesting
  void clear() {
    if (_definitions.isEmpty) return;
    _definitions.clear();
    notifyListeners();
  }
}
