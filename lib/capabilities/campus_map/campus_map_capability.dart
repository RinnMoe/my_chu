import "dart:async";

import "package:flutter/material.dart";

import "../campus_places/campus_places.dart";
import "layers/layers.dart";
import "mapbox/mapbox_campus_map_page.dart";

export "campus_map_models.dart";
export "layers/layers.dart";
export "../campus_places/campus_places.dart"
    show UnifiedPlaceRequest, PlaceResolutionResult, PlaceCandidate;

/// Shared campus-map capability facade (SDK independent).
///
/// Business modules only depend on MyCHU place-domain types and the generic map
/// layer types. The concrete renderer is currently the official Mapbox Maps SDK
/// for Flutter; no business module receives a Mapbox controller.
class CampusMapCapability {
  MapboxCampusMapPage createPage({
    Key? key,
    bool asRootTab = false,
    UnifiedPlaceRequest? destination,
    MapLayerFocusRequest? layerFocus,
    MapLayerRegistry? layerRegistry,
    MapLayerManager? layerManager,
  }) => MapboxCampusMapPage(
    key: key,
    asRootTab: asRootTab,
    destination: destination,
    layerFocus: layerFocus,
    layerRegistry: layerRegistry,
    layerManager: layerManager,
  );

  Future<void> openRequest(BuildContext context, UnifiedPlaceRequest request) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapboxCampusMapPage(destination: request),
      ),
    );
  }

  /// 打开校园地图并显示业务图层，可选定位/选中某个要素。
  ///
  /// 与用户长期保存的图层可见性偏好互不影响：这里只是本次导航的临时请求。
  /// 可同步判定的失败（图层未注册、目标校区不适用）直接返回结果，不打开地图。
  Future<MapLayerOpenResult> openLayerFocus(
    BuildContext context,
    MapLayerFocusRequest request, {
    MapLayerRegistry? layerRegistry,
    MapLayerManager? layerManager,
  }) async {
    final registry = layerRegistry ?? MapLayerRegistry.shared;
    final definition = registry.byId(request.layerId);
    if (definition == null) return MapLayerOpenResult.unknownLayer;
    final campusId = request.campusId;
    if (campusId != null && !definition.supportsCampus(campusId)) {
      return MapLayerOpenResult.unsupportedCampus;
    }
    if (!context.mounted) return MapLayerOpenResult.openFailed;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => MapboxCampusMapPage(
                layerFocus: request,
                layerRegistry: registry,
                layerManager: layerManager,
              ),
        ),
      ),
    );
    return MapLayerOpenResult.opened;
  }
}

final campusMapCapability = CampusMapCapability();
