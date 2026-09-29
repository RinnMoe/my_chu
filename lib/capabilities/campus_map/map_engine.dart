import "../campus_places/campus_places.dart";
import "indoor_map.dart";

/// 地图引擎能力抽象（SDK 无关）。
///
/// 控制器与业务只依赖本接口，具体地图 SDK 由能力实现封装。
abstract class CampusMapEngine {
  /// 加载校区地图配置与边界；完成时表示可以继续绑定地点数据。
  Future<void> loadCampus(CampusEntry campus);

  /// 设置当前校区地点语义数据，供业务 hit-test 与地点聚焦等运行时能力使用。
  /// 不要求将地点几何渲染为底图 overlay。
  Future<void> setPlaces(CampusPlacesData places);

  /// 根据稳定地点身份聚焦并显示选中标记；信息卡和选中数据由页面/controller 状态管理。
  Future<void> selectPlace(CampusPlaceId placeId);

  /// 显示独立的选中位置标记；不渲染 CampusPlace 几何作为底图 overlay。
  Future<void> showSelectionMarker(CampusCoordinate coordinate);

  /// 显示用户主动请求的当前位置；输入与地点主数据同为 WGS84。
  Future<void> showUserLocation(CampusCoordinate coordinate);

  /// 隐藏当前位置；切换校区或清除定位状态时调用。
  Future<void> clearUserLocation();

  /// 仅将镜头聚焦到地点，不改变选中状态。
  Future<void> focusPlace(CampusPlaceId placeId);

  /// 清除 renderer 的选中标记；页面状态负责信息卡。
  Future<void> clearSelection();

  /// 镜头：中心+缩放 或 边界；[animate] 为 true 时播放过渡动画。
  Future<void> moveCamera({
    CampusCoordinate? center,
    double? zoom,
    CampusBounds? bounds,
    bool animate = false,
  });

  /// 相对缩放：正数放大、负数缩小；原生层自动夹逼到校区 min/max zoom。
  Future<void> zoomBy(double delta, {bool animate = false});

  /// 回到校区默认视图（优先紧致边界，回退到校区 bounds/initial 视野）。
  Future<void> resetToDefaultView();

  /// Enters a building using the loaded SDK-independent indoor source data.
  Future<void> enterIndoor(
    IndoorBuildingData building, {
    required int floor,
    String? selectedIndoorSpaceId,
    bool fitCamera = true,
  });

  /// Changes only the active-floor renderer filters.
  Future<void> setIndoorFloor(int floor);

  /// Selects a stable indoor-space key or clears the room highlight.
  Future<void> selectIndoorSpace(String? indoorSpaceId);

  /// Leaves indoor mode; returns false when zooming in reverses an automatic fade-out.
  Future<bool> exitIndoor({bool preserveCamera = false});

  /// 释放资源。
  Future<void> dispose();
}

/// A configuration failure that can be shown without exposing SDK internals.
///
/// The renderer may throw this exception while preparing a map, but the
/// controller remains SDK-independent and only needs the stable message.
class CampusMapConfigurationException implements Exception {
  final String message;

  const CampusMapConfigurationException(this.message);

  @override
  String toString() => message;
}
