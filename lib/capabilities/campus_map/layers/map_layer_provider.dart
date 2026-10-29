/// 业务应用实现的地图图层数据提供接口。
///
/// 生命周期由 [MapLayerManager] 驱动：图层可见时 `activate` → `loadFeatures`，
/// 图层关闭、切换校区或页面销毁时 `deactivate`。Provider 不持有地图对象，
/// 也不负责绘制。
library;

import "map_layer_models.dart";

/// 数据提供者。实现方只关心自己的数据来源与状态映射。
///
/// 约束：
/// - 只返回 WGS84 坐标；
/// - 不得在 [loadFeatures] 之外启动无界轮询；
/// - [deactivate] 后必须停止自身产生的加载、订阅与计时器；
/// - 与独立应用共享 Repository 时，必须使用引用计数而不是直接取消他人的请求。
abstract class MapLayerProvider {
  /// 按校区加载一份完整快照。取消时抛出 [MapLayerCancelledException]。
  Future<List<MapLayerFeature>> loadFeatures(MapLayerLoadRequest request);

  /// 订阅数据变化（状态轮询结果、本地编辑等）。返回 null 表示不订阅。
  ///
  /// 流只在该图层激活期间被监听，停用时管理器会取消订阅。
  Stream<MapLayerFeatureUpdate>? watchFeatures(String campusId) => null;

  /// 图层变为可见时调用，可在此获取共享数据源的消费者引用。
  void activate(String campusId) {}

  /// 图层不可见或被销毁时调用，必须释放 [activate] 获取的资源。
  Future<void> deactivate() async {}

  /// 用户显式刷新（图层刷新入口）。
  Future<void> refresh() async {}

  /// 要素被选中（地图点击或业务导航聚焦）时通知；[featureId] 为空表示取消选中。
  ///
  /// 业务可据此按需刷新单个要素，而不必刷新整层数据。
  void onFeatureSelected(String? featureId) {}

  /// 进程内最终释放；之后不会再有加载请求。
  void dispose() {}
}
