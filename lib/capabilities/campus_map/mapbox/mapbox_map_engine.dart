import "dart:async";
import "dart:convert";
import "dart:ui" as ui;

import "package:mapbox_maps_flutter/mapbox_maps_flutter.dart";

import "../../campus_places/campus_places.dart";
import "../campus_semantic_hit_tester.dart";
import "../indoor_map.dart";
import "../map_engine.dart";
import "mapbox_map_config.dart";

const String _selectionSource = "mychu-selection";
const String _selectionLayer = "mychu-selection-circle";
const String _userLocationSource = "mychu-user-location";
const String _userLocationLayer = "mychu-user-location-circle";
const String _tapInteractionId = "mychu-semantic-map-tap";
const String _indoorSource = "mychu-indoor-source";
// Keep indoor layers renderable slightly below the 17.5 auto-exit threshold
// so their opacity transition can finish when the user zooms out.
const double _indoorLayerMinZoom = 17;
const int _indoorOpacityTransitionMilliseconds = 240;
const String _indoorFloorShellLayer = "mychu-indoor-floor-shell";
const String _indoorVoidLayer = "mychu-indoor-void";
const String _indoorCorridorLayer = "mychu-indoor-corridor";
const String _indoorRoomLayer = "mychu-indoor-room";
const String _indoorFacilityLayer = "mychu-indoor-facility";
const String _indoorFacilityDetailLayer = "mychu-indoor-facility-detail";
const String _indoorWallLayer = "mychu-indoor-wall";
const String _indoorRoomLabelLayer = "mychu-indoor-room-label";
const String _indoorFacilityLabelLayer = "mychu-indoor-facility-label";
const String _indoorSelectionLayer = "mychu-indoor-selection";
const List<String> _indoorLayers = <String>[
  _indoorFloorShellLayer,
  _indoorVoidLayer,
  _indoorCorridorLayer,
  _indoorRoomLayer,
  _indoorFacilityLayer,
  _indoorFacilityDetailLayer,
  _indoorWallLayer,
  _indoorRoomLabelLayer,
  _indoorFacilityLabelLayer,
  _indoorSelectionLayer,
];

/// Mapbox implementation of the SDK-independent campus map engine.
///
/// Mapbox owns the basemap, style, glyph, sprite and tile delivery. MyCHU
/// continues to own semantic campus places and resolves taps against that
/// domain data so plugin integrations stay independent from Mapbox feature IDs.
class MapboxMapEngine implements CampusMapEngine {
  final MapboxMapConfig config;

  MapboxMap? _controller;
  CampusEntry? _loadedCampus;
  CampusPlacesData? _places;
  bool _prepared = false;
  bool _styleReady = false;
  bool _overlayReady = false;
  bool _indoorLayersReady = false;
  bool _styleFallbackAttempted = false;
  int _loadGeneration = 0;
  String? _mapInstanceToken;
  ui.Size? _viewportSize;

  CampusCoordinate? _selectionCoordinate;
  CampusCoordinate? _userLocationCoordinate;
  CampusCoordinate? _pendingFocus;
  IndoorBuildingData? _indoorBuilding;
  int? _indoorFloor;
  String? _selectedIndoorSpaceId;
  CameraOptions? _outdoorCameraBeforeIndoor;
  bool _restoreDefaultOutdoorCamera = false;
  bool _fitCameraToIndoor = false;
  bool _indoorCameraBoundsConfigured = false;
  int _indoorVisibilityGeneration = 0;
  final CampusSemanticHitTester _hitTester = const CampusSemanticHitTester();

  void Function(CampusPlaceId placeId, CampusCoordinate coordinate)? onPlaceTap;
  void Function(String indoorSpaceId)? onIndoorSpaceTap;
  void Function(
    CampusCoordinate center,
    double zoom,
    CampusBounds? viewportBounds,
  )?
  onCameraIdle;

  MapboxMapEngine({this.config = const MapboxMapConfig()});

  bool get isPrepared => _prepared;
  String get styleUri => config.resolvedStyleUri;
  String get mapInstanceToken =>
      "$_loadGeneration:${_loadedCampus?.campusId ?? "none"}:$styleUri";

  @override
  Future<void> loadCampus(CampusEntry campus) async {
    final generation = ++_loadGeneration;
    if (campus.coordinateSystem != "WGS84") {
      throw StateError("仅支持 WGS84 校区坐标：${campus.campusId}");
    }

    config.configureSdk();
    if (generation != _loadGeneration) return;

    _controller = null;
    _mapInstanceToken = null;
    _viewportSize = null;
    _loadedCampus = campus;
    _places = null;
    _prepared = true;
    _styleReady = false;
    _overlayReady = false;
    _indoorLayersReady = false;
    _styleFallbackAttempted = false;
    _selectionCoordinate = null;
    _userLocationCoordinate = null;
    _pendingFocus = null;
    _indoorBuilding = null;
    _indoorFloor = null;
    _selectedIndoorSpaceId = null;
    _outdoorCameraBeforeIndoor = null;
    _restoreDefaultOutdoorCamera = false;
    _indoorCameraBoundsConfigured = false;
    _fitCameraToIndoor = false;
  }

  /// Called by [MapWidget.onMapCreated].
  void attach(
    MapboxMap controller, {
    String? instanceToken,
    ui.Size? viewportSize,
  }) {
    final token = instanceToken ?? mapInstanceToken;
    _controller = controller;
    _mapInstanceToken = token;
    if (viewportSize != null) _viewportSize = viewportSize;
    controller.addInteraction(
      TapInteraction.onMap(
        (context) => unawaited(handleTap(context, instanceToken: token)),
      ),
      interactionID: _tapInteractionId,
    );
    // Mapbox's native logo and attribution remain visible. Only the
    // attribution button accent is softened through the SDK-supported color
    // setting; do not cover or replace the required wordmark.
    unawaited(
      controller.attribution.updateSettings(
        AttributionSettings(iconColor: MapboxMapConfig.attributionIconColor),
      ),
    );
    unawaited(
      controller.scaleBar.updateSettings(ScaleBarSettings(enabled: false)),
    );
    unawaited(_configureCameraBounds(controller, instanceToken: token));
  }

  void updateViewportSize(ui.Size size, {String? instanceToken}) {
    if (!_isCurrentInstance(instanceToken) ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    _viewportSize = size;
  }

  /// Called after the configured Mapbox style is fully loaded.
  Future<void> handleStyleLoaded([String? instanceToken]) async {
    if (!_isCurrentInstance(instanceToken) || _styleReady) return;
    try {
      await _ensureOverlayLayers(instanceToken: instanceToken);
      if (!_isCurrentInstance(instanceToken)) return;
      _styleReady = true;
      await _applySelection();
      if (!_isCurrentInstance(instanceToken)) return;
      await _applyUserLocation();
      if (!_isCurrentInstance(instanceToken)) return;
      final indoorBuilding = _indoorBuilding;
      if (indoorBuilding == null) {
        await resetToDefaultView();
      } else {
        if (_restoreDefaultOutdoorCamera &&
            _outdoorCameraBeforeIndoor == null) {
          await resetToDefaultView();
          if (!_isCurrentInstance(instanceToken)) return;
          await _saveOutdoorCamera();
          _restoreDefaultOutdoorCamera = false;
        }
        await _ensureIndoorLayers(instanceToken: instanceToken);
        if (!_isCurrentInstance(instanceToken)) return;
        await _setIndoorLayerOpacity(1, instanceToken: instanceToken);
        if (!_isCurrentInstance(instanceToken)) return;
        if (_fitCameraToIndoor) {
          await _configureIndoorCamera(
            indoorBuilding.context,
            selectedSpaceBounds:
                _selectedIndoorSpaceId == null
                    ? null
                    : indoorBuilding.boundsForRoomSpace(
                      _selectedIndoorSpaceId!,
                    ),
            animate: false,
            instanceToken: instanceToken,
          );
        }
      }
      if (!_isCurrentInstance(instanceToken)) return;

      final focus = _pendingFocus;
      if (focus != null) {
        await _focusCoordinate(focus, animate: false);
      }
    } catch (_) {
      // A style reload can invalidate runtime source/layer handles. The next
      // style-loaded callback retries the idempotent setup instead of leaving
      // the page with an unhandled callback future.
      if (!_isCurrentInstance(instanceToken)) return;
      _styleReady = false;
      _overlayReady = false;
    }
  }

  /// Falls back to Mapbox Standard when an optional custom style cannot load.
  Future<void> handleMapLoadError(
    MapLoadingErrorEventData event, [
    String? instanceToken,
  ]) async {
    if (!_isCurrentInstance(instanceToken)) return;
    if (!shouldFallbackForMapLoadError(event.type)) return;
    final controller = _controller;
    if (!config.hasCustomStyle ||
        _styleFallbackAttempted ||
        controller == null ||
        !_prepared) {
      return;
    }
    _styleFallbackAttempted = true;
    _styleReady = false;
    _overlayReady = false;
    _indoorLayersReady = false;
    if (!_isCurrentInstance(instanceToken)) return;
    await controller.loadStyleURI(MapboxStyles.STANDARD);
  }

  static bool shouldFallbackForMapLoadError(MapLoadErrorType type) =>
      type == MapLoadErrorType.STYLE;

  @override
  Future<void> setPlaces(CampusPlacesData places) async {
    _places = places;
  }

  @override
  Future<void> selectPlace(CampusPlaceId placeId) async {
    final coordinate = _placeCenter(placeId);
    if (coordinate == null) return;
    _pendingFocus = coordinate;
    await _focusCoordinate(coordinate, animate: true);
    await showSelectionMarker(coordinate);
  }

  @override
  Future<void> focusPlace(CampusPlaceId placeId) async {
    final coordinate = _placeCenter(placeId);
    if (coordinate == null) return;
    _pendingFocus = coordinate;
    await _focusCoordinate(coordinate, animate: true);
  }

  @override
  Future<void> showSelectionMarker(CampusCoordinate coordinate) async {
    _selectionCoordinate = coordinate;
    await _applySelection();
  }

  @override
  Future<void> showUserLocation(CampusCoordinate coordinate) async {
    _userLocationCoordinate = coordinate;
    await _applyUserLocation();
  }

  @override
  Future<void> clearUserLocation() async {
    _userLocationCoordinate = null;
    await _applyUserLocation();
  }

  @override
  Future<void> clearSelection() async {
    _selectionCoordinate = null;
    _pendingFocus = null;
    await _applySelection();
  }

  @override
  Future<void> moveCamera({
    CampusCoordinate? center,
    double? zoom,
    CampusBounds? bounds,
    bool animate = false,
  }) async {
    final controller = _controller;
    if (controller == null) return;

    if (center != null) {
      await _setCamera(
        CameraOptions(center: _point(center), zoom: zoom),
        animate: animate,
      );
      return;
    }

    if (bounds != null) {
      final camera = await controller.cameraForCoordinateBounds(
        _coordinateBounds(bounds),
        MbxEdgeInsets(top: 32, left: 32, bottom: 32, right: 32),
        null,
        null,
        null,
        null,
      );
      await _setCamera(camera, animate: animate);
    }
  }

  @override
  Future<void> zoomBy(double delta, {bool animate = false}) async {
    final controller = _controller;
    if (controller == null || delta == 0) return;
    final state = await controller.getCameraState();
    final campus = _loadedCampus;
    final indoor = _indoorBuilding?.context;
    final minZoom = (campus?.minZoom ?? 15).toDouble();
    final maxZoom = (indoor?.maxZoom ?? campus?.maxZoom ?? 19).toDouble();
    final target = (state.zoom + delta).clamp(minZoom, maxZoom).toDouble();
    await _setCamera(CameraOptions(zoom: target), animate: animate);
  }

  @override
  Future<void> resetToDefaultView() async {
    final campus = _loadedCampus;
    if (campus == null || _controller == null) return;
    if (campus.initialCenter != null) {
      await moveCamera(
        center: campus.initialCenter,
        zoom: campus.initialZoom ?? 15,
      );
      return;
    }
    if (campus.bounds != null) {
      await moveCamera(bounds: campus.bounds);
    }
  }

  @override
  Future<void> enterIndoor(
    IndoorBuildingData building, {
    required int floor,
    String? selectedIndoorSpaceId,
    bool fitCamera = true,
  }) async {
    final campus = _loadedCampus;
    if (campus == null || building.context.campusId != campus.campusId) return;
    if (!building.context.floors.contains(floor)) return;
    if (selectedIndoorSpaceId != null &&
        building.floorForSpace(selectedIndoorSpaceId) != floor) {
      return;
    }

    final visibilityGeneration = ++_indoorVisibilityGeneration;
    final isSameBuilding =
        _indoorBuilding?.context.buildingPlaceId ==
        building.context.buildingPlaceId;
    final wasFittingCamera = _fitCameraToIndoor;
    if (!isSameBuilding && _indoorBuilding != null) {
      await _setIndoorLayerOpacity(0);
      await Future<void>.delayed(
        const Duration(milliseconds: _indoorOpacityTransitionMilliseconds + 40),
      );
      if (visibilityGeneration != _indoorVisibilityGeneration) return;
      await _removeIndoorLayers();
    }
    if (fitCamera && !wasFittingCamera) {
      if (_controller != null && _styleReady) {
        await _saveOutdoorCamera();
        _restoreDefaultOutdoorCamera = false;
      } else {
        _outdoorCameraBeforeIndoor = null;
        _restoreDefaultOutdoorCamera = true;
      }
    } else if (!fitCamera && wasFittingCamera) {
      // Keep the current camera exactly where the user left it. The wider
      // outdoor bounds are restored when indoor mode exits.
      _outdoorCameraBeforeIndoor = null;
      _restoreDefaultOutdoorCamera = false;
    }

    _indoorBuilding = building;
    _indoorFloor = floor;
    _selectedIndoorSpaceId = selectedIndoorSpaceId;
    _fitCameraToIndoor = fitCamera;
    _selectionCoordinate = null;
    _pendingFocus = null;
    final instanceToken = _mapInstanceToken;
    if (!_styleReady || !_isCurrentInstance(instanceToken)) return;
    await _applySelection();
    if (!_isCurrentInstance(instanceToken)) return;
    await _ensureIndoorLayers(instanceToken: instanceToken);
    if (!_isCurrentInstance(instanceToken)) return;
    await _setIndoorLayerOpacity(1, instanceToken: instanceToken);
    if (!_isCurrentInstance(instanceToken)) return;
    if (fitCamera) {
      await _configureIndoorCamera(
        building.context,
        selectedSpaceBounds:
            selectedIndoorSpaceId == null
                ? null
                : building.boundsForRoomSpace(selectedIndoorSpaceId),
        animate: true,
        instanceToken: instanceToken,
      );
    } else {
      await _applyIndoorFilters(instanceToken: instanceToken);
    }
  }

  @override
  Future<void> setIndoorFloor(int floor) async {
    final building = _indoorBuilding;
    if (building == null || !building.context.floors.contains(floor)) return;
    _indoorFloor = floor;
    await _applyIndoorFilters(instanceToken: _mapInstanceToken);
  }

  @override
  Future<void> selectIndoorSpace(String? indoorSpaceId) async {
    final building = _indoorBuilding;
    final floor = _indoorFloor;
    if (building == null ||
        (indoorSpaceId != null &&
            building.floorForSpace(indoorSpaceId) != floor)) {
      return;
    }
    _selectedIndoorSpaceId = indoorSpaceId;
    await _applyIndoorFilters(instanceToken: _mapInstanceToken);
  }

  @override
  Future<bool> exitIndoor({bool preserveCamera = false}) async {
    if (_indoorBuilding == null) return true;
    final visibilityGeneration = ++_indoorVisibilityGeneration;
    final wasFittingCamera = _fitCameraToIndoor;
    final campus = _loadedCampus;
    final instanceToken = _mapInstanceToken;
    final controller = _controller;
    final cameraBeforeExit =
        preserveCamera && wasFittingCamera && controller != null && _styleReady
            ? await controller.getCameraState()
            : null;
    if (_styleReady && _isCurrentInstance(instanceToken)) {
      await _setIndoorLayerOpacity(0, instanceToken: instanceToken);
      await Future<void>.delayed(
        const Duration(milliseconds: _indoorOpacityTransitionMilliseconds + 40),
      );
      if (visibilityGeneration != _indoorVisibilityGeneration ||
          !_isCurrentInstance(instanceToken)) {
        return false;
      }
      await _removeIndoorLayers(instanceToken: instanceToken);
    }
    _indoorBuilding = null;
    _indoorFloor = null;
    _selectedIndoorSpaceId = null;
    _fitCameraToIndoor = false;
    if (!wasFittingCamera) {
      if (_indoorCameraBoundsConfigured) {
        await _configureOutdoorCameraBounds(instanceToken: instanceToken);
      }
      _outdoorCameraBeforeIndoor = null;
      _restoreDefaultOutdoorCamera = false;
      return true;
    }
    if (campus == null || _controller == null || !_styleReady) {
      _restoreDefaultOutdoorCamera = true;
      _outdoorCameraBeforeIndoor = null;
      return true;
    }
    await _configureOutdoorCameraBounds(instanceToken: instanceToken);
    if (cameraBeforeExit != null) {
      final minZoom = (campus.minZoom ?? 15).toDouble();
      final maxZoom = (campus.maxZoom ?? 19).toDouble();
      _outdoorCameraBeforeIndoor = null;
      _restoreDefaultOutdoorCamera = false;
      await _setCamera(
        CameraOptions(
          center: cameraBeforeExit.center,
          zoom: cameraBeforeExit.zoom.clamp(minZoom, maxZoom).toDouble(),
          bearing: cameraBeforeExit.bearing,
          pitch: cameraBeforeExit.pitch,
          padding: cameraBeforeExit.padding,
        ),
        animate: false,
      );
      return true;
    }
    final camera = _outdoorCameraBeforeIndoor;
    _outdoorCameraBeforeIndoor = null;
    _restoreDefaultOutdoorCamera = false;
    if (camera == null) {
      await resetToDefaultView();
    } else {
      await _setCamera(camera, animate: true);
    }
    return true;
  }

  /// Reports the settled map center and zoom to the SDK-independent page.
  Future<void> handleMapIdle({String? instanceToken}) async {
    if (!_isCurrentInstance(instanceToken)) return;
    final controller = _controller;
    if (controller == null) return;
    final state = await controller.getCameraState();
    if (!_isCurrentInstance(instanceToken)) return;
    final viewportSize = _viewportSize;
    if (viewportSize != null &&
        viewportSize.width > 0 &&
        viewportSize.height > 0) {
      try {
        final points = await controller
            .coordinatesForPixels(<ScreenCoordinate?>[
              ScreenCoordinate(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2,
              ),
              ScreenCoordinate(x: 0, y: 0),
              ScreenCoordinate(x: viewportSize.width, y: 0),
              ScreenCoordinate(x: viewportSize.width, y: viewportSize.height),
              ScreenCoordinate(x: 0, y: viewportSize.height),
            ]);
        if (!_isCurrentInstance(instanceToken)) return;
        if (points.length == 5 && points.every((point) => point != null)) {
          final centerPoint = points.first!;
          final center = CampusCoordinate(
            longitude: centerPoint.coordinates.lng.toDouble(),
            latitude: centerPoint.coordinates.lat.toDouble(),
          );
          final corners = points.skip(1).map((point) {
            final coordinate = point!.coordinates;
            return CampusCoordinate(
              longitude: coordinate.lng.toDouble(),
              latitude: coordinate.lat.toDouble(),
            );
          });
          final cornerList = corners.toList(growable: false);
          onCameraIdle?.call(
            center,
            state.zoom,
            CampusBounds(
              west: cornerList
                  .map((coordinate) => coordinate.longitude)
                  .reduce((a, b) => a < b ? a : b),
              south: cornerList
                  .map((coordinate) => coordinate.latitude)
                  .reduce((a, b) => a < b ? a : b),
              east: cornerList
                  .map((coordinate) => coordinate.longitude)
                  .reduce((a, b) => a > b ? a : b),
              north: cornerList
                  .map((coordinate) => coordinate.latitude)
                  .reduce((a, b) => a > b ? a : b),
            ),
          );
          return;
        }
      } catch (_) {
        // Fall back to the camera center if screen projection is unavailable.
      }
    }
    onCameraIdle?.call(
      CampusCoordinate(
        longitude: state.center.coordinates.lng.toDouble(),
        latitude: state.center.coordinates.lat.toDouble(),
      ),
      state.zoom,
      null,
    );
  }

  /// Resolves a Mapbox tap against MyCHU's semantic place model.
  ///
  /// This deliberately does not depend on Mapbox feature IDs. It preserves
  /// stable plugin-to-place mappings even when the hosted basemap changes.
  Future<void> handleTap(
    MapContentGestureContext context, {
    String? instanceToken,
  }) async {
    if (!_isCurrentInstance(instanceToken)) return;
    final campusId = _loadedCampus?.campusId;
    final places = _places;
    if (campusId == null || places == null) return;

    if (_indoorBuilding != null && _indoorFloor != null) {
      final controller = _controller;
      if (controller == null || !_styleReady) return;
      final features = await controller.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(context.touchPosition),
        RenderedQueryOptions(layerIds: <String?>[_indoorRoomLayer]),
      );
      if (!_isCurrentInstance(instanceToken)) return;
      for (final rendered in features) {
        final feature = rendered?.queriedFeature.feature;
        final rawProperties = feature?["properties"];
        if (rawProperties is! Map) continue;
        final indoorSpaceId = rawProperties["indoor_space_id"];
        if (indoorSpaceId is String &&
            indoorSpaceId.isNotEmpty &&
            _indoorBuilding?.floorForSpace(indoorSpaceId) == _indoorFloor) {
          onIndoorSpaceTap?.call(indoorSpaceId);
          return;
        }
      }
    }

    final position = context.point.coordinates;
    final coordinate = CampusCoordinate(
      longitude: position.lng.toDouble(),
      latitude: position.lat.toDouble(),
    );
    final placeId = _hitTester.hitTestPlaceId(
      campusId: campusId,
      data: places,
      point: coordinate,
    );
    if (placeId == null) return;
    onPlaceTap?.call(placeId, coordinate);
  }

  /// SDK-free semantic tap entry point used by tests and the Mapbox callback.
  CampusPlaceId? semanticPlaceIdAt(CampusCoordinate coordinate) {
    final campusId = _loadedCampus?.campusId;
    final places = _places;
    if (campusId == null || places == null) return null;
    return _hitTester.hitTestPlaceId(
      campusId: campusId,
      data: places,
      point: coordinate,
    );
  }

  @override
  Future<void> dispose() async {
    _loadGeneration++;
    // MapWidget owns the native controller lifetime. The SDK exposes
    // removeInteraction as void while dropping its platform Future, so
    // calling it during teardown can surface an uncatchable error after a
    // hot restart.
    _controller = null;
    _mapInstanceToken = null;
    _loadedCampus = null;
    _places = null;
    _prepared = false;
    _styleReady = false;
    _overlayReady = false;
    _indoorLayersReady = false;
    _styleFallbackAttempted = false;
    _selectionCoordinate = null;
    _userLocationCoordinate = null;
    _pendingFocus = null;
    _indoorBuilding = null;
    _indoorFloor = null;
    _selectedIndoorSpaceId = null;
    _outdoorCameraBeforeIndoor = null;
    _restoreDefaultOutdoorCamera = false;
  }

  Future<void> _configureCameraBounds(
    MapboxMap controller, {
    String? instanceToken,
  }) async {
    if (!_isCurrentInstance(instanceToken)) return;
    final campus = _loadedCampus;
    if (campus == null) return;
    await _setCameraBounds(
      controller,
      bounds: campus.bounds,
      minZoom: campus.minZoom ?? 15,
      maxZoom: campus.maxZoom ?? 19,
      instanceToken: instanceToken,
    );
    _indoorCameraBoundsConfigured = false;
  }

  Future<void> _configureOutdoorCameraBounds({String? instanceToken}) async {
    final controller = _controller;
    final campus = _loadedCampus;
    if (controller == null || campus == null) return;
    await _setCameraBounds(
      controller,
      bounds: campus.bounds,
      minZoom: campus.minZoom ?? 15,
      maxZoom: campus.maxZoom ?? 19,
      instanceToken: instanceToken,
    );
    _indoorCameraBoundsConfigured = false;
  }

  Future<void> _configureIndoorCamera(
    IndoorMapContext context, {
    CampusBounds? selectedSpaceBounds,
    required bool animate,
    String? instanceToken,
  }) async {
    final controller = _controller;
    if (controller == null || !_isCurrentInstance(instanceToken)) return;
    await _setCameraBounds(
      controller,
      bounds: null,
      minZoom: (_loadedCampus?.minZoom ?? 15).toDouble(),
      maxZoom: context.maxZoom.toDouble(),
      instanceToken: instanceToken,
    );
    _indoorCameraBoundsConfigured = true;
    if (!_isCurrentInstance(instanceToken)) return;
    final targetBounds = selectedSpaceBounds ?? context.bounds;
    final camera = await controller.cameraForCoordinateBounds(
      _coordinateBounds(targetBounds),
      selectedSpaceBounds == null
          ? MbxEdgeInsets(top: 56, left: 36, bottom: 180, right: 36)
          : MbxEdgeInsets(top: 48, left: 120, bottom: 240, right: 48),
      null,
      null,
      null,
      null,
    );
    camera.pitch = 0;
    if (camera.zoom != null) {
      camera.zoom = camera.zoom!.clamp(
        context.minZoom.toDouble(),
        context.maxZoom.toDouble(),
      );
    }
    await _setCamera(camera, animate: animate);
  }

  Future<void> _setCameraBounds(
    MapboxMap controller, {
    required CampusBounds? bounds,
    required double minZoom,
    required double maxZoom,
    String? instanceToken,
  }) async {
    if (!_isCurrentInstance(instanceToken)) return;
    await controller.setBounds(
      CameraBoundsOptions(
        bounds: bounds == null ? null : _coordinateBounds(bounds),
        minZoom: minZoom,
        maxZoom: maxZoom,
        minPitch: 0,
        maxPitch: 0,
      ),
    );
    if (!_isCurrentInstance(instanceToken)) return;
    await controller.gestures.updateSettings(
      GesturesSettings(rotateEnabled: false, pitchEnabled: false),
    );
  }

  Future<void> _saveOutdoorCamera() async {
    final controller = _controller;
    if (controller == null) return;
    final state = await controller.getCameraState();
    _outdoorCameraBeforeIndoor = CameraOptions(
      center: state.center,
      zoom: state.zoom,
      bearing: state.bearing,
      pitch: state.pitch,
      padding: state.padding,
    );
  }

  Future<void> _ensureIndoorLayers({String? instanceToken}) async {
    if (!_isCurrentInstance(instanceToken) || !_styleReady) return;
    final building = _indoorBuilding;
    final floor = _indoorFloor;
    final controller = _controller;
    if (building == null || floor == null || controller == null) return;
    final style = controller.style;

    if (!await style.styleSourceExists(_indoorSource)) {
      if (!_isCurrentInstance(instanceToken)) return;
      await style.addSource(
        GeoJsonSource(
          id: _indoorSource,
          data: jsonEncode(building.runtimeGeoJson),
        ),
      );
    }
    if (!_isCurrentInstance(instanceToken)) return;

    String? firstBasemapLabelLayerId;
    try {
      final layers = await style.getStyleLayers();
      if (!_isCurrentInstance(instanceToken)) return;
      for (final layer in layers) {
        if (layer != null &&
            layer.type == "symbol" &&
            !layer.id.startsWith("mychu-indoor-")) {
          firstBasemapLabelLayerId = layer.id;
          break;
        }
      }
    } catch (_) {
      // Imported styles may hide their internal labels. Their slot placement
      // remains the fallback for those styles.
    }

    Future<void> addIfMissing(String id, Layer layer) async {
      if (await style.styleLayerExists(id)) return;
      if (!_isCurrentInstance(instanceToken)) return;
      final labelLayerId = firstBasemapLabelLayerId;
      if (labelLayerId == null) {
        await style.addLayer(layer);
      } else {
        await style.addLayerAt(layer, LayerPosition(below: labelLayerId));
      }
    }

    await addIfMissing(
      _indoorFloorShellLayer,
      FillLayer(
        id: _indoorFloorShellLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "floor_shell"),
        fillColor: 0xFFE7E9ED,
        fillOpacity: 0,
        fillOutlineColor: 0xFF7D8792,
      ),
    );
    await addIfMissing(
      _indoorVoidLayer,
      FillLayer(
        id: _indoorVoidLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "void"),
        fillColor: 0xFFFFFFFF,
        fillOpacity: 0,
        fillOutlineColor: 0xFFD4D8DE,
      ),
    );
    await addIfMissing(
      _indoorCorridorLayer,
      FillLayer(
        id: _indoorCorridorLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "corridor"),
        fillColor: 0xFFF4F0E6,
        fillOpacity: 0,
        fillOutlineColor: 0xFFDDD6C8,
      ),
    );
    await addIfMissing(
      _indoorRoomLayer,
      FillLayer(
        id: _indoorRoomLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "room"),
        fillColor: 0xFFD9EAF7,
        fillOpacity: 0,
        fillOutlineColor: 0xFF7895AC,
      ),
    );
    await addIfMissing(
      _indoorFacilityLayer,
      FillLayer(
        id: _indoorFacilityLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "facility"),
        fillColorExpression: <Object>[
          "match",
          <Object>["get", "space_type"],
          "restroom_male",
          "#DDEAF5",
          "restroom_female",
          "#F4E2EA",
          "restroom_accessible",
          "#E4EFE5",
          "restroom",
          "#E9EBED",
          "stair",
          "#E5E3DC",
          "#FFFFFF",
        ],
        fillOpacity: 0,
        fillOutlineColorExpression: <Object>[
          "match",
          <Object>["get", "space_type"],
          "restroom_male",
          "#718CA2",
          "restroom_female",
          "#A8758C",
          "restroom_accessible",
          "#718A73",
          "restroom",
          "#7A858C",
          "stair",
          "#77786F",
          "#FFFFFF",
        ],
      ),
    );
    await addIfMissing(
      _indoorFacilityDetailLayer,
      LineLayer(
        id: _indoorFacilityDetailLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "facility_detail"),
        lineColor: 0xFF686B65,
        lineWidth: 1.25,
        lineOpacity: 0,
      ),
    );
    await addIfMissing(
      _indoorWallLayer,
      LineLayer(
        id: _indoorWallLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "wall"),
        lineColor: 0xFF626C76,
        lineWidth: 1.5,
        lineOpacity: 0,
      ),
    );
    await addIfMissing(
      _indoorRoomLabelLayer,
      SymbolLayer(
        id: _indoorRoomLabelLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "room"),
        textFieldExpression: <Object>[
          "coalesce",
          <Object>["get", "room_code"],
          <Object>["get", "name"],
        ],
        textSize: 10,
        textColor: 0xFF263442,
        textOpacity: 0,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 1.2,
        textAllowOverlap: false,
      ),
    );
    await addIfMissing(
      _indoorFacilityLabelLayer,
      SymbolLayer(
        id: _indoorFacilityLabelLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorFilter(floor, "facility"),
        textFieldExpression: <Object>[
          "coalesce",
          <Object>["get", "facility_label"],
          "",
        ],
        textSize: 9,
        textColor: 0xFF344451,
        textOpacity: 0,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 1.1,
        textAllowOverlap: false,
      ),
    );
    await addIfMissing(
      _indoorSelectionLayer,
      FillLayer(
        id: _indoorSelectionLayer,
        sourceId: _indoorSource,
        slot: "middle",
        minZoom: _indoorLayerMinZoom,
        filter: _indoorSelectionFilter(floor, _selectedIndoorSpaceId),
        fillColor: 0xFFFFC857,
        fillOpacity: 0,
        fillOutlineColor: 0xFF145DA0,
      ),
    );

    if (!_isCurrentInstance(instanceToken)) return;
    _indoorLayersReady = true;
    await _applyIndoorFilters(instanceToken: instanceToken);
    await _configureIndoorOpacityTransitions(instanceToken: instanceToken);
    await _setIndoorLayerOpacity(1, instanceToken: instanceToken);
  }

  Future<void> _configureIndoorOpacityTransitions({
    String? instanceToken,
  }) async {
    final controller = _controller;
    if (controller == null || !_isCurrentInstance(instanceToken)) return;
    const properties = <String, String>{
      _indoorFloorShellLayer: "fill-opacity",
      _indoorVoidLayer: "fill-opacity",
      _indoorCorridorLayer: "fill-opacity",
      _indoorRoomLayer: "fill-opacity",
      _indoorFacilityLayer: "fill-opacity",
      _indoorFacilityDetailLayer: "line-opacity",
      _indoorWallLayer: "line-opacity",
      _indoorRoomLabelLayer: "text-opacity",
      _indoorFacilityLabelLayer: "text-opacity",
      _indoorSelectionLayer: "fill-opacity",
    };
    final style = controller.style;
    for (final entry in properties.entries) {
      if (!await style.styleLayerExists(entry.key)) continue;
      if (!_isCurrentInstance(instanceToken)) return;
      await style.setStyleLayerProperty(
        entry.key,
        "${entry.value}-transition",
        <String, int>{
          "duration": _indoorOpacityTransitionMilliseconds,
          "delay": 0,
        },
      );
    }
  }

  Future<void> _setIndoorLayerOpacity(
    double visibility, {
    String? instanceToken,
  }) async {
    final controller = _controller;
    if (controller == null || !_isCurrentInstance(instanceToken)) return;
    const opacities = <String, MapEntry<String, double>>{
      _indoorFloorShellLayer: MapEntry("fill-opacity", 0.82),
      _indoorVoidLayer: MapEntry("fill-opacity", 0.95),
      _indoorCorridorLayer: MapEntry("fill-opacity", 0.9),
      _indoorRoomLayer: MapEntry("fill-opacity", 0.9),
      _indoorFacilityLayer: MapEntry("fill-opacity", 0.9),
      _indoorFacilityDetailLayer: MapEntry("line-opacity", 0.9),
      _indoorWallLayer: MapEntry("line-opacity", 0.9),
      _indoorRoomLabelLayer: MapEntry("text-opacity", 1),
      _indoorFacilityLabelLayer: MapEntry("text-opacity", 1),
      _indoorSelectionLayer: MapEntry("fill-opacity", 0.55),
    };
    final style = controller.style;
    for (final entry in opacities.entries) {
      if (!await style.styleLayerExists(entry.key)) continue;
      if (!_isCurrentInstance(instanceToken)) return;
      await style.setStyleLayerProperty(
        entry.key,
        entry.value.key,
        entry.value.value * visibility,
      );
    }
  }

  Future<void> _applyIndoorFilters({String? instanceToken}) async {
    if (!_styleReady ||
        !_indoorLayersReady ||
        !_isCurrentInstance(instanceToken)) {
      return;
    }
    final controller = _controller;
    final floor = _indoorFloor;
    if (controller == null || floor == null) return;
    final style = controller.style;
    final filters = <String, List<Object>>{
      _indoorFloorShellLayer: _indoorFilter(floor, "floor_shell"),
      _indoorVoidLayer: _indoorFilter(floor, "void"),
      _indoorCorridorLayer: _indoorFilter(floor, "corridor"),
      _indoorRoomLayer: _indoorFilter(floor, "room"),
      _indoorFacilityLayer: _indoorFilter(floor, "facility"),
      _indoorFacilityDetailLayer: _indoorFilter(floor, "facility_detail"),
      _indoorWallLayer: _indoorFilter(floor, "wall"),
      _indoorRoomLabelLayer: _indoorFilter(floor, "room"),
      _indoorFacilityLabelLayer: _indoorFilter(floor, "facility"),
      _indoorSelectionLayer: _indoorSelectionFilter(
        floor,
        _selectedIndoorSpaceId,
      ),
    };
    for (final entry in filters.entries) {
      if (!await style.styleLayerExists(entry.key)) continue;
      if (!_isCurrentInstance(instanceToken)) return;
      await style.setStyleLayerProperty(entry.key, "filter", entry.value);
    }
  }

  Future<void> _removeIndoorLayers({String? instanceToken}) async {
    final controller = _controller;
    if (controller == null) return;
    final style = controller.style;
    for (final layerId in _indoorLayers.reversed) {
      if (instanceToken != null && !_isCurrentInstance(instanceToken)) return;
      if (await style.styleLayerExists(layerId)) {
        await style.removeStyleLayer(layerId);
      }
    }
    if (instanceToken != null && !_isCurrentInstance(instanceToken)) return;
    if (await style.styleSourceExists(_indoorSource)) {
      await style.removeStyleSource(_indoorSource);
    }
    _indoorLayersReady = false;
  }

  static List<Object> _indoorFilter(int floor, String renderClass) => <Object>[
    "all",
    <Object>[
      "==",
      <Object>["get", "floor"],
      floor,
    ],
    <Object>[
      "==",
      <Object>["get", "render_class"],
      renderClass,
    ],
  ];

  static List<Object> _indoorSelectionFilter(
    int floor,
    String? selectedIndoorSpaceId,
  ) => <Object>[
    "all",
    <Object>[
      "==",
      <Object>["get", "floor"],
      floor,
    ],
    <Object>[
      "==",
      <Object>["get", "render_class"],
      "room",
    ],
    <Object>[
      "==",
      <Object>["get", "indoor_space_id"],
      selectedIndoorSpaceId ?? "",
    ],
  ];

  bool _isCurrentInstance(String? instanceToken) =>
      _prepared &&
      _controller != null &&
      (instanceToken == null || instanceToken == _mapInstanceToken);

  Future<void> _ensureOverlayLayers({String? instanceToken}) async {
    if (!_isCurrentInstance(instanceToken)) return;
    final controller = _controller;
    if (controller == null || _overlayReady) return;
    final style = controller.style;

    if (!await style.styleSourceExists(_selectionSource)) {
      if (!_isCurrentInstance(instanceToken)) return;
      await style.addSource(
        GeoJsonSource(id: _selectionSource, data: jsonEncode(_emptyGeoJson())),
      );
    }
    if (!_isCurrentInstance(instanceToken)) return;
    if (!await style.styleSourceExists(_userLocationSource)) {
      if (!_isCurrentInstance(instanceToken)) return;
      await style.addSource(
        GeoJsonSource(
          id: _userLocationSource,
          data: jsonEncode(_emptyGeoJson()),
        ),
      );
    }
    if (!_isCurrentInstance(instanceToken)) return;
    if (!await style.styleLayerExists(_selectionLayer)) {
      if (!_isCurrentInstance(instanceToken)) return;
      await style.addLayer(
        CircleLayer(
          id: _selectionLayer,
          sourceId: _selectionSource,
          slot: "top",
          circleRadius: 7,
          circleColor: 0xFF1A73E8,
          circleStrokeWidth: 2,
          circleStrokeColor: 0xFFFFFFFF,
        ),
      );
    }
    if (!_isCurrentInstance(instanceToken)) return;
    if (!await style.styleLayerExists(_userLocationLayer)) {
      if (!_isCurrentInstance(instanceToken)) return;
      await style.addLayer(
        CircleLayer(
          id: _userLocationLayer,
          sourceId: _userLocationSource,
          slot: "top",
          circleRadius: 8,
          circleColor: 0xFF0D47A1,
          circleStrokeWidth: 2,
          circleStrokeColor: 0xFFFFFFFF,
        ),
      );
    }
    if (!_isCurrentInstance(instanceToken)) return;
    _overlayReady = true;
  }

  Future<void> _applySelection() async {
    if (!_styleReady || !_overlayReady) return;
    await _setPointSource(_selectionSource, _selectionCoordinate);
  }

  Future<void> _applyUserLocation() async {
    if (!_styleReady || !_overlayReady) return;
    await _setPointSource(_userLocationSource, _userLocationCoordinate);
  }

  Future<void> _setPointSource(
    String sourceId,
    CampusCoordinate? coordinate,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    final data =
        coordinate == null ? _emptyGeoJson() : _pointGeoJson(coordinate);
    await controller.style.setStyleSourceProperty(
      sourceId,
      "data",
      jsonEncode(data),
    );
  }

  Future<void> _setCamera(
    CameraOptions options, {
    required bool animate,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    if (animate) {
      await controller.easeTo(
        options,
        MapAnimationOptions(duration: 250, startDelay: 0),
      );
    } else {
      await controller.setCamera(options);
    }
  }

  Future<void> _focusCoordinate(
    CampusCoordinate coordinate, {
    required bool animate,
  }) async {
    if (_controller == null) return;
    await _setCamera(
      CameraOptions(
        center: _point(coordinate),
        zoom: 18,
        padding: MbxEdgeInsets(top: 80, left: 40, bottom: 220, right: 40),
      ),
      animate: animate,
    );
  }

  CampusCoordinate? _placeCenter(CampusPlaceId placeId) {
    final place = _places?.placeById(placeId.placeId);
    if (place == null) return null;
    return place.displayCoordinate ??
        (place.geometry.isNotEmpty ? place.geometry.first : null);
  }

  Point _point(CampusCoordinate coordinate) =>
      Point(coordinates: Position(coordinate.longitude, coordinate.latitude));

  CoordinateBounds _coordinateBounds(CampusBounds bounds) => CoordinateBounds(
    southwest: Point(coordinates: Position(bounds.west, bounds.south)),
    northeast: Point(coordinates: Position(bounds.east, bounds.north)),
    infiniteBounds: false,
  );

  Map<String, dynamic> _emptyGeoJson() => {
    "type": "FeatureCollection",
    "features": <Object>[],
  };

  Map<String, dynamic> _pointGeoJson(CampusCoordinate coordinate) => {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [coordinate.longitude, coordinate.latitude],
        },
        "properties": <String, dynamic>{},
      },
    ],
  };
}
