import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "../../campus_places/campus_places.dart";
import "../../external_navigation/external_navigation.dart";
import "../../../services/campus_settings_service.dart";
import "../../../services/host_platform.dart";
import "../../../pages/host_permission_purpose_overlay.dart";
import "../../../services/platform_environment.dart";
import "../campus_map_controller.dart";
import "../campus_map_models.dart";
import "../campus_user_location.dart";
import "../indoor_map.dart";
import "../layers/layers.dart";
import "mapbox_campus_map_view.dart";
import "mapbox_layer_panel.dart";
import "mapbox_map_engine.dart";
import "mapbox_offline_cache.dart";
import 'package:mychu/widgets/apple_window_controls.dart';

/// Mapbox-powered campus map page.
///
/// Mapbox owns basemap rendering and hosted resources. MyCHU keeps the
/// SDK-independent place resolver, plugin navigation and semantic place data.
class MapboxCampusMapPage extends StatefulWidget {
  final bool asRootTab;
  final UnifiedPlaceRequest? destination;

  /// 业务 App 请求显示并聚焦业务图层（临时请求，不写用户偏好）。
  final MapLayerFocusRequest? layerFocus;
  final CampusPlacesService? placesService;
  final MapboxMapEngine? engine;
  final MapboxOfflineCache? offlineCache;
  final ExternalNavigationCapability? externalNavigation;
  final CampusUserLocationService? userLocationService;
  final MapLayerRegistry? layerRegistry;
  final MapLayerManager? layerManager;

  @visibleForTesting
  final HostPlatform? hostPlatformOverride;

  const MapboxCampusMapPage({
    super.key,
    this.asRootTab = false,
    this.destination,
    this.layerFocus,
    this.placesService,
    this.engine,
    this.offlineCache,
    this.externalNavigation,
    this.userLocationService,
    this.layerRegistry,
    this.layerManager,

    @visibleForTesting this.hostPlatformOverride,
  });

  @override
  State<MapboxCampusMapPage> createState() => _MapboxCampusMapPageState();
}

class _MapboxCampusMapPageState extends State<MapboxCampusMapPage> {
  static const double _locateZoom = 17;

  bool get _isHarmony =>
      (widget.hostPlatformOverride ?? HostPlatform.current) ==
      HostPlatform.harmony;

  late final CampusPlacesService _placesService;
  late final MapboxMapEngine _engine;
  late final MapboxOfflineCache _offlineCache;
  late final ExternalNavigationCapability _externalNavigation;
  late final CampusUserLocationService _userLocationService;
  late final CampusMapController _controller;
  late final MapLayerManager _layerManager;
  bool _ownsLayerManager = false;
  final TextEditingController _search = TextEditingController();

  bool _destinationApplied = false;
  bool _layerFocusApplied = false;
  bool _layerOpenBusy = false;
  bool _locating = false;
  String? _offlineCacheIdentity;
  String? _campusIdForLayers;
  Future<void>? _layerCampusSync;

  @override
  void initState() {
    super.initState();
    if (_isHarmony) return;
    _placesService =
        widget.placesService ??
        CampusPlacesService(releaseCoordinator: MapReleaseCoordinator.shared);
    _engine = widget.engine ?? MapboxMapEngine();
    _offlineCache =
        widget.offlineCache ?? MapboxOfflineCache(config: _engine.config);
    _externalNavigation =
        widget.externalNavigation ?? ExternalNavigationCapability();
    _userLocationService =
        widget.userLocationService ?? CampusUserLocationService();
    _engine.onPlaceTap = _onMapPlaceTap;
    _controller = CampusMapController(
      placesService: _placesService,
      engine: _engine,
    );
    final injectedManager = widget.layerManager;
    _ownsLayerManager = injectedManager == null;
    _layerManager =
        injectedManager ??
        MapLayerManager(registry: widget.layerRegistry ?? MapLayerRegistry.shared);
    _layerManager.onCameraRequest = _onLayerCameraRequest;
    _layerManager.onSelectionChanged = _onLayerSelectionChanged;
    _layerManager.addListener(_onLayersChanged);
    _engine.onMapLayerTap = _onMapLayerTap;
    _engine.onIndoorSpaceTap = (spaceId) {
      unawaited(_controller.selectIndoorSpace(spaceId));
    };
    _engine.onCameraIdle = (center, zoom, viewportBounds) {
      _layerManager.handleCamera(zoom, viewportBounds: viewportBounds);
      unawaited(_syncMapLayers());
      unawaited(
        _controller.handleCameraIdle(
          center,
          zoom,
          viewportBounds: viewportBounds,
        ),
      );
    };
    _controller.addListener(_onState);
    unawaited(_initializeController());
  }

  Future<void> _initializeController() async {
    final campusId = await campusSettingsService.read();
    if (!mounted) return;
    await _controller.initialize(preferredCampusId: campusId);
  }

  void _onState() {
    if (!mounted) return;
    final state = _controller.state;
    final campus =
        state.campusId == null
            ? null
            : _placesService.campusById(state.campusId!);
    if (state.selected != null && _layerManager.selectedEntry != null) {
      // 校园地点优先：选中地点时收起业务图层要素卡。
      _layerManager.clearSelection();
    }
    setState(() {});
    final cacheIdentity =
        campus == null ? null : _offlineCache.cacheIdentity(campus);
    if (cacheIdentity != _offlineCacheIdentity) {
      _offlineCacheIdentity = cacheIdentity;
      if (campus != null) unawaited(_prepareOfflineCache(campus));
    }
    unawaited(_syncCampusLayers(state.campusId));
    unawaited(_syncMapLayers());
    _applyDestinationIfPending();
    _applyLayerFocusIfPending();
  }

  /// 图层管理按校区绑定：切换校区时停用不适用图层，恢复适用图层的偏好。
  ///
  /// 返回本次（或正在进行的）绑定过程，业务图层定位必须等它完成，
  /// 否则管理器还没有当前校区，定位会直接失败。
  Future<void> _syncCampusLayers(String? campusId) {
    final inFlight = _layerCampusSync;
    if (campusId == _campusIdForLayers) {
      return inFlight ?? Future<void>.value();
    }
    _campusIdForLayers = campusId;
    final future =
        campusId == null
            ? _layerManager.detachCampus()
            : _layerManager.attachCampus(campusId);
    _layerCampusSync = future;
    return future;
  }

  void _onLayersChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_syncMapLayers());
  }

  Future<void> _syncMapLayers() async {
    if (!mounted) return;
    await _engine.applyMapLayers(_layerManager.renderStates);
  }

  void _onLayerSelectionChanged() {
    if (!mounted) return;
    // 业务图层要素详情卡与校园地点卡互斥，避免底部堆叠两张卡片。
    if (_layerManager.selectedEntry != null && _controller.state.selected != null) {
      unawaited(_controller.clearSelection());
    }
    setState(() {});
  }

  void _onLayerCameraRequest(MapLayerCameraRequest request) {
    if (!mounted) return;
    unawaited(_engine.moveCameraForLayer(request));
  }

  void _onMapLayerTap(MapLayerHit hit) {
    if (!mounted) return;
    _layerManager.handleFeatureTap(hit);
  }

  /// 业务 App 请求的图层定位：等地图就绪后执行一次。
  void _applyLayerFocusIfPending() {
    final request = widget.layerFocus;
    if (request == null || _layerFocusApplied) return;
    if (_controller.state.status != CampusMapStatus.ready) return;
    _layerFocusApplied = true;
    unawaited(_applyLayerFocus(request));
  }

  Future<void> _applyLayerFocus(MapLayerFocusRequest request) async {
    final targetCampusId = request.campusId;
    final currentCampusId = _controller.state.campusId;
    if (targetCampusId != null && targetCampusId != currentCampusId) {
      await _controller.switchCampus(targetCampusId);
      if (!mounted) return;
    }
    await _syncCampusLayers(_controller.state.campusId);
    if (!mounted) return;
    final result = await _layerManager.focusFeature(
      layerId: request.layerId,
      featureId: request.featureId,
      select: request.select,
    );
    if (!mounted) return;
    if (result == MapLayerFocusResult.featureNotFound) {
      _showMessage("该要素暂无可用位置信息");
    } else if (result == MapLayerFocusResult.unknownLayer ||
        result == MapLayerFocusResult.unsupportedCampus) {
      _showMessage("该图层在当前校区不可用");
    }
    await _syncMapLayers();
  }

  Future<void> _showLayerSheet() async {
    if (!_layerManager.hasLayers) {
      _showMessage("当前校区暂无可用图层");
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => MapLayerSheet(
            manager: _layerManager,
            onToggle: (layerId, visible) async {
              final persisted = await _layerManager.setVisible(layerId, visible);
              if (!persisted && sheetContext.mounted) {
                _showMessage("图层设置未能保存，本次仍按当前选择显示");
              }
              await _syncMapLayers();
            },
            onRetry: (layerId) async {
              await _layerManager.refreshLayer(layerId);
              await _syncMapLayers();
            },
            onRefresh: (layerId) async {
              await _layerManager.refreshLayer(layerId);
              await _syncMapLayers();
            },
          ),
    );
  }

  Future<void> _openLayerOwnerApp() async {
    final selection = _layerManager.selectedEntry;
    final feature = selection?.selectedFeature;
    if (selection == null || feature == null) return;
    final open = selection.definition.interaction.openOwnerApp;
    if (open == null) return;
    setState(() => _layerOpenBusy = true);
    var opened = false;
    try {
      opened = await open(
        context,
        MapLayerFeatureSelection(
          definition: selection.definition,
          feature: feature,
          campusId: _controller.state.campusId ?? "",
        ),
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _layerOpenBusy = false);
    if (!opened) _showMessage("暂时无法打开该应用");
  }

  Future<void> _prepareOfflineCache(CampusEntry campus) async {
    try {
      await _offlineCache.prepareCampus(campus);
    } catch (_) {
      // Offline preparation is best-effort. The visible map and semantic
      // release remain usable when the network or native cache is unavailable.
    }
  }

  void _applyDestinationIfPending() {
    final destination = widget.destination;
    if (destination == null || _destinationApplied) return;
    if (_controller.state.status != CampusMapStatus.ready) return;
    _destinationApplied = true;
    unawaited(_resolveRequest(destination));
  }

  Future<void> _resolve(String raw) async {
    if (raw.trim().isEmpty) return;
    await _resolveRequest(UnifiedPlaceRequest(rawText: raw));
  }

  Future<void> _resolveRequest(UnifiedPlaceRequest request) async {
    final requestCampusId = _controller.state.campusId;
    final result = await _controller.openRequest(request);
    if (!mounted || result.status == PlaceResolutionStatus.resolved) return;
    if (requestCampusId != _controller.state.campusId &&
        result.status != PlaceResolutionStatus.campusNotFound) {
      return;
    }
    if (result.status == PlaceResolutionStatus.ambiguous &&
        result.candidates.isNotEmpty) {
      await _showCandidates(result.candidates);
    } else {
      _showMessage(result.message ?? "未找到相关地点");
    }
  }

  Future<void> _onMapPlaceTap(
    CampusPlaceId placeId,
    CampusCoordinate clickCoordinate,
  ) async {
    final result = await _controller.handlePlaceTap(placeId, clickCoordinate);
    if (!mounted || result == null) return;
    if (_controller.state.campusId != placeId.campusId) return;
    if (result.status != PlaceResolutionStatus.resolved) {
      _showMessage(result.message ?? "未识别该地点");
    }
  }

  Future<void> _showCandidates(List<PlaceCandidate> candidates) async {
    final selected = await showModalBottomSheet<PlaceCandidate>(
      context: context,
      builder: (context) => MapPlaceCandidateSheet(candidates: candidates),
    );
    if (selected != null) await _controller.selectCandidate(selected);
  }

  Future<void> _showCampusSelector() async {
    final campuses = _placesService.campuses;
    if (campuses.isEmpty) return;
    final current = _controller.state.campusId;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder:
          (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "选择校区",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final campus in campuses)
                  ListTile(
                    title: Text(campus.displayName),
                    trailing:
                        campus.campusId == current
                            ? const Icon(Icons.check)
                            : null,
                    onTap: () => Navigator.of(context).pop(campus.campusId),
                  ),
              ],
            ),
          ),
    );
    if (selected != null && selected != current) {
      await _controller.switchCampus(selected);
    }
  }

  Future<void> _clearSelection() => _controller.clearSelection();

  Future<void> _locateMe() async {
    final campusId = _controller.state.campusId;
    if (campusId == null || _locating) return;
    final campus = _placesService.campusById(campusId);
    if (campus == null) return;
    setState(() => _locating = true);
    final result = await _userLocationService.acquire(
      presentPurpose:
          (purpose) => presentHostPermissionPurpose(context, purpose),
    );
    if (!mounted) return;
    setState(() => _locating = false);
    if (!_isCurrentCampus(campusId)) return;
    switch (result.status) {
      case CampusUserLocationStatus.located:
        final coordinate = result.coordinate!;
        if (campus.bounds?.contains(coordinate) == true) {
          if (!_isCurrentCampus(campusId)) return;
          await _engine.showUserLocation(coordinate);
          if (!_isCurrentCampus(campusId)) return;
          await _engine.moveCamera(
            center: coordinate,
            zoom: _locateZoom,
            animate: true,
          );
        } else {
          await _fallBackToCampusOverview("当前位置不在该校区范围内", campusId: campusId);
        }
      case CampusUserLocationStatus.denied:
        await _fallBackToCampusOverview(
          "未授予定位权限，请在系统设置中开启",
          campusId: campusId,
        );
      case CampusUserLocationStatus.serviceUnavailable:
        await _fallBackToCampusOverview("无法获取当前位置", campusId: campusId);
    }
  }

  Future<void> _fallBackToCampusOverview(
    String message, {
    required String campusId,
  }) async {
    if (!_isCurrentCampus(campusId)) return;
    await _engine.clearUserLocation();
    if (!_isCurrentCampus(campusId)) return;
    _showMessage(message);
    await _engine.resetToDefaultView();
  }

  bool _isCurrentCampus(String campusId) =>
      mounted && _controller.state.campusId == campusId;

  /// 当前选中的业务图层要素是否有详情卡（业务可声明只展示通用卡）。
  bool get _layerCardVisible {
    final entry = _layerManager.selectedEntry;
    return entry != null &&
        entry.selectedFeature != null &&
        entry.definition.interaction.showsDetailCard;
  }

  Widget _buildLayerCard() {
    final entry = _layerManager.selectedEntry!;
    return MapLayerFeatureCard(
      selection: MapLayerFeatureSelection(
        definition: entry.definition,
        feature: entry.selectedFeature!,
        campusId: _controller.state.campusId ?? "",
      ),
      busy: _layerOpenBusy,
      onClose: () => _layerManager.clearSelection(),
      onOpenOwnerApp:
          entry.definition.interaction.openOwnerApp == null
              ? null
              : _openLayerOwnerApp,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isHarmony) {
      return _HarmonyMapUnavailablePage(asRootTab: widget.asRootTab);
    }

    final state = _controller.state;
    final campus =
        state.campusId == null
            ? null
            : _placesService.campusById(state.campusId!);
    final selection = state.selected;
    final indoorView = state.indoorView;
    final status = switch (state.status) {
      CampusMapStatus.idle => "初始化中",
      CampusMapStatus.loading => "加载中",
      CampusMapStatus.ready => "就绪",
      CampusMapStatus.error => _mapErrorMessage(state.errorMessage),
    };
    final mapReady =
        state.status == CampusMapStatus.ready &&
        campus != null &&
        _engine.isPrepared;
    final presentation =
        selection == null
            ? null
            : MapPlacePresentation.fromResolvedSelection(
              selection,
              campusName:
                  _placesService.campusById(selection.campusId)?.displayName,
            );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          automaticallyImplyLeading: !widget.asRootTab,
          title: const Text("校园地图"),
        ),
      ),
      body: _buildMapBody(context, mapReady, presentation, status, indoorView),
    );
  }

  Widget _buildMapBody(
    BuildContext context,
    bool mapReady,
    MapPlacePresentation? presentation,

    String status,
    IndoorViewState? indoorView,
  ) {
    final environment = PlatformEnvironment.fromContext(context);
    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isAtLeastMedium) {
      return _buildTabletMapBody(
        context,
        mapReady,
        presentation,

        status,
        indoorView,
      );
    }

    final placeCardVisible =
        presentation != null && presentation.showInfoCard && !_layerCardVisible;
    final cardVisible = placeCardVisible || _layerCardVisible;
    final floorSelectorBottom = cardVisible ? 116.0 : 12.0;
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: "支持教室编号查询",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: _resolve,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _resolve(_search.text),
                  ),
                ],
              ),
            ),
            Expanded(
              child:
                  mapReady
                      ? MapboxCampusMapView(engine: _engine)
                      : _StatusView(status: status),
            ),
          ],
        ),
        if (indoorView != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 12,
            bottom: floorSelectorBottom,
            child: IndoorFloorSelector(
              state: indoorView,
              onFloorSelected:
                  (floor) => unawaited(_controller.setIndoorFloor(floor)),
              onExit: () => unawaited(_controller.exitIndoor()),
            ),
          ),
        Positioned(
          right: 12,
          top: 76,
          bottom: _layerCardVisible ? 160 : (cardVisible ? 100 : 12),
          width: 48,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              reverse: true,
              child: MapboxMapControls(
                onLayers: _showLayerSheet,
                onCampus: _showCampusSelector,
                onZoomIn: () => _engine.zoomBy(1, animate: true),
                onZoomOut: () => _engine.zoomBy(-1, animate: true),
                onLocate: _locateMe,
                mapReady: mapReady,
                locating: _locating,
              ),
            ),
          ),
        ),
        if (placeCardVisible)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: MapPlaceInfoCard(
              presentation: presentation,
              onClear: _clearSelection,
              onNavigate:
                  (target) => _externalNavigation.showSheet(context, target),
            ),
          ),
        if (_layerCardVisible)
          Positioned(left: 8, right: 8, bottom: 8, child: _buildLayerCard()),
      ],
    );
  }

  Widget _buildTabletMapBody(
    BuildContext context,
    bool mapReady,
    MapPlacePresentation? presentation,

    String status,
    IndoorViewState? indoorView,
  ) {
    final selectedPresentation = presentation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth =
            (constraints.maxWidth - 24).clamp(0.0, 360.0).toDouble();
        final cardVisible =
            (selectedPresentation?.showInfoCard == true) || _layerCardVisible;
        final cardWidth =
            (constraints.maxWidth - 32).clamp(0.0, 520.0).toDouble();
        final cardLeft = (constraints.maxWidth - cardWidth) / 2;
        final search = DecoratedBox(
          key: const ValueKey('tablet-map-search'),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: "支持教室编号查询",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _resolve,
                  ),
                ),
                IconButton(
                  tooltip: "搜索地点",
                  onPressed: () => _resolve(_search.text),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
        );
        return Stack(
          children: [
            Positioned.fill(
              child:
                  mapReady
                      ? KeyedSubtree(
                        key: const ValueKey('tablet-map-canvas'),
                        child: MapboxCampusMapView(engine: _engine),
                      )
                      : _StatusView(status: status),
            ),
            Positioned(left: 12, top: 12, width: searchWidth, child: search),
            if (indoorView != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: 12,
                bottom: cardVisible ? 116 : 16,
                child: IndoorFloorSelector(
                  state: indoorView,
                  onFloorSelected:
                      (floor) => unawaited(_controller.setIndoorFloor(floor)),
                  onExit: () => unawaited(_controller.exitIndoor()),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              right: 16,
              top: 12,
              bottom: cardVisible ? 116 : 16,
              width: 48,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  reverse: true,
                  child: KeyedSubtree(
                    key: const ValueKey('tablet-map-controls'),
                    child: MapboxMapControls(
                      onLayers: _showLayerSheet,
                      onCampus: _showCampusSelector,
                      onZoomIn: () => _engine.zoomBy(1, animate: true),
                      onZoomOut: () => _engine.zoomBy(-1, animate: true),
                      onLocate: _locateMe,
                      mapReady: mapReady,
                      locating: _locating,
                    ),
                  ),
                ),
              ),
            ),
            if (cardVisible)
              Positioned(
                left: cardLeft,
                width: cardWidth,
                bottom: 12,
                child: KeyedSubtree(
                  key: const ValueKey('tablet-map-selection'),
                  child:
                      _layerCardVisible
                          ? _buildLayerCard()
                          : MapPlaceInfoCard(
                            presentation: selectedPresentation!,
                            onClear: _clearSelection,
                            onNavigate:
                                (target) => _externalNavigation.showSheet(
                                  context,
                                  target,
                                ),
                          ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    if (!_isHarmony) {
      _layerManager
        ..removeListener(_onLayersChanged)
        ..onCameraRequest = null
        ..onSelectionChanged = null;
      if (_ownsLayerManager) _layerManager.dispose();
      _controller
        ..removeListener(_onState)
        ..dispose();
    }
    _search.dispose();
    super.dispose();
  }
}

class _HarmonyMapUnavailablePage extends StatelessWidget {
  const _HarmonyMapUnavailablePage({required this.asRootTab});

  final bool asRootTab;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: asRootTab ? null : AppBar(title: const Text("校园地图")),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                "校园地图暂不可用",
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text("HarmonyOS 版地图能力尚在适配中。", textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isError = status.contains("错误");

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isError) const CircularProgressIndicator(),
            if (!isError) const SizedBox(height: 16),
            Text(status, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class IndoorFloorSelector extends StatelessWidget {
  const IndoorFloorSelector({
    super.key,
    required this.state,
    required this.onFloorSelected,
    required this.onExit,
  });

  final IndoorViewState state;
  final ValueChanged<int> onFloorSelected;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surfaceContainer;
    final onSurface = theme.colorScheme.onSurface;
    final selectedFloorColor = theme.colorScheme.primaryContainer;
    final selectedFloorTextColor = theme.colorScheme.onPrimaryContainer;
    return Material(
      elevation: 4,
      color: surface,
      key: const ValueKey("indoor-floor-selector"),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 76,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: state.context.displayName,
                      child: Text(
                        state.context.buildingId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 30,
                    child: IconButton(
                      tooltip: "退出室内地图",
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: onExit,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
              if (kDebugMode)
                Text(
                  state.context.publicationVerified ? "位置已核验" : "位置未核验",
                  maxLines: 1,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              const SizedBox(height: 4),
              for (final floor in state.context.floors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Semantics(
                    button: true,
                    selected: state.activeFloor == floor,
                    label: "$floor 楼",
                    child: Material(
                      color:
                          state.activeFloor == floor
                              ? selectedFloorColor
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onFloorSelected(floor),
                        child: SizedBox(
                          height: 38,
                          child: Center(
                            child: Text(
                              "${floor}F",
                              style: TextStyle(
                                color:
                                    state.activeFloor == floor
                                        ? selectedFloorTextColor
                                        : onSurface,
                                fontSize: 13,
                                fontWeight:
                                    state.activeFloor == floor
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom card for a resolved semantic campus place.
class MapPlaceInfoCard extends StatelessWidget {
  const MapPlaceInfoCard({
    super.key,
    required this.presentation,
    required this.onClear,
    required this.onNavigate,
  });

  final MapPlacePresentation presentation;
  final VoidCallback onClear;
  final ValueChanged<ExternalNavigationTarget> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = presentation.campusPlace;
    final navTarget = presentation.navigationTarget;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (presentation.subtitle?.isNotEmpty == true)
                    Text(
                      presentation.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (place?.verified == true)
                    Text("位置已确认", style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            IconButton(
              tooltip:
                  navTarget != null && presentation.showExternalNavigation
                      ? "外部导航"
                      : "目标尚未配置导航入口",
              onPressed:
                  navTarget == null || !presentation.showExternalNavigation
                      ? null
                      : () => onNavigate(navTarget),
              icon: const Icon(Icons.directions_outlined),
            ),
            IconButton(
              tooltip: "关闭地点信息",
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// Candidate list shown when a search resolves to multiple semantic places.
class MapPlaceCandidateSheet extends StatelessWidget {
  const MapPlaceCandidateSheet({
    super.key,
    required this.candidates,
    this.onSelected,
  });

  final List<PlaceCandidate> candidates;
  final ValueChanged<PlaceCandidate>? onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '匹配到多个地点',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final candidate in candidates)
          ListTile(
            title: Text(candidate.label),
            subtitle: Text(candidate.campusName),
            onTap: () {
              onSelected?.call(candidate);
              if (onSelected == null) {
                Navigator.of(context).pop(candidate);
              }
            },
          ),
      ],
    ),
  );
}

class MapboxMapControls extends StatelessWidget {
  const MapboxMapControls({
    super.key,
    required this.onLayers,
    required this.onCampus,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocate,
    this.mapReady = true,
    this.locating = false,
  });

  final VoidCallback onLayers;
  final VoidCallback onCampus;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onLocate;
  final bool mapReady;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(context, Icons.layers_outlined, "地图图层", onLayers),
        const SizedBox(height: 8),
        _button(context, Icons.location_city, "选择校区", onCampus),
        const SizedBox(height: 8),
        _button(context, Icons.add, "放大", onZoomIn, enabled: mapReady),
        const SizedBox(height: 8),
        _button(context, Icons.remove, "缩小", onZoomOut, enabled: mapReady),
        const SizedBox(height: 8),
        locating
            ? _button(
              context,
              Icons.my_location,
              "定位中",
              onLocate,
              enabled: false,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
            : _button(
              context, Icons.my_location, "定位", onLocate, enabled: mapReady,
            ),
      ],
    );
  }

  Widget _button(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    Widget? child,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: child ?? Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.surface,
        disabledBackgroundColor: colorScheme.surface,
        disabledForegroundColor: colorScheme.primary,
        shape: const CircleBorder(),
        fixedSize: const Size(44, 44),
      ),
    );
  }
}

String _mapErrorMessage(String? message) {
  const safeMessages = {'没有可用的校区', '该校区暂不可用，请稍后重试'};
  if (message != null && safeMessages.contains(message)) {
    return message;
  }
  return '地图暂时无法加载，请稍后重试。';
}
