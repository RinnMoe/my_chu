/// 图层管理器：激活、可见性、数据订阅与生命周期。
///
/// 本类不持有任何地图 SDK 对象，也不认识具体业务：数据来自
/// [MapLayerProvider]，展示结果以 [MapLayerRenderState] 交给页面/渲染器，
/// 相机请求通过回调交给页面。这样图层管理层可以完全在纯 Dart 测试中验证。
library;

import "dart:async";
import "dart:math" as math;

import "package:flutter/foundation.dart";

import "../../../services/user_error_message.dart";
import "../../campus_places/campus_places.dart";
import "../layers/map_layer_definition.dart";
import "map_layer_models.dart";
import "map_layer_preferences.dart";
import "map_layer_provider.dart";
import "map_layer_registry.dart";
import "map_layer_render_state.dart";

/// 单个图层的加载状态。
enum MapLayerLoadStatus {
  /// 未加载（图层未可见或刚刚停用）。
  idle,
  loading,
  ready,

  /// 加载成功但没有任何要素。
  empty,
  error,
}

/// 图层导航请求的处理结果；业务据此决定是否提示用户。
enum MapLayerFocusResult {
  focused,

  /// 图层已显示但未定位具体要素（无 featureId 或仅要求显示图层）。
  revealed,
  unknownLayer,
  unsupportedCampus,
  mapNotReady,
  featureNotFound,
}

/// 图层面板与页面读取的单个图层状态。
class MapLayerEntry {
  final MapLayerDefinition definition;

  /// 用户长期保存的开关偏好。
  final bool enabled;

  /// 业务导航临时请求的显示（不写入偏好）。
  final bool transientVisible;

  final MapLayerLoadStatus status;
  final List<MapLayerFeature> features;
  final String? errorMessage;
  final MapLayerFeature? selectedFeature;

  const MapLayerEntry({
    required this.definition,
    required this.enabled,
    required this.transientVisible,
    required this.status,
    required this.features,
    this.errorMessage,
    this.selectedFeature,
  });

  String get layerId => definition.layerId;

  bool get visible => enabled || transientVisible;

  bool get isLoading => status == MapLayerLoadStatus.loading;

  bool get hasError => status == MapLayerLoadStatus.error;
}

class _LayerRuntime {
  MapLayerProvider? provider;
  MapLayerCancellation? cancellation;
  StreamSubscription<MapLayerFeatureUpdate>? subscription;
  Future<void>? inFlight;
  int generation = 0;
  bool activated = false;
  Future<void> transition = Future<void>.value();
}

class MapLayerManager extends ChangeNotifier {
  MapLayerManager({
    MapLayerRegistry? registry,
    MapLayerPreferenceStore? preferences,
  }) : registry = registry ?? MapLayerRegistry.shared,
       _preferences = preferences ?? MapLayerPreferenceStore();

  final MapLayerRegistry registry;
  final MapLayerPreferenceStore _preferences;

  final Map<String, _LayerRuntime> _runtimes = <String, _LayerRuntime>{};
  final Map<String, bool> _enabled = <String, bool>{};
  final Set<String> _transient = <String>{};
  final Map<String, List<MapLayerFeature>> _features =
      <String, List<MapLayerFeature>>{};
  final Map<String, MapLayerLoadStatus> _status =
      <String, MapLayerLoadStatus>{};
  final Map<String, String?> _errors = <String, String?>{};
  final Map<String, MapLayerFeature> _selected = <String, MapLayerFeature>{};
  final Map<String, bool> _aggregateModes = <String, bool>{};

  String? _campusId;
  String? _selectedLayerId;
  double _zoom = 16;
  CampusBounds? _viewportBounds;
  bool _preferencesRestored = false;
  bool _disposed = false;
  int _campusRevision = 0;
  int _boundCampusRevision = 0;
  Future<void>? _preferenceRestore;

  /// 串行化的偏好写入链；为空表示还没有写过。
  Future<void>? _preferenceWrites;

  /// 相机请求回调；页面接上后转成引擎调用（管理器不依赖引擎）。
  void Function(MapLayerCameraRequest request)? onCameraRequest;

  /// 图层选中/取消选中回调；页面据此切换底部卡片。
  VoidCallback? onSelectionChanged;

  static const String _aggregatePrefix = "agg:";

  String? get campusId => _campusId;

  double get zoom => _zoom;

  bool get hasLayers =>
      _campusId != null && registry.forCampus(_campusId!).isNotEmpty;

  /// 当前校区适用图层，按优先级降序；面板与渲染都基于它。
  List<MapLayerEntry> get entries {
    final campusId = _campusId;
    if (campusId == null) return const <MapLayerEntry>[];
    return registry.forCampus(campusId).map(_entryFor).toList(growable: false);
  }

  MapLayerEntry? entryFor(String layerId) {
    final definition = registry.byId(layerId);
    if (definition == null) return null;
    final campusId = _campusId;
    if (campusId == null || !definition.supportsCampus(campusId)) return null;
    return _entryFor(definition);
  }

  /// 当前选中的图层要素（同一时刻最多一个）。
  MapLayerEntry? get selectedEntry {
    final layerId = _selectedLayerId;
    if (layerId == null) return null;
    return entryFor(layerId);
  }

  /// 只读取并应用持久化偏好，不触发任何 Provider 生命周期。
  Future<void> _applyStoredPreferences() async {
    if (_preferencesRestored) return;
    final pending = _preferenceRestore;
    if (pending != null) return pending;
    final flight = _readStoredPreferences();
    _preferenceRestore = flight;
    try {
      await flight;
    } finally {
      if (identical(_preferenceRestore, flight)) _preferenceRestore = null;
    }
  }

  Future<void> _readStoredPreferences() async {
    final stored = await _preferences.readVisibility();
    if (_disposed) return;
    for (final definition in registry.definitions) {
      _enabled[definition.layerId] =
          stored[definition.layerId] ?? definition.defaultVisible;
    }
    // 偏好文件中出现的图层以文件为准；未出现的图层使用声明的默认值。
    _preferencesRestored = true;
    notifyListeners();
  }

  /// 绑定校区：停用不适用图层，激活已开启且适用的图层。
  Future<void> attachCampus(String campusId) async {
    final revision = ++_campusRevision;
    await _detachProviders();
    if (_disposed || revision != _campusRevision) return;
    _campusId = campusId;
    _boundCampusRevision = revision;
    _transient.clear();
    _selected.clear();
    _selectedLayerId = null;
    _features.removeWhere((layerId, _) {
      final definition = registry.byId(layerId);
      return definition == null || !definition.supportsCampus(campusId);
    });
    _status.removeWhere((layerId, _) => !_features.containsKey(layerId));
    _errors.removeWhere((layerId, _) => !_features.containsKey(layerId));
    await _applyStoredPreferences();
    if (_disposed || revision != _campusRevision) return;
    await _syncActiveLayers();
  }

  /// 取消校区绑定（页面销毁或切换中的中间态）。
  Future<void> detachCampus() async {
    final revision = ++_campusRevision;
    await _detachProviders();
    if (_disposed || revision != _campusRevision) return;
    _campusId = null;
    _boundCampusRevision = revision;
    _transient.clear();
    _selected.clear();
    _selectedLayerId = null;
    if (!_disposed) notifyListeners();
  }

  /// 用户在图层面板切换开关。这是唯一会写入持久偏好的入口。
  Future<bool> setVisible(String layerId, bool visible) async {
    final definition = registry.byId(layerId);
    if (definition == null) return false;
    final campusId = _campusId;
    if (campusId == null || !definition.supportsCampus(campusId)) return false;
    await _applyStoredPreferences();
    if (_disposed || _campusId != campusId) return false;
    _enabled[layerId] = visible;
    _transient.remove(layerId);
    // 先把期望状态交给图层生命周期，再等待写盘：写盘慢时不能反过来停掉
    // 用户随后重新开启的图层。写入按调用顺序串行，最后一次切换生效。
    final persisted = _persistVisibility(layerId, visible);
    if (!visible) {
      if (_selected.remove(layerId) != null && _selectedLayerId == layerId) {
        _selectedLayerId = null;
        _notifyFeatureSelected(layerId, null);
      }
      await _deactivate(layerId);
    } else {
      await _activate(layerId);
    }
    if (_disposed) return false;
    notifyListeners();
    onSelectionChanged?.call();
    return await persisted;
  }

  /// 按调用顺序串行写入偏好，避免慢写覆盖快写。
  Future<bool> _persistVisibility(String layerId, bool visible) {
    Future<bool> write() => _preferences.writeVisibility(layerId, visible);
    final previous = _preferenceWrites;
    final next =
        previous == null
            ? write()
            : previous.then(
              (_) => write(),
              onError: (Object _, StackTrace __) => write(),
            );
    _preferenceWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  /// 业务导航临时显示图层，不修改用户偏好。
  Future<void> revealLayer(String layerId) async {
    final definition = registry.byId(layerId);
    final campusId = _campusId;
    if (definition == null || campusId == null) return;
    if (!definition.supportsCampus(campusId)) return;
    await _applyStoredPreferences();
    if (_disposed || _campusId != campusId) return;
    if (_enabled[layerId] == true) return;
    _transient.add(layerId);
    await _activate(layerId);
    if (!_disposed) notifyListeners();
  }

  /// 定位并（可选）选中一个要素。供业务 App → 地图 的跳转使用。
  Future<MapLayerFocusResult> focusFeature({
    required String layerId,
    String? featureId,
    bool select = true,
    bool animate = true,
  }) async {
    final definition = registry.byId(layerId);
    if (definition == null) return MapLayerFocusResult.unknownLayer;
    final campusId = _campusId;
    if (campusId == null) return MapLayerFocusResult.mapNotReady;
    if (!definition.supportsCampus(campusId)) {
      return MapLayerFocusResult.unsupportedCampus;
    }
    await revealLayer(layerId);
    if (_disposed ||
        _campusId != campusId ||
        _boundCampusRevision != _campusRevision ||
        entryFor(layerId)?.visible != true) {
      return MapLayerFocusResult.mapNotReady;
    }
    final current = _features[layerId];
    if (current == null || current.isEmpty) {
      await _load(layerId, force: true);
      if (_disposed ||
          _campusId != campusId ||
          _boundCampusRevision != _campusRevision ||
          entryFor(layerId)?.visible != true) {
        return MapLayerFocusResult.mapNotReady;
      }
    }
    if (featureId == null) {
      final features = _features[layerId];
      final bounds = _boundsOf(features ?? const <MapLayerFeature>[]);
      if (bounds != null) {
        onCameraRequest?.call(
          MapLayerCameraRequest(bounds: bounds, animate: animate),
        );
      }
      return MapLayerFocusResult.revealed;
    }
    final feature = _findFeature(layerId, featureId);
    if (feature == null) return MapLayerFocusResult.featureNotFound;
    final bounds = feature.geometry.bounds;
    if (feature.isPoint) {
      final coordinate = feature.primaryCoordinate;
      if (coordinate != null) {
        onCameraRequest?.call(
          MapLayerCameraRequest(
            center: coordinate,
            zoom: _focusZoom(definition),
            animate: animate,
          ),
        );
      }
    } else if (bounds != null) {
      onCameraRequest?.call(
        MapLayerCameraRequest(bounds: bounds, animate: animate),
      );
    }
    if (select) {
      _select(layerId, feature);
      if (!_disposed) {
        notifyListeners();
        onSelectionChanged?.call();
      }
    }
    return MapLayerFocusResult.focused;
  }

  /// 处理渲染器返回的点击命中。
  void handleFeatureTap(MapLayerHit hit) {
    final definition = registry.byId(hit.layerId);
    if (definition == null || !definition.interaction.tapSelectable) return;
    if (hit.featureId.startsWith(_aggregatePrefix)) {
      _focusAggregate(hit.layerId, hit.featureId);
      return;
    }
    final feature = _findFeature(hit.layerId, hit.featureId);
    if (feature == null) return;
    _select(hit.layerId, feature);
    notifyListeners();
    onSelectionChanged?.call();
  }

  /// 清除选中状态（点击地图空白、切换校区、关闭卡片时调用）。
  void clearSelection() {
    if (_selectedLayerId == null && _selected.isEmpty) return;
    final previousLayerId = _selectedLayerId;
    _selected.clear();
    _selectedLayerId = null;
    _notifyFeatureSelected(previousLayerId, null);
    notifyListeners();
    onSelectionChanged?.call();
  }

  /// 用户或页面请求刷新单个图层的数据。
  Future<void> refreshLayer(String layerId) async {
    final runtime = _runtimes[layerId];
    try {
      await runtime?.provider?.refresh();
    } catch (error) {
      if (_disposed) return;
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "layer_refresh",
      );
    }
    if (_disposed) return;
    final entry = entryFor(layerId);
    if (entry == null || !entry.visible) return;
    await _load(layerId, force: true);
  }

  /// 相机变化：缩放用于聚合展示，视口用于 Provider 按范围加载。
  void handleCamera(double zoom, {CampusBounds? viewportBounds}) {
    _viewportBounds = viewportBounds ?? _viewportBounds;
    if ((zoom - _zoom).abs() < 0.001) return;
    _zoom = zoom;
    if (_aggregateModeChanged() && !_disposed) notifyListeners();
  }

  /// 任一图层的“聚合/明细”档位变化时才需要重建展示数据。
  bool _aggregateModeChanged() {
    var changed = false;
    for (final definition in registry.definitions) {
      final threshold = definition.aggregateBelowZoom;
      if (threshold == null) continue;
      final aggregate = _zoom < threshold;
      if (_aggregateModes[definition.layerId] != aggregate) {
        _aggregateModes[definition.layerId] = aggregate;
        changed = true;
      }
    }
    return changed;
  }

  /// 交给渲染器的展示数据。已排序（优先级升序，后加入者绘制在上层）。
  List<MapLayerRenderState> get renderStates {
    final campusId = _campusId;
    if (campusId == null) return const <MapLayerRenderState>[];
    final definitions = registry.forCampus(campusId).reversed;
    final states = <MapLayerRenderState>[];
    for (final definition in definitions) {
      final entry = _entryFor(definition);
      if (!entry.visible) continue;
      final features = entry.features;
      if (features.isEmpty) continue;
      final display = _displayFeatures(definition, features);
      if (display.isEmpty) continue;
      states.add(
        MapLayerRenderState(
          layerId: definition.layerId,
          priority: definition.priority,
          style: definition.style,
          interactive: definition.interaction.tapSelectable,
          features: display,
          selectedFeatureId: _selected[definition.layerId]?.featureId,
        ),
      );
    }
    return states;
  }

  List<MapLayerDisplayFeature> _displayFeatures(
    MapLayerDefinition definition,
    List<MapLayerFeature> features,
  ) {
    final style = definition.style;
    final selectedId = _selected[definition.layerId]?.featureId;
    final threshold = definition.aggregateBelowZoom;
    final aggregate = threshold != null && _zoom < threshold;
    if (!aggregate) {
      return <MapLayerDisplayFeature>[
        for (final feature in features)
          if (feature.geometry.hasRenderableGeometry)
            MapLayerDisplayFeature(
              featureId: feature.featureId,
              geometry: feature.geometry,
              badgeText: feature.resolvedBadgeText,
              color: feature.color ?? style.colorFor(feature.status),
              emphasized: feature.featureId == selectedId,
            ),
      ];
    }
    final groups = <String, List<MapLayerFeature>>{};
    final leftovers = <MapLayerFeature>[];
    for (final feature in features) {
      final group = feature.group;
      if (group != null &&
          feature.isPoint &&
          feature.primaryCoordinate != null) {
        groups
            .putIfAbsent(group.groupId, () => <MapLayerFeature>[])
            .add(feature);
      } else if (feature.geometry.hasRenderableGeometry) {
        leftovers.add(feature);
      }
    }
    final display = <MapLayerDisplayFeature>[];
    for (final entry in groups.entries) {
      final members = entry.value;
      final coordinate = _centroid(members);
      if (coordinate == null) continue;
      final status = _aggregateStatus(members);
      // 分组名比成员数量更能说明“这是哪里”；没有名称时才退回数量。
      final label = members.first.group?.label;
      display.add(
        MapLayerDisplayFeature(
          featureId: "$_aggregatePrefix${entry.key}",
          geometry: MapLayerGeometry.point(coordinate),
          badgeText: label ?? members.length.toString(),
          color: style.colorFor(status),
          emphasized:
              _selectedLayerId == definition.layerId &&
              _selected[definition.layerId]?.group?.groupId == entry.key,
          isAggregate: true,
        ),
      );
    }
    for (final feature in leftovers) {
      display.add(
        MapLayerDisplayFeature(
          featureId: feature.featureId,
          geometry: feature.geometry,
          badgeText: feature.resolvedBadgeText,
          color: feature.color ?? style.colorFor(feature.status),
          emphasized: feature.featureId == selectedId,
        ),
      );
    }
    return display;
  }

  /// 聚合状态规则：任一要素可用即可用；全部不可用才不可用；否则未知。
  ///
  /// 这条规则保证“部分设备查询失败”不会被聚合成“已占满”。
  static MapLayerFeatureStatus _aggregateStatus(List<MapLayerFeature> members) {
    if (members.any((f) => f.status == MapLayerFeatureStatus.positive)) {
      return MapLayerFeatureStatus.positive;
    }
    final allNegative = members.every(
      (f) => f.status == MapLayerFeatureStatus.negative,
    );
    if (allNegative) return MapLayerFeatureStatus.negative;
    if (members.any((f) => f.status == MapLayerFeatureStatus.neutral)) {
      return MapLayerFeatureStatus.neutral;
    }
    return MapLayerFeatureStatus.unknown;
  }

  CampusCoordinate? _centroid(List<MapLayerFeature> members) {
    var longitude = 0.0;
    var latitude = 0.0;
    var count = 0;
    for (final member in members) {
      final coordinate = member.primaryCoordinate;
      if (coordinate == null) continue;
      longitude += coordinate.longitude;
      latitude += coordinate.latitude;
      count++;
    }
    if (count == 0) return null;
    return CampusCoordinate(
      longitude: longitude / count,
      latitude: latitude / count,
    );
  }

  CampusBounds? _boundsOf(List<MapLayerFeature> features) {
    CampusBounds? bounds;
    for (final feature in features) {
      final featureBounds = feature.geometry.bounds;
      if (featureBounds == null) continue;
      bounds =
          bounds == null
              ? featureBounds
              : CampusBounds(
                west:
                    featureBounds.west < bounds.west
                        ? featureBounds.west
                        : bounds.west,
                south:
                    featureBounds.south < bounds.south
                        ? featureBounds.south
                        : bounds.south,
                east:
                    featureBounds.east > bounds.east
                        ? featureBounds.east
                        : bounds.east,
                north:
                    featureBounds.north > bounds.north
                        ? featureBounds.north
                        : bounds.north,
              );
    }
    return bounds;
  }

  double _focusZoom(MapLayerDefinition definition) {
    final maxZoom = definition.style.maxZoom;
    return maxZoom.isFinite ? (maxZoom < 18 ? maxZoom : 18) : 18;
  }

  void _focusAggregate(String layerId, String featureId) {
    final definition = registry.byId(layerId);
    if (definition == null) return;
    final groupId = featureId.substring(_aggregatePrefix.length);
    final members = (_features[layerId] ?? const <MapLayerFeature>[])
        .where((feature) => feature.group?.groupId == groupId)
        .toList(growable: false);
    final center = _centroid(members);
    if (center == null) return;
    final targetZoom = math.min(
      definition.style.maxZoom,
      math.max(
        18.0,
        math.max(
              definition.style.labelMinZoom,
              definition.aggregateBelowZoom ?? definition.style.minZoom,
            ) +
            0.2,
      ),
    );
    onCameraRequest?.call(
      MapLayerCameraRequest(center: center, zoom: targetZoom, animate: true),
    );
  }

  MapLayerFeature? _findFeature(String layerId, String featureId) {
    final features = _features[layerId];
    if (features == null) return null;
    for (final feature in features) {
      if (feature.featureId == featureId) return feature;
    }
    return null;
  }

  void _select(String layerId, MapLayerFeature feature) {
    _selectedLayerId = layerId;
    _selected
      ..clear()
      ..[layerId] = feature;
    _notifyFeatureSelected(layerId, feature.featureId);
  }

  /// 通知 Provider 选中变化：只通知被选中的图层，取消选中时传 null。
  void _notifyFeatureSelected(String? layerId, String? featureId) {
    final provider = layerId == null ? null : _runtimes[layerId]?.provider;
    try {
      provider?.onFeatureSelected(featureId);
    } catch (error) {
      if (_disposed) return;
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "layer_feature_selected",
      );
    }
  }

  MapLayerEntry _entryFor(MapLayerDefinition definition) {
    final layerId = definition.layerId;
    return MapLayerEntry(
      definition: definition,
      enabled: _enabled[layerId] ?? definition.defaultVisible,
      transientVisible: _transient.contains(layerId),
      status: _status[layerId] ?? MapLayerLoadStatus.idle,
      features: _features[layerId] ?? const <MapLayerFeature>[],
      errorMessage: _errors[layerId],
      selectedFeature: _selected[layerId],
    );
  }

  Future<void> _syncActiveLayers() async {
    final campusId = _campusId;
    if (campusId == null) return;
    for (final definition in registry.forCampus(campusId)) {
      final entry = _entryFor(definition);
      if (entry.visible) {
        await _activate(definition.layerId);
      } else {
        await _deactivate(definition.layerId);
      }
      if (_disposed) return;
    }
    if (!_disposed) notifyListeners();
  }

  _LayerRuntime _runtimeFor(String layerId) =>
      _runtimes.putIfAbsent(layerId, _LayerRuntime.new);

  Future<void> _activate(String layerId) async {
    final definition = registry.byId(layerId);
    final campusId = _campusId;
    if (definition == null || campusId == null) return;
    if (!definition.supportsCampus(campusId)) return;
    final runtime = _runtimeFor(layerId);
    await _transition(runtime, () async {
      if (_disposed ||
          _campusId != campusId ||
          _boundCampusRevision != _campusRevision ||
          entryFor(layerId)?.visible != true) {
        return;
      }
      try {
        final provider = runtime.provider ??= definition.providerFactory();
        if (!runtime.activated) {
          runtime.activated = true;
          provider.activate(campusId);
          final stream = provider.watchFeatures(campusId);
          if (stream != null) {
            runtime.subscription = stream.listen(
              (update) => _applyUpdate(layerId, update),
              onError: (Object error) {
                if (_disposed) return;
                logUserFacingError(
                  UserErrorContext.map,
                  error,
                  operation: "layer_stream",
                );
              },
            );
          }
        }
      } catch (error) {
        if (runtime.activated) {
          runtime.activated = false;
          try {
            await runtime.provider?.deactivate();
          } catch (_) {
            // Preserve the activation error while releasing partial setup.
          }
        }
        if (_disposed) return;
        _status[layerId] = MapLayerLoadStatus.error;
        _errors[layerId] = userFacingError(UserErrorContext.map, error);
        logUserFacingError(
          UserErrorContext.map,
          error,
          operation: "layer_activate",
        );
        if (!_disposed) notifyListeners();
        return;
      }
    });
    if (_disposed ||
        _campusId != campusId ||
        _boundCampusRevision != _campusRevision ||
        entryFor(layerId)?.visible != true ||
        !runtime.activated) {
      return;
    }
    await _load(layerId);
  }

  Future<void> _deactivate(String layerId) async {
    final runtime = _runtimes[layerId];
    if (runtime == null) return;
    runtime.generation++;
    runtime.cancellation?.cancel();
    runtime.cancellation = null;
    // 停用后不再等待旧请求：新一次激活必须发起自己的加载，
    // 否则切换校区会复用上一个校区的在途请求。
    runtime.inFlight = null;
    await _transition(runtime, () async {
      // An earlier activation may have started loading while this transition
      // was queued; invalidate that request as well.
      runtime.generation++;
      runtime.cancellation?.cancel();
      runtime.cancellation = null;
      runtime.inFlight = null;
      if (_disposed) return;
      final subscription = runtime.subscription;
      runtime.subscription = null;
      await subscription?.cancel();
      if (runtime.activated) {
        runtime.activated = false;
        try {
          await runtime.provider?.deactivate();
        } catch (error) {
          if (_disposed) return;
          logUserFacingError(
            UserErrorContext.map,
            error,
            operation: "layer_deactivate",
          );
        }
      }
    });
  }

  Future<void> _transition(
    _LayerRuntime runtime,
    Future<void> Function() action,
  ) {
    final next = runtime.transition.then((_) => action());
    runtime.transition = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<void> _detachProviders() async {
    for (final layerId in _runtimes.keys.toList(growable: false)) {
      await _deactivate(layerId);
    }
  }

  Future<void> _load(String layerId, {bool force = false}) async {
    final runtime = _runtimeFor(layerId);
    final existing = runtime.inFlight;
    if (existing != null && !force) return existing;
    final future = _performLoad(layerId, runtime);
    runtime.inFlight = future;
    try {
      await future;
    } finally {
      if (identical(runtime.inFlight, future)) runtime.inFlight = null;
    }
  }

  Future<void> _performLoad(String layerId, _LayerRuntime runtime) async {
    final definition = registry.byId(layerId);
    final campusId = _campusId;
    if (definition == null || campusId == null) return;
    if (!definition.supportsCampus(campusId)) return;
    final provider = runtime.provider;
    if (provider == null) return;
    runtime.cancellation?.cancel();
    final cancellation = MapLayerCancellation();
    runtime.cancellation = cancellation;
    final generation = ++runtime.generation;
    _status[layerId] = MapLayerLoadStatus.loading;
    _errors[layerId] = null;
    notifyListeners();
    try {
      final features = await provider.loadFeatures(
        MapLayerLoadRequest(
          campusId: campusId,
          generation: generation,
          cancellation: cancellation,
          viewportBounds: _viewportBounds,
          zoom: _zoom,
        ),
      );
      if (_isStale(layerId, runtime, generation, cancellation, campusId)) {
        return;
      }
      _applySnapshot(layerId, features);
    } on MapLayerCancelledException {
      return;
    } catch (error) {
      if (_isStale(layerId, runtime, generation, cancellation, campusId)) {
        return;
      }
      logUserFacingError(UserErrorContext.map, error, operation: "layer_load");
      _status[layerId] = MapLayerLoadStatus.error;
      _errors[layerId] = userFacingError(UserErrorContext.map, error);
      notifyListeners();
    }
  }

  bool _isStale(
    String layerId,
    _LayerRuntime runtime,
    int generation,
    MapLayerCancellation cancellation,
    String campusId,
  ) {
    if (_disposed) return true;
    if (cancellation.isCancelled) return true;
    if (generation != runtime.generation) return true;
    if (_campusId != campusId) return true;
    final entry = entryFor(layerId);
    if (entry != null && !entry.visible) return true;
    return false;
  }

  void _applySnapshot(String layerId, List<MapLayerFeature> features) {
    _features[layerId] = List<MapLayerFeature>.unmodifiable(features);
    _status[layerId] =
        features.isEmpty ? MapLayerLoadStatus.empty : MapLayerLoadStatus.ready;
    _errors[layerId] = null;
    _pruneSelection(layerId, features);
    notifyListeners();
  }

  void _applyUpdate(String layerId, MapLayerFeatureUpdate update) {
    if (_disposed) return;
    final entry = entryFor(layerId);
    if (entry == null || !entry.visible) return;
    final Map<String, MapLayerFeature> byId = <String, MapLayerFeature>{};
    if (!update.replacesAll) {
      for (final feature in _features[layerId] ?? const <MapLayerFeature>[]) {
        byId[feature.featureId] = feature;
      }
    }
    for (final feature in update.features) {
      byId[feature.featureId] = feature;
    }
    for (final removed in update.removedFeatureIds) {
      byId.remove(removed);
    }
    _applySnapshot(layerId, byId.values.toList(growable: false));
  }

  void _pruneSelection(String layerId, List<MapLayerFeature> features) {
    final selected = _selected[layerId];
    if (selected == null) return;
    for (final feature in features) {
      if (feature.featureId == selected.featureId) {
        _selected[layerId] = feature;
        return;
      }
    }
    _selected.remove(layerId);
    if (_selectedLayerId == layerId) {
      _selectedLayerId = null;
      _notifyFeatureSelected(layerId, null);
    }
    onSelectionChanged?.call();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _campusRevision++;
    for (final entry in _runtimes.entries) {
      final runtime = entry.value;
      runtime.generation++;
      runtime.cancellation?.cancel();
      unawaited(runtime.subscription?.cancel());
      if (runtime.activated) {
        runtime.activated = false;
        try {
          unawaited(runtime.provider?.deactivate());
        } catch (_) {
          // 释放阶段的失败不再上报，避免销毁流程抛异常。
        }
      }
      runtime.provider?.dispose();
    }
    _runtimes.clear();
    super.dispose();
  }
}
