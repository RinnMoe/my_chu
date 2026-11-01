import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:mapbox_maps_flutter/mapbox_maps_flutter.dart";

import "../../campus_places/campus_places.dart";
import "../layers/layers.dart";

/// 通用 Mapbox 图层渲染适配器。
///
/// 只认识 [MapLayerRenderState]：不知道图层 ID 来自哪个业务，也不知道要素
/// 的业务含义。所有 Source/Layer ID 由本类按统一规则生成，避免业务之间
/// 的命名冲突；数据更新只改 GeoJSON Source，不重建地图、不重载底图、
/// 不重置相机。
class MapboxLayerRenderer {
  MapboxLayerRenderer({
    required MapboxMap? Function() controller,
    required bool Function() isStyleReady,
  }) : _controller = controller,
       _isStyleReady = isStyleReady;

  final MapboxMap? Function() _controller;
  final bool Function() _isStyleReady;

  /// 已布局到样式里的图层顺序（升序优先级，后加入者在上）。
  final List<String> _appliedOrder = <String>[];
  final Map<String, String> _lastSourceData = <String, String>{};
  final Map<String, Set<MapLayerGeometryType>> _appliedGeometry =
      <String, Set<MapLayerGeometryType>>{};
  List<MapLayerRenderState> _states = const <MapLayerRenderState>[];
  bool _suspended = false;
  Future<void>? _syncFlight;
  int _syncRevision = 0;
  int _styleGeneration = 0;

  static const String _idPrefix = "mychu-map-layer-";
  static const String _sourceSuffix = "-source";
  static const String _pointLayerSuffix = "-point";
  static const String _labelLayerSuffix = "-label";
  static const String _aggregateLabelLayerSuffix = "-aggregate-label";
  static const String _aggregateBadgeLayerSuffix = "-aggregate-badge";
  static const String _aggregatePointLayerSuffix = "-aggregate-point";
  static const String _emphasizedPointLayerSuffix = "-point-emphasized";
  static const String _lineLayerSuffix = "-line";
  static const String _fillLayerSuffix = "-fill";

  /// 业务图层使用的 Source ID 前缀，便于诊断与清理。
  static String sourceIdFor(String layerId) =>
      "$_idPrefix$layerId$_sourceSuffix";

  static String pointLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_pointLayerSuffix";

  /// 聚合圆点单独一层。
  ///
  /// 单点圆点的半径要随缩放插值，而 Mapbox 只接受**顶层**的 `zoom` 表达式 ——
  /// 塞进 `case` 分支里会让 addLayer 抛错，整层都建不出来。所以按 aggregate
  /// 拆成两层：单点层用纯 zoom 插值，聚合层用固定的 `case`。
  static String aggregatePointLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_aggregatePointLayerSuffix";

  /// 选中（强调）态的单点单独一层。
  ///
  /// 半径要随缩放插值，而 Mapbox 只接受顶层的 `zoom` 表达式，不能写成
  /// `case(emphasized, 大, 小)`；于是按 emphasized 再拆一层，两层各自用
  /// 顶层的 zoom 插值，强调态自然比普通态大一圈。
  static String emphasizedPointLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_emphasizedPointLayerSuffix";

  static String labelLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_labelLayerSuffix";

  static String aggregateLabelLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_aggregateLabelLayerSuffix";

  /// 聚合圆点下方的分组名（「充电桩-北门」）。
  ///
  /// 它和逐点桩号是两种标签：共用一个 SymbolLayer 时只能靠 filter 二选一，
  /// 打开逐点标签就会把分组名过滤掉。
  static String aggregateBadgeLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_aggregateBadgeLayerSuffix";

  static String lineLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_lineLayerSuffix";

  static String fillLayerIdFor(String layerId) =>
      "$_idPrefix$layerId$_fillLayerSuffix";

  /// 当前已应用图层（按绘制顺序，后加入者在上）。
  List<String> get appliedLayerIds => List<String>.unmodifiable(_appliedOrder);

  /// 样式重载后调用：清空本地缓存，下一次 [sync] 会重新建立 Source/Layer。
  void reset() {
    _styleGeneration++;
    _syncRevision++;
    _appliedOrder.clear();
    _lastSourceData.clear();
    _appliedGeometry.clear();
  }

  /// 应用一份完整的展示状态。
  ///
  /// 实现为幂等同步：缺失的 Source/Layer 会补齐，多余的业务 Layer 会移除，
  /// 数据变化只更新 Source 数据；顺序变化时才重排本框架自己的 Layer。
  Future<void> sync(List<MapLayerRenderState> states) {
    _states = states;
    _syncRevision++;
    return _syncFlight ??= _drainSync();
  }

  Future<void> _drainSync() async {
    try {
      while (true) {
        final revision = _syncRevision;
        final generation = _styleGeneration;
        try {
          await _syncNow(_states);
        } catch (_) {
          if (generation == _styleGeneration) rethrow;
        }
        if (generation != _styleGeneration) {
          // An operation on the previous style can finish after reset().
          _appliedOrder.clear();
          _lastSourceData.clear();
          _appliedGeometry.clear();
        }
        if (revision == _syncRevision) return;
      }
    } finally {
      _syncFlight = null;
    }
  }

  Future<void> _syncNow(List<MapLayerRenderState> states) async {
    final controller = _controller();
    if (controller == null || !_isStyleReady()) return;
    final style = controller.style;
    final desired = <String>[
      for (final state in states)
        if (state.features.isNotEmpty) state.layerId,
    ];
    final desiredSources = desired.toSet();

    // 移除不再可见的业务图层与 Source。
    for (final layerId in List<String>.of(_appliedOrder)) {
      if (desiredSources.contains(layerId)) continue;
      await _removeLayer(style, layerId);
    }
    for (final sourceId in List<String>.of(_lastSourceData.keys)) {
      final layerId = _layerIdOfSource(sourceId);
      if (layerId == null || desiredSources.contains(layerId)) continue;
      _lastSourceData.remove(sourceId);
      if (await style.styleSourceExists(sourceId)) {
        if (!_isStyleReady()) return;
        await style.removeStyleSource(sourceId);
      }
    }

    // 顺序不一致时整体重排：业务图层数量很少，重排代价远低于保持错序。
    final needsNewGeometry = states.any((state) {
      final applied = _appliedGeometry[state.layerId];
      if (applied == null) return false;
      return state.features.any(
        (feature) => !applied.contains(feature.geometry.type),
      );
    });
    if (!_listEquals(_appliedOrder, desired) || needsNewGeometry) {
      for (final layerId in List<String>.of(_appliedOrder)) {
        await _removeLayer(style, layerId);
      }
      for (final state in states) {
        if (state.features.isEmpty) continue;
        final applied = await _applyLayer(style, state);
        if (!applied || !_isStyleReady()) return;
      }
    } else {
      for (final state in states) {
        if (state.features.isEmpty) continue;
        final applied = await _ensureLayer(style, state);
        if (!applied || !_isStyleReady()) return;
      }
    }

    if (!_isStyleReady()) return;
    await _applySuspension(style);
  }

  /// 参与命中的图层，按优先级从高到低；同一层级内保持渲染顺序。
  @visibleForTesting
  static List<MapLayerRenderState> orderedInteractive(
    List<MapLayerRenderState> states,
  ) {
    final ordered = states
        .where((state) => state.interactive && state.features.isNotEmpty)
        .toList(growable: false);
    // List.sort 不保证稳定；先按渲染顺序编号再排序，保证同优先级可复现。
    final indexed = <(int, MapLayerRenderState)>[
      for (var index = 0; index < ordered.length; index++)
        (index, ordered[index]),
    ]..sort((a, b) {
      final byPriority = b.$2.priority.compareTo(a.$2.priority);
      return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
    });
    return <MapLayerRenderState>[for (final entry in indexed) entry.$2];
  }

  /// 命中查询。按优先级从高到低返回第一个命中要素。
  Future<MapLayerHit?> hitTest(MapLayerHitQuery query) async {
    final controller = _controller();
    if (controller == null || !_isStyleReady()) return null;
    // 高优先级图层先判定，与“当前可见业务图层中的命中要素”优先级一致。
    final ordered = orderedInteractive(_states);
    if (ordered.isEmpty) return null;
    final layerIds = <String?>[];
    for (final state in ordered) {
      for (final layerId in layerIdsFor(state)) {
        if (await controller.style.styleLayerExists(layerId)) {
          layerIds.add(layerId);
        }
      }
    }
    if (layerIds.isEmpty) return null;
    if (!_isStyleReady()) return null;
    final rendered = await controller.queryRenderedFeatures(
      RenderedQueryGeometry.fromScreenCoordinate(
        ScreenCoordinate(x: query.x, y: query.y),
      ),
      RenderedQueryOptions(layerIds: layerIds),
    );
    if (!_isStyleReady()) return null;
    final hits = <String, String>{};
    for (final entry in rendered) {
      final feature = entry?.queriedFeature.feature;
      final properties = feature?["properties"];
      if (properties is! Map) continue;
      final featureId = properties["feature_id"];
      final layerId = properties["layer_id"];
      if (featureId is String && layerId is String) {
        hits.putIfAbsent(layerId, () => featureId);
      }
    }
    for (final state in ordered) {
      final featureId = hits[state.layerId];
      if (featureId != null) {
        return MapLayerHit(layerId: state.layerId, featureId: featureId);
      }
    }
    return null;
  }

  /// 进入室内地图时挂起室外业务图层，退出时恢复；两者不共存于同一视野。
  Future<void> setSuspended(bool suspended) async {
    if (_suspended == suspended) return;
    _suspended = suspended;
    final controller = _controller();
    if (controller == null || !_isStyleReady()) return;
    await _applySuspension(controller.style);
  }

  bool get isSuspended => _suspended;

  Future<void> _applySuspension(StyleManager style) async {
    final visibility = _suspended ? "none" : "visible";
    for (final layerId in _appliedOrder) {
      for (final id in <String>[
        emphasizedPointLayerIdFor(layerId),
        pointLayerIdFor(layerId),
        aggregatePointLayerIdFor(layerId),
        labelLayerIdFor(layerId),
        aggregateBadgeLayerIdFor(layerId),
        aggregateLabelLayerIdFor(layerId),
        lineLayerIdFor(layerId),
        fillLayerIdFor(layerId),
      ]) {
        if (!await style.styleLayerExists(id)) continue;
        if (!_isStyleReady()) return;
        await style.setStyleLayerProperty(id, "visibility", visibility);
      }
    }
  }

  /// 渲染器为某图层生成的 Mapbox Layer ID（按命中优先级：文本层在圆形层之上）。
  @visibleForTesting
  static List<String> layerIdsFor(MapLayerRenderState state) {
    final geometryTypes = <MapLayerGeometryType>{
      for (final feature in state.features) feature.geometry.type,
    };
    return <String>[
      if (geometryTypes.contains(MapLayerGeometryType.point)) ...<String>[
        // 文本层在圆点层之上，命中优先级也按这个顺序。
        if (state.features.any((feature) => feature.isAggregate))
          aggregateLabelLayerIdFor(state.layerId),
        if (state.features.any((feature) => feature.isAggregate))
          aggregateBadgeLayerIdFor(state.layerId),
        if (state.features.any((feature) => feature.isAggregate))
          aggregatePointLayerIdFor(state.layerId),
        labelLayerIdFor(state.layerId),
        emphasizedPointLayerIdFor(state.layerId),
        pointLayerIdFor(state.layerId),
      ],
      if (geometryTypes.contains(MapLayerGeometryType.lineString))
        lineLayerIdFor(state.layerId),
      if (geometryTypes.contains(MapLayerGeometryType.polygon))
        fillLayerIdFor(state.layerId),
    ];
  }

  Future<bool> _ensureLayer(
    StyleManager style,
    MapLayerRenderState state,
  ) async {
    final sourceId = sourceIdFor(state.layerId);
    if (!await style.styleSourceExists(sourceId)) {
      if (!_isStyleReady()) return false;
      await style.addSource(GeoJsonSource(id: sourceId, data: _emptyData()));
      _lastSourceData.remove(sourceId);
    }
    if (!_isStyleReady()) return false;
    // A later snapshot may introduce a geometry type absent at first render.
    return _addLayersFor(style, state);
  }

  Future<bool> _applyLayer(
    StyleManager style,
    MapLayerRenderState state,
  ) async {
    final sourceId = sourceIdFor(state.layerId);
    if (!await style.styleSourceExists(sourceId)) {
      if (!_isStyleReady()) return false;
      await style.addSource(GeoJsonSource(id: sourceId, data: _emptyData()));
      _lastSourceData.remove(sourceId);
    }
    if (!_isStyleReady()) return false;
    return _addLayersFor(style, state);
  }

  Future<bool> _addLayersFor(
    StyleManager style,
    MapLayerRenderState state,
  ) async {
    final sourceId = sourceIdFor(state.layerId);
    final layerStyle = state.style;
    final data = buildFeatureCollectionJson(state);
    if (!_isStyleReady()) return false;
    if (_lastSourceData[sourceId] != data &&
        await style.styleSourceExists(sourceId)) {
      await style.setStyleSourceProperty(sourceId, "data", data);
      _lastSourceData[sourceId] = data;
    }
    if (!_isStyleReady()) return false;
    final geometryTypes = <MapLayerGeometryType>{
      for (final feature in state.features) feature.geometry.type,
    };
    if (geometryTypes.contains(MapLayerGeometryType.polygon)) {
      final fillId = fillLayerIdFor(state.layerId);
      if (!await style.styleLayerExists(fillId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          FillLayer(
            id: fillId,
            sourceId: sourceId,
            slot: "top",
            minZoom: layerStyle.minZoom,
            maxZoom: layerStyle.maxZoom,
            fillColorExpression: _colorExpression(),
            fillOpacity: 0.25,
            fillOutlineColorExpression: _colorExpression(),
          ),
        );
      }
    }
    if (geometryTypes.contains(MapLayerGeometryType.lineString)) {
      final lineId = lineLayerIdFor(state.layerId);
      if (!await style.styleLayerExists(lineId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          LineLayer(
            id: lineId,
            sourceId: sourceId,
            slot: "top",
            minZoom: layerStyle.minZoom,
            maxZoom: layerStyle.maxZoom,
            lineColorExpression: _colorExpression(),
            lineWidth: 3,
          ),
        );
      }
    }
    if (geometryTypes.contains(MapLayerGeometryType.point)) {
      final pointId = pointLayerIdFor(state.layerId);
      if (!await style.styleLayerExists(pointId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          CircleLayer(
            id: pointId,
            sourceId: sourceId,
            slot: "top",
            filter: <Object>[
              "all",
              <Object>["==", <Object>["get", "aggregate"], false],
              <Object>["!=", <Object>["get", "emphasized"], true],
            ],
            minZoom: layerStyle.minZoom,
            maxZoom: layerStyle.maxZoom,
            circleColorExpression: _colorExpression(),
            // 单点层：半径是顶层 zoom 插值，不能再包 case。
            circleRadiusExpression: _radiusByZoom(layerStyle),
            circleStrokeWidth: layerStyle.strokeWidth,
            circleStrokeColor: layerStyle.strokeColor,
            circleOpacity: 0.92,
          ),
        );
      }
      final emphasizedPointId = emphasizedPointLayerIdFor(state.layerId);
      if (!await style.styleLayerExists(emphasizedPointId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          CircleLayer(
            id: emphasizedPointId,
            sourceId: sourceId,
            slot: "top",
            filter: <Object>[
              "all",
              <Object>["==", <Object>["get", "aggregate"], false],
              <Object>["==", <Object>["get", "emphasized"], true],
            ],
            minZoom: layerStyle.minZoom,
            maxZoom: layerStyle.maxZoom,
            circleColorExpression: _colorExpression(),
            circleRadiusExpression: _radiusByZoom(
              layerStyle,
              radius: layerStyle.emphasizedCircleRadius,
            ),
            circleStrokeWidth: layerStyle.strokeWidth,
            circleStrokeColor: layerStyle.strokeColor,
            circleOpacity: 0.92,
          ),
        );
      }
      final aggregatePointId = aggregatePointLayerIdFor(state.layerId);
      if (!await style.styleLayerExists(aggregatePointId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          CircleLayer(
            id: aggregatePointId,
            sourceId: sourceId,
            slot: "top",
            filter: <Object>["==", <Object>["get", "aggregate"], true],
            minZoom: layerStyle.minZoom,
            maxZoom: layerStyle.maxZoom,
            circleColorExpression: _colorExpression(),
            circleRadiusExpression: <Object>[
              "case",
              <Object>["==", <Object>["get", "emphasized"], true],
              layerStyle.emphasizedAggregateCircleRadius ??
                  layerStyle.emphasizedCircleRadius,
              layerStyle.aggregateCircleRadius ?? layerStyle.circleRadius,
            ],
            circleStrokeWidth: layerStyle.strokeWidth,
            circleStrokeColor: layerStyle.strokeColor,
            circleOpacity: 0.92,
          ),
        );
      }
      final labelId = labelLayerIdFor(state.layerId);
      if (layerStyle.showLabels && !await style.styleLayerExists(labelId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          _badgeLayer(
            id: labelId,
            sourceId: sourceId,
            layerStyle: layerStyle,
            aggregate: false,
            minZoom: layerStyle.labelMinZoom,
          ),
        );
      }
      // 聚合圆点下方的分组名。与逐点桩号分开一层：同一个 SymbolLayer 只能靠
      // filter 二选一，合在一起时打开逐点标签就会把分组名一起过滤掉。
      final aggregateBadgeId = aggregateBadgeLayerIdFor(state.layerId);
      if (layerStyle.showAggregateCount &&
          !await style.styleLayerExists(aggregateBadgeId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          _badgeLayer(
            id: aggregateBadgeId,
            sourceId: sourceId,
            layerStyle: layerStyle,
            aggregate: true,
            minZoom: layerStyle.minZoom,
          ),
        );
      }
      final aggregateLabelId = aggregateLabelLayerIdFor(state.layerId);
      if (!await style.styleLayerExists(aggregateLabelId)) {
        if (!_isStyleReady()) return false;
        await style.addLayer(
          SymbolLayer(
            id: aggregateLabelId,
            sourceId: sourceId,
            slot: "top",
            filter: <Object>[
              "==",
              <Object>["get", "aggregate"],
              true,
            ],
            minZoom: layerStyle.minZoom,
            maxZoom: layerStyle.maxZoom,
            textFieldExpression:
                layerStyle.showAggregateCount
                    ? <Object>[
                      "case",
                      ["has", "available_count"],
                      [
                        "to-string",
                        ["get", "available_count"],
                      ],
                      "",
                    ]
                    : <Object>["get", "badge"],
            textSize: layerStyle.showAggregateCount ? 14 : 10,
            textFont:
                layerStyle.showAggregateCount
                    ? ["DIN Pro Bold", "Arial Unicode MS Bold"]
                    : ["Open Sans Regular", "Arial Unicode MS Regular"],
            textColor: 0xFFFFFFFF,
            textHaloColor: 0xFF1B1B1B,
            textHaloWidth: layerStyle.showAggregateCount ? 0 : 0.6,
            textAllowOverlap: true,
            textIgnorePlacement: true,
          ),
        );
      }
    }
    if (!_appliedOrder.contains(state.layerId)) {
      _appliedOrder.add(state.layerId);
    }
    _appliedGeometry
        .putIfAbsent(state.layerId, () => <MapLayerGeometryType>{})
        .addAll(geometryTypes);
    return true;
  }

  /// 点位短文本的标签层。
  ///
  /// 两种标签各有一套视觉：
  /// * 逐点桩号 —— 白字、**无描边**，压在圆点正中，和聚合圆点里的可用数同款；
  /// * 聚合分组名 —— 黑字白描边，浮在聚合圆点下方，因为它是压在底图上而不是色块上。
  static SymbolLayer _badgeLayer({
    required String id,
    required String sourceId,
    required MapLayerStyle layerStyle,
    required bool aggregate,
    required double minZoom,
  }) {
    if (!aggregate) {
      return SymbolLayer(
        id: id,
        sourceId: sourceId,
        slot: "top",
        filter: <Object>["==", <Object>["get", "aggregate"], false],
        minZoom: minZoom,
        maxZoom: layerStyle.maxZoom,
        textFieldExpression: <Object>["get", "badge"],
        // 与聚合圆点里的可用数同款：白色、不描边。字号收到 10，最长的
        // 五字符桩号（TY-01）也装得进固定半径的圆点里。
        textSize: 10,
        textColor: 0xFFFFFFFF,
        textHaloWidth: 0,
        textAnchor: TextAnchor.CENTER,
        textOffset: <double>[0, 0],
        textAllowOverlap: false,
      );
    }
    // 这一层只在 showAggregateCount 为真时创建，所以直接写死「大号黑字浮在圆点下方」。
    return SymbolLayer(
      id: id,
      sourceId: sourceId,
      slot: "top",
      filter: <Object>["==", <Object>["get", "aggregate"], true],
      minZoom: minZoom,
      maxZoom: layerStyle.maxZoom,
      textFieldExpression: <Object>["get", "badge"],
      textSize: 13,
      textColor: 0xFF000000,
      textHaloColor: 0xFFFFFFFF,
      textHaloWidth: 2,
      textAnchor: TextAnchor.TOP,
      textOffset: <double>[
        0,
        ((layerStyle.emphasizedAggregateCircleRadius ??
                    layerStyle.emphasizedCircleRadius) +
                5) /
            13,
      ],
      textAllowOverlap: false,
    );
  }

  Future<void> _removeLayer(StyleManager style, String layerId) async {
    for (final id in <String>[
      aggregateLabelLayerIdFor(layerId),
      aggregateBadgeLayerIdFor(layerId),
      aggregatePointLayerIdFor(layerId),
      emphasizedPointLayerIdFor(layerId),
      labelLayerIdFor(layerId),
      pointLayerIdFor(layerId),
      lineLayerIdFor(layerId),
      fillLayerIdFor(layerId),
    ]) {
      if (!_isStyleReady()) return;
      if (await style.styleLayerExists(id)) {
        if (!_isStyleReady()) return;
        await style.removeStyleLayer(id);
      }
    }
    _appliedOrder.remove(layerId);
    _appliedGeometry.remove(layerId);
  }

  String? _layerIdOfSource(String sourceId) {
    if (!sourceId.startsWith(_idPrefix) || !sourceId.endsWith(_sourceSuffix)) {
      return null;
    }
    return sourceId.substring(
      _idPrefix.length,
      sourceId.length - _sourceSuffix.length,
    );
  }

  /// 把展示状态转换为 Mapbox GeoJSON Source 数据。
  ///
  /// 属性包含 feature_id / layer_id / badge / color / emphasized，全部由框架
  /// 写入，因此业务字段名不会影响绘制。
  @visibleForTesting
  static String buildFeatureCollectionJson(MapLayerRenderState state) {
    final features = <Map<String, Object?>>[];
    for (final feature in state.features) {
      final geometry = _geometryJson(feature.geometry);
      if (geometry == null) continue;
      features.add(<String, Object?>{
        "type": "Feature",
        "id": feature.featureId,
        "geometry": geometry,
        "properties": <String, Object?>{
          "feature_id": feature.featureId,
          "layer_id": state.layerId,
          "badge": feature.badgeText ?? "",
          if (feature.availableCount != null)
            "available_count": feature.availableCount,
          "color": _hex(feature.color),
          "emphasized": feature.emphasized,
          "aggregate": feature.isAggregate,
        },
      });
    }
    return jsonEncode(<String, Object?>{
      "type": "FeatureCollection",
      "features": features,
    });
  }

  static Map<String, Object?>? _geometryJson(MapLayerGeometry geometry) {
    final valid = geometry.validCoordinates;
    if (valid.isEmpty) return null;
    List<double> position(CampusCoordinate coordinate) => <double>[
      coordinate.longitude,
      coordinate.latitude,
    ];
    switch (geometry.type) {
      case MapLayerGeometryType.point:
        return <String, Object?>{
          "type": "Point",
          "coordinates": position(valid.first),
        };
      case MapLayerGeometryType.lineString:
        if (valid.length < 2) return null;
        return <String, Object?>{
          "type": "LineString",
          "coordinates": <List<double>>[for (final c in valid) position(c)],
        };
      case MapLayerGeometryType.polygon:
        if (valid.length < 3) return null;
        final ring = <List<double>>[for (final c in valid) position(c)];
        final first = ring.first;
        final last = ring.last;
        if (first[0] != last[0] || first[1] != last[1]) ring.add(first);
        return <String, Object?>{
          "type": "Polygon",
          "coordinates": <List<List<double>>>[ring],
        };
    }
  }

  static List<Object> _colorExpression() => <Object>["get", "color"];

  /// 带文本的点位半径随缩放变化。
  ///
  /// 半径如果固定成屏幕像素，缩小时点不会变小，几十个点会糊成一整片；放大后
  /// 又显得过小。这里让它在「开始画单个点」到「文本出现后一格」之间从 1/3 长到
  /// 满尺寸：缩小时收成小点、放大后长到能装下文本。不带文本的图层仍用固定半径。
  static List<Object> _radiusByZoom(MapLayerStyle style, {double? radius}) {
    final base = radius ?? style.circleRadius;
    if (!style.showLabels) return <Object>[base];
    // 带文本时半径随缩放变化：缩小时收成小点避免糊成一片，放大后长到能装下文本。
    final high = style.labelMinZoom;
    return <Object>[
      "interpolate",
      <Object>["linear"],
      <Object>["zoom"],
      high - 1.8,
      base * 0.31,
      high + 1.2,
      base,
    ];
  }

  static String _hex(int argb) {
    final rgb = argb & 0xFFFFFF;
    return "#${rgb.toRadixString(16).padLeft(6, "0")}";
  }

  static String _emptyData() => jsonEncode(<String, Object?>{
    "type": "FeatureCollection",
    "features": <Object>[],
  });

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
