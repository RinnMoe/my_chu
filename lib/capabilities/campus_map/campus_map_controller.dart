import "dart:math" as math;

import "package:flutter/foundation.dart";

import "../campus_places/campus_places.dart";
import "../external_navigation/external_navigation.dart";
import "../../services/user_error_message.dart";
import "campus_map_models.dart";
import "map_engine.dart";
import "indoor_map.dart";

/// 地图页面状态。
enum CampusMapStatus { idle, loading, ready, error }

/// 地图视图状态（控制器对外发布，SDK 无关）。
class CampusMapViewState {
  final CampusMapStatus status;
  final String? campusId;
  final ResolvedPlaceSelection? selected;
  final IndoorViewState? indoorView;
  final String? errorMessage;

  const CampusMapViewState({
    this.status = CampusMapStatus.idle,
    this.campusId,
    this.selected,
    this.indoorView,
    this.errorMessage,
  });

  CampusMapViewState copyWith({
    CampusMapStatus? status,
    String? campusId,
    ResolvedPlaceSelection? selected,
    bool clearSelected = false,
    IndoorViewState? indoorView,
    bool clearIndoorView = false,
    String? errorMessage,
  }) => CampusMapViewState(
    status: status ?? this.status,
    campusId: campusId ?? this.campusId,
    selected: clearSelected ? null : (selected ?? this.selected),
    indoorView: clearIndoorView ? null : (indoorView ?? this.indoorView),
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

/// 校区/地点协调控制器：统一跳转、跨校区切换、目标不丢失、并发覆盖。
///
/// 依赖 `CampusPlacesService`（解析/搜索）与 `CampusMapEngine`（渲染抽象）；
/// 二者均可注入，便于单元测试。
class CampusMapController extends ChangeNotifier {
  static const double _indoorAutoExitZoom = 17.5;
  static const double _indoorAutoEnterZoom = 18;

  final CampusPlacesService placesService;
  final CampusMapEngine engine;
  final CampusIndoorMapRepository indoorMapRepository;
  final NavigationTargetResolver navigationResolver;

  int _generation = 0;
  int _indoorGeneration = 0;
  int _selectionGeneration = 0;
  bool _disposed = false;
  bool _autoIndoorEntryPending = false;
  bool _indoorExitPending = false;
  bool _indoorExitCancelable = false;
  int _indoorExitGeneration = 0;
  String? _suppressedAutoIndoorBuildingId;
  String? _manualIndoorBuildingId;
  CampusCoordinate? _manualIndoorSelectionCenter;
  double? _manualIndoorSelectionZoom;
  int _indoorActivationDepth = 0;
  CampusCoordinate? _lastCameraCenter;
  CampusBounds? _lastViewportBounds;
  double? _lastCameraZoom;
  UnifiedPlaceRequest? _pendingRequest;
  CampusMapViewState _state = const CampusMapViewState();

  CampusMapViewState get state => _state;

  CampusMapController({
    required this.placesService,
    required this.engine,
    CampusIndoorMapRepository? indoorMapRepository,
    NavigationTargetResolver? navigationResolver,
  }) : indoorMapRepository = indoorMapRepository ?? CampusIndoorMapRepository(),
       navigationResolver =
           navigationResolver ?? const NavigationTargetResolver();

  /// 初始化：加载地点服务与首选校区；完成后重放 pending 目标（目标不丢失）。
  Future<void> initialize({String? preferredCampusId}) async {
    if (_disposed) return;
    final initializationGeneration = ++_generation;
    await placesService.load();
    if (!_isCurrent(initializationGeneration)) return;
    var campusId = preferredCampusId;
    final preferredCampus =
        campusId == null ? null : placesService.campusById(campusId);
    if (preferredCampus == null || !preferredCampus.enabled) {
      campusId =
          placesService.campuses.isEmpty
              ? null
              : placesService.campuses.first.campusId;
    }
    if (campusId == null) {
      _setError("没有可用的校区");
      return;
    }
    await switchCampus(campusId);
    final pending = _pendingRequest;
    if (pending != null) {
      _pendingRequest = null;
      await openRequest(pending);
    }
  }

  /// 切换校区（任务书八.5 流程）。
  Future<void> switchCampus(String campusId) async {
    if (_disposed) return;
    if (campusId == _state.campusId && _state.status == CampusMapStatus.ready) {
      return;
    }
    final generation = ++_generation;
    _indoorGeneration++;
    _lastCameraZoom = null;
    _lastCameraCenter = null;
    _lastViewportBounds = null;
    _suppressedAutoIndoorBuildingId = null;
    _manualIndoorBuildingId = null;
    final campus = placesService.campusById(campusId);
    if (campus == null) {
      _setError("该校区暂不可用，请稍后重试");
      return;
    }
    _state = CampusMapViewState(
      status: CampusMapStatus.loading,
      campusId: campusId,
    );
    notifyListeners();
    try {
      await engine.loadCampus(campus);
      if (generation != _generation) return; // 已被更新的切换取代
      final places = placesService.placesFor(campusId);
      if (places != null) {
        await engine.setPlaces(places);
        if (generation != _generation) return;
      }
      _state = CampusMapViewState(
        status: CampusMapStatus.ready,
        campusId: campusId,
      );
      notifyListeners();
      if (_pendingRequest == null && campus.defaultPlaceId != null) {
        if (generation != _generation || _disposed) return;
        await engine.focusPlace(
          CampusPlaceId(campusId: campusId, placeId: campus.defaultPlaceId!),
        );
      }
    } catch (error) {
      if (generation != _generation) return;
      logUserFacingError(UserErrorContext.map, error, operation: 'load');
      _setError(
        error is CampusMapConfigurationException
            ? error.message
            : userFacingError(UserErrorContext.map, error),
        campusId: campusId,
      );
    }
  }

  /// 统一地点跳转入口。
  Future<PlaceResolutionResult> openRequest(
    UnifiedPlaceRequest request, {
    CampusCoordinate? selectionMarkerCoordinate,
  }) async {
    if (_disposed) {
      return PlaceResolutionResult.unresolved(message: "地图控制器已释放");
    }
    final selectionGeneration = ++_selectionGeneration;
    // Keep a request issued while the first semantic snapshot is loading.
    // Startup may advance the controller generation before the resolver
    // finishes, but initialization will replay this pending request.
    if (_state.status == CampusMapStatus.idle && !placesService.isLoaded) {
      _pendingRequest = request;
    }
    final generation = _generation;
    final result = await placesService.resolve(
      request,
      currentCampusId: _state.campusId,
    );
    if (!_isCurrentSelection(generation, selectionGeneration)) return result;
    if (result.status == PlaceResolutionStatus.resolved) {
      await _selectResolved(
        result,
        request,
        generation: generation,
        selectionGeneration: selectionGeneration,
        selectionMarkerCoordinate: selectionMarkerCoordinate,
      );
    }
    return result;
  }

  /// Handles a map tap, using indoor mode only when supported and available.
  /// Returns null when indoor mode successfully consumed the tap.
  Future<PlaceResolutionResult?> handlePlaceTap(
    CampusPlaceId placeId,
    CampusCoordinate clickCoordinate,
  ) async {
    final place = placesService
        .placesFor(placeId.campusId)
        ?.placeById(placeId.placeId);
    if (place != null &&
        isBuildingFootprint(place) &&
        indoorMapRepository.supportsBuildingPlaceId(place.placeId)) {
      final activated = await enterIndoorForPlace(
        place.placeId,
        fitCamera: false,
        userInitiated: true,
      );
      if (activated) {
        await clearSelection();
        return null;
      }
    }

    return openRequest(
      UnifiedPlaceRequest(campusId: placeId.campusId, placeId: placeId.placeId),
      selectionMarkerCoordinate: clickCoordinate,
    );
  }

  /// 歧义候选选择后调用。
  Future<void> selectCandidate(PlaceCandidate candidate) async {
    if (_disposed) return;
    final selectionGeneration = ++_selectionGeneration;
    final generation = _generation;
    final request = UnifiedPlaceRequest(
      campusId: candidate.campusId,
      placeId: candidate.placeId,
      rawText: candidate.label,
    );
    final result = await placesService.resolve(
      request,
      currentCampusId: _state.campusId,
    );
    if (!_isCurrentSelection(generation, selectionGeneration)) return;
    if (result.status == PlaceResolutionStatus.resolved) {
      await _selectResolved(
        result,
        request,
        generation: generation,
        selectionGeneration: selectionGeneration,
      );
    }
  }

  Future<void> clearSelection() async {
    if (_disposed) return;
    final selectionGeneration = ++_selectionGeneration;
    final indoor = _state.indoorView;
    if (indoor != null) {
      final indoorGeneration = ++_indoorGeneration;
      await engine.selectIndoorSpace(null);
      if (!_isCurrentSelection(_generation, selectionGeneration) ||
          indoorGeneration != _indoorGeneration) {
        return;
      }
      _state = _state.copyWith(
        clearSelected: true,
        indoorView: indoor.copyWith(clearSelectedIndoorSpace: true),
      );
    } else {
      _state = _state.copyWith(clearSelected: true);
    }
    notifyListeners();
    if (_state.status == CampusMapStatus.ready && indoor == null) {
      await engine.clearSelection();
    }
  }

  /// Enters indoor mode for a supported building.
  Future<bool> enterIndoorForPlace(
    String buildingPlaceId, {
    int? floor,
    bool fitCamera = false,
    bool userInitiated = false,
  }) async {
    if (_disposed || _state.status != CampusMapStatus.ready) return false;
    if (!indoorMapRepository.supportsBuildingPlaceId(buildingPlaceId)) {
      return false;
    }
    if (userInitiated) {
      _manualIndoorBuildingId = buildingPlaceId;
      _manualIndoorSelectionCenter = _lastCameraCenter;
      _manualIndoorSelectionZoom = _lastCameraZoom;
    }
    final activeIndoor = _state.indoorView;
    if (activeIndoor?.context.buildingPlaceId == buildingPlaceId) {
      _suppressedAutoIndoorBuildingId = null;
      if (floor != null && floor != activeIndoor!.activeFloor) {
        await setIndoorFloor(floor);
      }
      return true;
    }
    if (!fitCamera && (_lastCameraZoom ?? 0) < _indoorAutoEnterZoom) {
      return false;
    }
    final selectionGeneration = ++_selectionGeneration;
    final generation = _generation;
    try {
      final building = await indoorMapRepository.loadForBuildingPlaceId(
        buildingPlaceId,
      );
      if (!_isCurrentSelection(generation, selectionGeneration) ||
          building == null) {
        return false;
      }
      if (building.context.campusId != _state.campusId) return false;
      _suppressedAutoIndoorBuildingId = null;
      return await _activateIndoor(
        building,
        floor: floor ?? building.context.defaultFloor,
        generation: generation,
        selectionGeneration: selectionGeneration,
        fitCamera: fitCamera,
      );
    } catch (error) {
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "enter_indoor",
      );
      return false;
    }
  }

  /// Selects the nearest visible building once the map reaches indoor zoom.
  Future<void> handleCameraIdle(
    CampusCoordinate center,
    double zoom, {
    CampusBounds? viewportBounds,
  }) async {
    if (_disposed ||
        _state.status != CampusMapStatus.ready ||
        !center.isValidWgs84 ||
        !zoom.isFinite) {
      return;
    }
    _lastCameraZoom = zoom;
    _lastCameraCenter = center;
    _lastViewportBounds = viewportBounds;

    if (_indoorExitPending &&
        _indoorExitCancelable &&
        zoom > _indoorAutoExitZoom) {
      final exitingIndoor = _state.indoorView;
      if (exitingIndoor != null) {
        await _restoreIndoorAfterZoomReversal(exitingIndoor);
      }
    }

    final indoor = _state.indoorView;
    if (zoom <= _indoorAutoExitZoom) {
      _suppressedAutoIndoorBuildingId = null;
      _manualIndoorBuildingId = null;
      _manualIndoorSelectionCenter = null;
      _manualIndoorSelectionZoom = null;
      if (indoor != null) {
        await _exitIndoor(preserveCamera: true, cancelOnZoomIn: true);
      }
      return;
    }
    if (zoom < _indoorAutoEnterZoom) return;

    final manualBuildingId = _manualIndoorBuildingId;
    if (manualBuildingId != null) {
      final sameCamera =
          _manualIndoorSelectionCenter == null ||
          _manualIndoorSelectionZoom == null ||
          _sameCamera(
            _manualIndoorSelectionCenter,
            _manualIndoorSelectionZoom,
            center,
            zoom,
          );
      if (sameCamera &&
          (_indoorActivationDepth > 0 ||
              indoor?.context.buildingPlaceId == manualBuildingId)) {
        return;
      }
      _manualIndoorBuildingId = null;
      _manualIndoorSelectionCenter = null;
      _manualIndoorSelectionZoom = null;
    }
    if (_indoorActivationDepth > 0) return;

    final campusId = _state.campusId;
    if (campusId == null) return;
    final places = placesService.placesFor(campusId);
    if (places == null) return;
    final nearestBuilding = _nearestBuildingAtScreenCenter(
      places,
      center,
      viewportBounds,
      preferredBuildingPlaceId: indoor?.context.buildingPlaceId,
    );

    final suppressedBuildingId = _suppressedAutoIndoorBuildingId;
    if (suppressedBuildingId != null) {
      if (nearestBuilding?.placeId == suppressedBuildingId) return;
      _suppressedAutoIndoorBuildingId = null;
    }

    if (indoor?.context.buildingPlaceId == nearestBuilding?.placeId) return;
    if (nearestBuilding == null ||
        !indoorMapRepository.supportsBuildingPlaceId(nearestBuilding.placeId)) {
      if (indoor != null) {
        await _exitIndoor(preserveCamera: true, cancelOnZoomIn: true);
      }
      return;
    }
    if (_autoIndoorEntryPending) {
      return;
    }

    _autoIndoorEntryPending = true;
    try {
      await enterIndoorForPlace(nearestBuilding.placeId, fitCamera: false);
    } finally {
      _autoIndoorEntryPending = false;
    }
    if (!_disposed &&
        _lastCameraCenter != null &&
        _lastCameraZoom != null &&
        !_sameCamera(center, zoom, _lastCameraCenter!, _lastCameraZoom!)) {
      await handleCameraIdle(
        _lastCameraCenter!,
        _lastCameraZoom!,
        viewportBounds: _lastViewportBounds,
      );
    }
  }

  Future<void> setIndoorFloor(int floor) async {
    final indoor = _state.indoorView;
    if (_disposed || indoor == null || !indoor.context.floors.contains(floor)) {
      return;
    }
    final generation = _generation;
    final selectionGeneration = ++_selectionGeneration;
    final indoorGeneration = ++_indoorGeneration;
    await engine.setIndoorFloor(floor);
    if (!_isCurrentSelection(generation, selectionGeneration) ||
        indoorGeneration != _indoorGeneration) {
      return;
    }
    _state = _state.copyWith(indoorView: indoor.copyWith(activeFloor: floor));
    notifyListeners();
  }

  Future<void> exitIndoor() async {
    _suppressedAutoIndoorBuildingId =
        _state.indoorView?.context.buildingPlaceId;
    _manualIndoorBuildingId = null;
    _manualIndoorSelectionCenter = null;
    _manualIndoorSelectionZoom = null;
    await _exitIndoor(preserveCamera: true);
  }

  Future<void> _exitIndoor({
    required bool preserveCamera,
    bool cancelOnZoomIn = false,
  }) async {
    if (_disposed || _indoorExitPending || _state.indoorView == null) return;
    _indoorExitPending = true;
    _indoorExitCancelable = cancelOnZoomIn;
    final exitGeneration = ++_indoorExitGeneration;
    try {
      final generation = _generation;
      final selectionGeneration = ++_selectionGeneration;
      final indoorGeneration = ++_indoorGeneration;
      final exited = await engine.exitIndoor(preserveCamera: preserveCamera);
      if (!exited || exitGeneration != _indoorExitGeneration) return;
      if (!_isCurrentSelection(generation, selectionGeneration) ||
          indoorGeneration != _indoorGeneration) {
        return;
      }
      _state = _state.copyWith(clearIndoorView: true);
      notifyListeners();
    } finally {
      if (exitGeneration == _indoorExitGeneration) {
        _indoorExitPending = false;
        _indoorExitCancelable = false;
      }
    }
  }

  Future<void> _restoreIndoorAfterZoomReversal(IndoorViewState indoor) async {
    final generation = _generation;
    ++_indoorExitGeneration;
    _indoorExitPending = false;
    _indoorExitCancelable = false;
    try {
      final building = await indoorMapRepository.loadForBuildingPlaceId(
        indoor.context.buildingPlaceId,
      );
      if (!_isCurrent(generation) || building == null) return;
      await engine.enterIndoor(
        building,
        floor: indoor.activeFloor,
        selectedIndoorSpaceId: indoor.selectedIndoorSpaceId,
        fitCamera: false,
      );
      if (!_isCurrent(generation)) return;
    } catch (error) {
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "restore_indoor_after_zoom_reversal",
      );
      if (!_isCurrent(generation)) return;
      _state = _state.copyWith(clearIndoorView: true);
      notifyListeners();
    }
  }

  /// Maps a stable indoor-space id back to its registered semantic classroom.
  Future<void> selectIndoorSpace(String indoorSpaceId) async {
    final indoor = _state.indoorView;
    if (_disposed || indoor == null) return;
    final data = placesService.placesFor(indoor.context.campusId);
    CampusClassroom? classroom;
    if (data != null) {
      for (final candidate in data.classrooms) {
        if (candidate.indoorSpaceId == indoorSpaceId &&
            candidate.floor == indoor.activeFloor) {
          classroom = candidate;
          break;
        }
      }
    }
    if (classroom == null) return;

    final buildingPlaceId = classroom.zonePlaceId ?? classroom.buildingPlaceId;
    final place = data?.placeById(buildingPlaceId);
    final selection = ResolvedPlaceSelection(
      campusId: classroom.campusId,
      place: place,
      classroom: classroom,
      externalNavigationTarget: navigationResolver.resolve(
        place: place,
        classroom: classroom,
        places: data,
      ),
    );

    final generation = _generation;
    final selectionGeneration = ++_selectionGeneration;
    final indoorGeneration = ++_indoorGeneration;
    await engine.selectIndoorSpace(indoorSpaceId);
    if (!_isCurrentSelection(generation, selectionGeneration) ||
        indoorGeneration != _indoorGeneration) {
      return;
    }
    _state = _state.copyWith(
      selected: selection,
      indoorView: indoor.copyWith(selectedIndoorSpaceId: indoorSpaceId),
    );
    notifyListeners();
  }

  Future<void> _selectResolved(
    PlaceResolutionResult result,
    UnifiedPlaceRequest request, {
    required int generation,
    required int selectionGeneration,
    CampusCoordinate? selectionMarkerCoordinate,
  }) async {
    if (!_isCurrentSelection(generation, selectionGeneration)) return;
    final campusId = result.campusId ?? result.placeId?.campusId;
    if (campusId == null) return;
    final selection = ResolvedPlaceSelection(
      campusId: campusId,
      place: result.place,
      classroom: result.classroom,
      externalNavigationTarget: navigationResolver.resolve(
        place: result.place,
        classroom: result.classroom,
        places: placesService.placesFor(campusId),
      ),
      showInfoCard: request.openInfoCard,
      showExternalNavigation: request.showExternalNavigation,
    );

    var activeGeneration = generation;
    final sameCampus = campusId == _state.campusId;
    if (!sameCampus) {
      if (!request.allowCampusSwitch) return;
      await switchCampus(campusId);
      if (!_isCurrentSelection(_generation, selectionGeneration) ||
          _state.campusId != campusId) {
        return;
      }
      activeGeneration = _generation;
      if (_state.status == CampusMapStatus.error) {
        _state = _state.copyWith(selected: selection);
        notifyListeners();
        return;
      }
    }

    if (_state.status != CampusMapStatus.ready) {
      _pendingRequest = request.copyWith(campusId: campusId);
      return;
    }

    final placeId = result.placeId;
    IndoorBuildingData? indoorBuilding;
    final classroom = result.classroom;
    final classroomBuildingPlaceId =
        classroom == null
            ? null
            : classroom.zonePlaceId ?? classroom.buildingPlaceId;
    if (classroomBuildingPlaceId != null &&
        indoorMapRepository.supportsBuildingPlaceId(classroomBuildingPlaceId)) {
      try {
        indoorBuilding = await indoorMapRepository.loadForBuildingPlaceId(
          classroomBuildingPlaceId,
        );
      } catch (error) {
        logUserFacingError(
          UserErrorContext.map,
          error,
          operation: "load_indoor_building",
        );
      }
      if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;
    }

    String? spaceId;
    if (indoorBuilding != null) {
      final declaredSpaceId = classroom?.indoorSpaceId;
      if (declaredSpaceId != null &&
          indoorBuilding.containsSpace(declaredSpaceId)) {
        spaceId = declaredSpaceId;
      } else if (classroom != null) {
        spaceId = indoorBuilding.spaceIdForRoomCode(classroom.classroomId);
      }
    }
    final canEnterIndoor =
        indoorBuilding != null &&
        spaceId != null &&
        indoorBuilding.context.buildingPlaceId == classroomBuildingPlaceId &&
        indoorBuilding.containsSpace(spaceId);
    final sameIndoorBuilding =
        placeId != null &&
        _state.indoorView?.context.buildingPlaceId == placeId.placeId;

    if (canEnterIndoor) {
      final activeFloor =
          indoorBuilding.floorForSpace(spaceId) ??
          classroom?.floor ??
          indoorBuilding.context.defaultFloor;
      final entered = await _activateIndoor(
        indoorBuilding,
        floor: activeFloor,
        selectedIndoorSpaceId: spaceId,
        generation: activeGeneration,
        selectionGeneration: selectionGeneration,
        // A classroom search should center the indoor map so its floor and
        // selected room are immediately visible.
        fitCamera: true,
      );
      if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;
      if (!entered) {
        await _leaveIndoorForDifferentTarget(sameIndoorBuilding);
        if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;
        if (placeId != null) await engine.selectPlace(placeId);
      }
    } else {
      await _leaveIndoorForDifferentTarget(sameIndoorBuilding);
      if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;
      if (placeId != null) await engine.selectPlace(placeId);
    }
    if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;

    // A map tap identifies the containing business place, but the visual
    // marker belongs at the user's exact tap coordinate rather than the
    // place's display/geometry center.
    if (selectionMarkerCoordinate != null) {
      if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;
      await engine.showSelectionMarker(selectionMarkerCoordinate);
    }
    if (!_isCurrentSelection(activeGeneration, selectionGeneration)) return;
    _state = _state.copyWith(selected: selection);
    notifyListeners();
  }

  Future<bool> _activateIndoor(
    IndoorBuildingData building, {
    required int floor,
    String? selectedIndoorSpaceId,
    required int generation,
    required int selectionGeneration,
    bool fitCamera = true,
  }) async {
    if (!_isCurrentSelection(generation, selectionGeneration) ||
        building.context.campusId != _state.campusId) {
      return false;
    }
    if (!building.context.floors.contains(floor)) return false;
    if (selectedIndoorSpaceId != null &&
        building.floorForSpace(selectedIndoorSpaceId) != floor) {
      return false;
    }

    final indoorGeneration = ++_indoorGeneration;
    _indoorActivationDepth++;
    try {
      try {
        await engine.enterIndoor(
          building,
          floor: floor,
          selectedIndoorSpaceId: selectedIndoorSpaceId,
          fitCamera: fitCamera,
        );
      } catch (error) {
        logUserFacingError(
          UserErrorContext.map,
          error,
          operation: "enter_indoor_engine",
        );
        if (!_isCurrentSelection(generation, selectionGeneration) ||
            indoorGeneration != _indoorGeneration) {
          return false;
        }
        try {
          await engine.exitIndoor();
        } catch (cleanupError) {
          logUserFacingError(
            UserErrorContext.map,
            cleanupError,
            operation: "exit_indoor_after_failure",
          );
        }
        return false;
      }
      if (!_isCurrentSelection(generation, selectionGeneration) ||
          indoorGeneration != _indoorGeneration) {
        return false;
      }
      _state = _state.copyWith(
        indoorView: IndoorViewState(
          context: building.context,
          activeFloor: floor,
          selectedIndoorSpaceId: selectedIndoorSpaceId,
        ),
      );
      notifyListeners();
      return true;
    } finally {
      _indoorActivationDepth--;
    }
  }

  Future<void> _leaveIndoorForDifferentTarget(bool sameIndoorBuilding) async {
    if (_state.indoorView == null || sameIndoorBuilding) return;
    final indoorGeneration = ++_indoorGeneration;
    await engine.exitIndoor(preserveCamera: true);
    if (!_disposed && indoorGeneration == _indoorGeneration) {
      _state = _state.copyWith(clearIndoorView: true);
    }
  }

  void _setError(String message, {String? campusId}) {
    _state = CampusMapViewState(
      status: CampusMapStatus.error,
      campusId: campusId ?? _state.campusId,
      errorMessage: message,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    engine.dispose();
    super.dispose();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isCurrentSelection(int generation, int selectionGeneration) =>
      _isCurrent(generation) && selectionGeneration == _selectionGeneration;
}

CampusPlace? _nearestBuildingAtScreenCenter(
  CampusPlacesData places,
  CampusCoordinate center,
  CampusBounds? viewportBounds, {
  String? preferredBuildingPlaceId,
}) {
  CampusPlace? nearest;
  var nearestDistance = double.infinity;
  var nearestArea = double.infinity;
  CampusPlace? preferred;
  var preferredDistance = double.infinity;
  for (final place in places.places) {
    if (!isBuildingFootprint(place) ||
        (viewportBounds == null
            ? !_containsCoordinate(place.geometry, center)
            : !_buildingIntersectsViewport(place, viewportBounds))) {
      continue;
    }
    final distance = _distanceToBuildingMeters(place, center);
    if (place.placeId == preferredBuildingPlaceId) {
      preferred = place;
      preferredDistance = distance;
    }
    final area = _buildingAreaSquareMeters(place);
    if (distance < nearestDistance - 0.01 ||
        ((distance - nearestDistance).abs() <= 0.01 && area < nearestArea)) {
      nearest = place;
      nearestDistance = distance;
      nearestArea = area;
    }
  }
  if (preferred != null &&
      nearest != null &&
      preferred.placeId != nearest.placeId &&
      preferredDistance <= nearestDistance + 8) {
    return preferred;
  }
  return nearest;
}

bool _buildingIntersectsViewport(CampusPlace place, CampusBounds viewport) {
  if (!viewport.isValidWgs84 || place.geometry.isEmpty) return false;
  var west = place.geometry.first.longitude;
  var east = west;
  var south = place.geometry.first.latitude;
  var north = south;
  for (final coordinate in place.geometry.skip(1)) {
    if (coordinate.longitude < west) west = coordinate.longitude;
    if (coordinate.longitude > east) east = coordinate.longitude;
    if (coordinate.latitude < south) south = coordinate.latitude;
    if (coordinate.latitude > north) north = coordinate.latitude;
  }
  return west <= viewport.east &&
      east >= viewport.west &&
      south <= viewport.north &&
      north >= viewport.south;
}

double _distanceToBuildingMeters(CampusPlace place, CampusCoordinate point) {
  if (_containsCoordinate(place.geometry, point)) return 0;
  final originLatitude = point.latitude * math.pi / 180;
  final metersPerLongitude = 111320 * math.cos(originLatitude);
  const metersPerLatitude = 110540.0;
  double x(CampusCoordinate coordinate) =>
      (coordinate.longitude - point.longitude) * metersPerLongitude;
  double y(CampusCoordinate coordinate) =>
      (coordinate.latitude - point.latitude) * metersPerLatitude;

  var distanceSquared = double.infinity;
  final coordinates = place.geometry;
  for (var index = 0; index < coordinates.length; index++) {
    final start = coordinates[index];
    final end = coordinates[(index + 1) % coordinates.length];
    final startX = x(start);
    final startY = y(start);
    final deltaX = x(end) - startX;
    final deltaY = y(end) - startY;
    final lengthSquared = deltaX * deltaX + deltaY * deltaY;
    final fraction =
        lengthSquared <= 1e-9
            ? 0.0
            : (-(startX * deltaX + startY * deltaY) / lengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
    final nearestX = startX + deltaX * fraction;
    final nearestY = startY + deltaY * fraction;
    distanceSquared =
        math
            .min(distanceSquared, nearestX * nearestX + nearestY * nearestY)
            .toDouble();
  }
  return math.sqrt(distanceSquared);
}

double _buildingAreaSquareMeters(CampusPlace place) {
  final coordinates = place.geometry;
  if (coordinates.length < 3) return double.infinity;
  final origin = coordinates.first;
  final referenceLatitude = coordinates.first.latitude * math.pi / 180;
  final metersPerLongitude = 111320 * math.cos(referenceLatitude);
  const metersPerLatitude = 110540.0;
  double x(CampusCoordinate coordinate) =>
      (coordinate.longitude - origin.longitude) * metersPerLongitude;
  double y(CampusCoordinate coordinate) =>
      (coordinate.latitude - origin.latitude) * metersPerLatitude;

  var twiceArea = 0.0;
  for (var index = 0; index < coordinates.length; index++) {
    final current = coordinates[index];
    final next = coordinates[(index + 1) % coordinates.length];
    twiceArea += x(current) * y(next) - x(next) * y(current);
  }
  return twiceArea.abs() / 2;
}

bool _sameCamera(
  CampusCoordinate? expectedCenter,
  double? expectedZoom,
  CampusCoordinate actualCenter,
  double actualZoom,
) {
  if (expectedCenter == null || expectedZoom == null) return false;
  const coordinateTolerance = 0.00001;
  const zoomTolerance = 0.01;
  return (expectedCenter.longitude - actualCenter.longitude).abs() <=
          coordinateTolerance &&
      (expectedCenter.latitude - actualCenter.latitude).abs() <=
          coordinateTolerance &&
      (expectedZoom - actualZoom).abs() <= zoomTolerance;
}

bool _containsCoordinate(
  List<CampusCoordinate> ring,
  CampusCoordinate coordinate,
) {
  if (ring.length < 3) return false;
  var inside = false;
  for (
    var currentIndex = 0, previousIndex = ring.length - 1;
    currentIndex < ring.length;
    previousIndex = currentIndex++
  ) {
    final current = ring[currentIndex];
    final previous = ring[previousIndex];
    final cross =
        (coordinate.longitude - previous.longitude) *
            (current.latitude - previous.latitude) -
        (coordinate.latitude - previous.latitude) *
            (current.longitude - previous.longitude);
    if (cross.abs() < 1e-10 &&
        coordinate.longitude >=
            (current.longitude < previous.longitude
                ? current.longitude
                : previous.longitude) &&
        coordinate.longitude <=
            (current.longitude > previous.longitude
                ? current.longitude
                : previous.longitude) &&
        coordinate.latitude >=
            (current.latitude < previous.latitude
                ? current.latitude
                : previous.latitude) &&
        coordinate.latitude <=
            (current.latitude > previous.latitude
                ? current.latitude
                : previous.latitude)) {
      return true;
    }
    final crossesLatitude =
        (current.latitude > coordinate.latitude) !=
        (previous.latitude > coordinate.latitude);
    if (crossesLatitude &&
        coordinate.longitude <
            (previous.longitude - current.longitude) *
                    (coordinate.latitude - current.latitude) /
                    (previous.latitude - current.latitude) +
                current.longitude) {
      inside = !inside;
    }
  }
  return inside;
}
