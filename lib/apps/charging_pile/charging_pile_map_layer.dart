/// 共享充电桩的地图图层接入。
///
/// 本文件是「业务 App → 地图公开 Capability」的唯一接触面：
/// - 通过 [MapLayerDefinition] 注册 `charging.piles` 图层；
/// - 通过 [ChargingPileLayerProvider] 把 Repository 的实时状态映射成通用要素；
/// - 通过 [MapLayerInteraction] 提供业务详情卡与跳回应用的动作。
///
/// 地图侧不认识 [ChargingPileDevice]、JWT 或充电平台接口。
library;

import "dart:async";

import "package:flutter/material.dart";

import "../../capabilities/campus_map/layers/layers.dart";
import "../../capabilities/campus_places/campus_places.dart";
import "../../services/user_error_message.dart";
import "../app_target_router.dart";
import "charging_pile_geo.dart";
import "charging_pile_map_link.dart";
import "charging_pile_models.dart";
import "charging_pile_page.dart";
import "charging_pile_service.dart";
import "charging_pile_widgets.dart";

const String _weishuiCampusId = chargingPileMapCampusId;

/// 把 Repository 状态映射为地图要素。
///
/// 状态语义（任务书 7.4）：
/// - 绿色：已确认有空闲插座（live 且 freeSlots > 0）；
/// - 红色：已确认没有空闲插座（live 且全部已占用）；
/// - 灰色：未查询、查询失败、状态过期或无法确认。
///
/// 查询失败与“状态未知”一律为灰色，绝不显示成“已占满”。
MapLayerFeatureStatus chargingPileFeatureStatus({
  required ChargingPileDeviceState state,
  required ChargingPileStatusFreshness freshness,
}) => switch (chargingPileAvailabilityOf(state, freshness)) {
  ChargingPileAvailability.free => MapLayerFeatureStatus.positive,
  ChargingPileAvailability.occupied => MapLayerFeatureStatus.negative,
  ChargingPileAvailability.unknown => MapLayerFeatureStatus.unknown,
};

/// 业务状态摘要，供地图详情卡与标记副标题复用同一份数据。
String chargingPileStatusSummary({
  required ChargingPileDeviceState state,
  required ChargingPileStatusFreshness freshness,
  required DateTime now,
}) {
  final status = state.status;
  if (status == null) {
    final failure = state.failure;
    if (failure == ChargingPileFailure.consentRequired) return "请先同意用户协议";
    return failure == null ? "尚未查询" : "状态未知（${failure.message}）";
  }
  final observed = "更新于 ${chargingPileTime(status.fetchedAt, now)}";
  switch (freshness) {
    case ChargingPileStatusFreshness.live:
      if (status.freeSlots > 0) return "空闲 ${status.freeSlots} · $observed";
      if (status.occupiedSlots > 0 && status.otherSlots == 0) {
        return "无空闲插座 · $observed";
      }
      return "状态未知 · $observed";
    case ChargingPileStatusFreshness.stale:
    case ChargingPileStatusFreshness.expired:
      return "状态已过期 · $observed";
    case ChargingPileStatusFreshness.unavailable:
      return "状态未知 · $observed";
  }
}

/// 充电桩图层的 Provider。
///
/// 只消费共享的 [ChargingPileRepository]：与充电桩 App 共用同一份设备状态，
/// 不会为地图再查一次第三方平台。图层关闭时释放消费者引用，但不影响仍打开的 App。
class ChargingPileLayerProvider implements MapLayerProvider {
  ChargingPileLayerProvider({
    ChargingPileRepository? repository,
    Future<ChargingPileLocationCatalog> Function()? locations,
    DateTime Function()? now,
  }) : _repository = repository ?? ChargingPileRepository.shared(),
       _locations = locations ?? ChargingPileLocationCatalog.shared,
       _now = now ?? DateTime.now;

  final ChargingPileRepository _repository;
  final Future<ChargingPileLocationCatalog> Function() _locations;
  final DateTime Function() _now;

  final StreamController<MapLayerFeatureUpdate> _updates =
      StreamController<MapLayerFeatureUpdate>.broadcast();

  ChargingPileLocationCatalog? _catalog;
  VoidCallback? _release;
  bool _active = false;
  bool _disposed = false;
  String? _campusId;
  int _activationGeneration = 0;
  Timer? _expiryTimer;

  @override
  Future<List<MapLayerFeature>> loadFeatures(
    MapLayerLoadRequest request,
  ) async {
    if (request.campusId != _weishuiCampusId) return const <MapLayerFeature>[];
    final catalog = _catalog ?? await _locations();
    request.cancellation.throwIfCancelled();
    _catalog = catalog;
    if (catalog.campusId != request.campusId) return const <MapLayerFeature>[];
    await _repository.ensureCacheRestored();
    request.cancellation.throwIfCancelled();
    _scheduleExpiry();
    return _buildFeatures(catalog);
  }

  @override
  Stream<MapLayerFeatureUpdate>? watchFeatures(String campusId) =>
      _updates.stream;

  @override
  void activate(String campusId) {
    _campusId = campusId;
    _active = true;
    _release ??= _repository.acquire();
    _repository.addListener(_onRepositoryChanged);
    unawaited(_warmUp(++_activationGeneration));
  }

  @override
  Future<void> deactivate() async {
    _active = false;
    _activationGeneration++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _repository.removeListener(_onRepositoryChanged);
    _release?.call();
    _release = null;
  }

  @override
  Future<void> refresh() async {
    // 手动刷新走 Repository 的按需刷新：跳过整批去重窗口，但仍受单设备冷却约束，
    // 不会因为反复点按形成请求洪峰。
    try {
      await _repository.refreshIfStale(maxAge: Duration.zero);
    } on ChargingPileException catch (error) {
      if (_disposed) return;
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "charging_layer_refresh",
      );
    }
  }

  @override
  void onFeatureSelected(String? featureId) {
    if (featureId == null || !_active || _disposed) return;
    final catalog = _catalog;
    if (catalog == null || catalog.siteFor(featureId) == null) return;
    if (!_repository.isStale(featureId)) return;
    unawaited(_refreshOne(featureId));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _activationGeneration++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _repository.removeListener(_onRepositoryChanged);
    _release?.call();
    _release = null;
    if (!_updates.isClosed) unawaited(_updates.close());
  }

  /// 每次激活时恢复快照并刷新过期状态，包括被关闭图层中断的查询。
  Future<void> _warmUp(int generation) async {
    try {
      await _repository.ensureCacheRestored();
      if (!_active || _disposed || generation != _activationGeneration) return;
      _emitSnapshot();
      await _repository.refreshIfStale();
    } catch (error) {
      if (_disposed) return;
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "charging_layer_warmup",
      );
    }
  }

  Future<void> _refreshOne(String deviceId) async {
    try {
      await _repository.refreshDevice(deviceId);
    } catch (error) {
      if (_disposed) return;
      logUserFacingError(
        UserErrorContext.map,
        error,
        operation: "charging_layer_refresh_device",
      );
    }
  }

  void _onRepositoryChanged() {
    if (!_active || _disposed || _campusId == null) return;
    _emitSnapshot();
  }

  void _emitSnapshot() {
    final catalog = _catalog;
    if (catalog == null || _updates.isClosed) return;
    _updates.add(MapLayerFeatureUpdate.snapshot(_buildFeatures(catalog)));
    _scheduleExpiry();
  }

  /// 在最早的实时结果过期时重绘，避免长期显示过时的可用状态。
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final catalog = _catalog;
    if (!_active || _disposed || catalog == null) return;
    final now = _repository.now;
    DateTime? next;
    for (final location in catalog.sites) {
      final status = _repository.stateFor(location.deviceId).status;
      if (status == null) continue;
      final expiry = status.fetchedAt.add(_repository.liveWindow);
      if (!expiry.isAfter(now)) continue;
      if (next == null || expiry.isBefore(next)) next = expiry;
    }
    if (next == null) return;
    _expiryTimer = Timer(next.difference(now), () {
      _expiryTimer = null;
      if (_active && !_disposed) _emitSnapshot();
    });
  }

  List<MapLayerFeature> _buildFeatures(ChargingPileLocationCatalog catalog) {
    if (catalog.campusId != _weishuiCampusId) return const <MapLayerFeature>[];
    final now = _now();
    final features = <MapLayerFeature>[];
    for (final location in catalog.sites) {
      final device = _repository.deviceFor(location.deviceId);
      // 没有可靠位置的设备不编造坐标：直接不进入地图数据。
      if (device == null) continue;
      final state = _repository.stateFor(location.deviceId);
      final freshness = _repository.freshnessFor(location.deviceId);
      final area = device.area;
      features.add(
        MapLayerFeature(
          featureId: location.deviceId,
          geometry: MapLayerGeometry.point(
            CampusCoordinate(
              latitude: location.latitude,
              longitude: location.longitude,
            ),
          ),
          label: device.name,
          subtitle: chargingPileStatusSummary(
            state: state,
            freshness: freshness,
            now: now,
          ),
          status: chargingPileFeatureStatus(state: state, freshness: freshness),
          group: MapLayerFeatureGroup(
            groupId: area.location.isEmpty ? "unknown" : area.location,
            label: area.label,
          ),
          payload: device,
        ),
      );
    }
    return features;
  }
}

/// 业务详情卡：与地图共用同一份 Repository 状态。
///
/// 动作按钮放在底部，顶部右侧留给地图框架的关闭按钮。
Widget _buildChargingPileDetail(
  BuildContext context,
  MapLayerFeatureSelection selection,
  ChargingPileRepository repository,
  DateTime Function() now,
) {
  final device = selection.payload;
  if (device is! ChargingPileDevice) return const SizedBox.shrink();
  final state = repository.stateFor(device.id);
  final freshness = repository.freshnessFor(device.id);
  final theme = Theme.of(context);
  final status = state.status;
  final openOwnerApp = selection.definition.interaction.openOwnerApp;
  return Material(
    elevation: 8,
    color: theme.colorScheme.surfaceContainerLowest,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${device.code} · ${device.area.label}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chargingPileStatusSummary(
                    state: state,
                    freshness: freshness,
                    now: now(),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: 10),
            ChargingPilePorts(slots: status.slots, compact: true),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "刷新该设备",
                  onPressed:
                      () => unawaited(repository.refreshDevice(device.id)),
                  icon: const Icon(Icons.refresh),
                ),
                if (openOwnerApp != null)
                  IconButton(
                    tooltip: "在${selection.definition.name}中打开",
                    onPressed: () async {
                      final opened = await openOwnerApp(context, selection);
                      if (opened || !context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("暂时无法打开该应用")),
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 充电桩图层定义。注册与业务页面生命周期无关：地图面板无需打开过充电桩 App
/// 即可发现该图层。
MapLayerDefinition chargingPileMapLayerDefinition({
  ChargingPileRepository? repository,
  Future<ChargingPileLocationCatalog> Function()? locations,
  DateTime Function()? now,
}) {
  final resolvedRepository = repository ?? ChargingPileRepository.shared();
  final resolvedNow = now ?? DateTime.now;
  return MapLayerDefinition(
    layerId: chargingPileLayerId,
    ownerAppId: chargingPileMapOwnerAppId,
    name: "共享充电桩",
    icon: Icons.ev_station_outlined,
    campusIds: const <String>{_weishuiCampusId},
    defaultVisible: false,
    priority: 10,
    aggregateBelowZoom: 16.2,
    style: const MapLayerStyle(
      positiveColor: 0xFF1D9E75,
      negativeColor: 0xFFE24B4A,
      unknownColor: 0xFF9AA0A6,
      neutralColor: 0xFF1A73E8,
      showLabels: false,
      labelMinZoom: 17,
    ),
    interaction: MapLayerInteraction(
      tapSelectable: true,
      showsDetailCard: true,
      detailBuilder:
          (context, selection) => _buildChargingPileDetail(
            context,
            selection,
            resolvedRepository,
            resolvedNow,
          ),
      openOwnerApp: (context, selection) {
        final device = selection.payload;
        if (device is! ChargingPileDevice) return Future<bool>.value(false);
        return openTargetId(
          context,
          chargingPileMapOwnerAppId,
          appPageBuilder: (_) => ChargingPilePage(initialDeviceId: device.id),
        );
      },
    ),
    providerFactory:
        () => ChargingPileLayerProvider(
          repository: resolvedRepository,
          locations: locations,
          now: resolvedNow,
        ),
  );
}
