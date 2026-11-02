import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../services/privacy_agreement_service.dart';
import 'charging_pile_api_client.dart';
import 'charging_pile_catalog_document.dart';
import 'charging_pile_catalog_service.dart';
import 'charging_pile_snapshot_client.dart';
import 'charging_pile_models.dart';
import 'charging_pile_status_cache.dart';

/// One process-wide source of truth shared by the native page, the campus map
/// layer and future clients.
///
/// No polling. Consumers [acquire] a lease, refresh the scope they display and
/// release it when hidden; the last release stops queued work and retries.
///
/// All scopes ([refreshAll], [refreshArea], [refreshDevice], [refreshIfStale])
/// share one request budget and one in-flight table:
/// - a device is queried at most once at a time, later callers await the same
///   future;
/// - at most six requests run at once across every consumer;
/// - a device is not re-queried inside [deviceCooldown], even for an explicit
///   manual refresh; `force` only skips the batch dedupe window, so
///   pull-to-refresh hammering cannot turn into a request burst.
///
/// Results publish per device as they arrive; a transaction that is cancelled
/// before it completes rolls its published devices back to the previous
/// snapshot, so an interrupted refresh never leaves half-updated data.
class ChargingPileRepository extends ChangeNotifier {
  factory ChargingPileRepository.shared() =>
      _shared ??= ChargingPileRepository();
  static ChargingPileRepository? _shared;

  ChargingPileRepository({
    ChargingPileApi? api,
    ChargingPileCatalogDocument? catalog,
    ChargingPileCatalogService? catalogs,
    ChargingPileStatusCache? cache,
    ChargingPileSnapshotClient? snapshotClient,
    DateTime Function()? now,
    Future<bool> Function()? consent,
    this.retryDelay = const Duration(milliseconds: 800),
    this.deviceCooldown = const Duration(seconds: 5),
    this.liveWindow = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now,
       _consent = consent ?? PrivacyAgreementService.isAccepted {
    _api = api ?? ChargingPileApiClient();
    if (catalog != null) {
      _applyCatalog(catalog);
    } else {
      _catalogs = catalogs ?? ChargingPileCatalogService.shared();
      _catalogs!.addListener(_catalogChanged);
      final loaded = _catalogs!.document;
      if (loaded != null) _applyCatalog(loaded);
    }
    _cache = cache ?? ChargingPileStatusCache(catalog: _catalog);
    _snapshotClient = snapshotClient ?? ChargingPileSnapshotClient();
    PrivacyAgreementService.revision.addListener(_privacyChanged);
  }

  late final ChargingPileApi _api;
  late final ChargingPileStatusCache _cache;
  late final ChargingPileSnapshotClient _snapshotClient;
  ChargingPileCatalogService? _catalogs;
  List<ChargingPileDevice> _catalog = const <ChargingPileDevice>[];
  List<ChargingPileArea> _areas = const <ChargingPileArea>[];
  Map<String, ChargingPileDevice> _devicesById =
      const <String, ChargingPileDevice>{};
  final DateTime Function() _now;
  final Future<bool> Function() _consent;

  /// 当前生效的目录快照；随远端更新而变化。
  ChargingPileCatalogDocument? _document;

  /// 目录是否已有可用快照。未就绪时页面显示加载态而不是空列表。
  bool get hasCatalog => _catalog.isNotEmpty;

  /// Delay before the single retry of a transient network failure.
  final Duration retryDelay;

  /// Minimum interval between two queries of the same device while it already
  /// has a confirmed snapshot. Manual refresh bypasses the batch dedupe window
  /// but never this cooldown.
  final Duration deviceCooldown;

  /// 默认自动刷新间隔，不影响已有数据的可用性。
  final Duration liveWindow;

  final _states = <String, ChargingPileDeviceState>{};
  final _inFlight = <String, Future<List<ChargingPileSlot>>>{};
  final _lastDeviceAttempt = <String, DateTime>{};
  final _batches = <_RefreshBatch>{};
  Future<void>? _pageFlight;
  ChargingPileCancellation _runtime = ChargingPileCancellation();
  bool _disposed = false;
  int _consumers = 0;
  int _activeRequests = 0;
  Completer<void> _slotReleased = Completer<void>();
  DateTime? _lastPageAttempt;
  DateTime? _updatedAt;
  bool _interrupted = false;
  int _networkFailures = 0;
  ChargingPileFailure? _failure;
  ChargingPileFailure? _lastDegradation;
  DateTime? _pausedUntil;
  ChargingPileFailure? _pauseReason;
  Future<void>? _restoring;
  bool _restoreDone = false;
  int _privacyGeneration = 0;
  Future<void>? _cacheWrites;
  bool _cacheDirty = false;

  static const _maxConcurrent = 6;
  static const _pageDedupWindow = Duration(seconds: 60);
  static const _networkFailureLimit = 5;
  static const _pauseDuration = Duration(minutes: 10);

  /// A 429 stops the current scan, but the source only asks for "try again in
  /// a moment"; holding the whole feature for ten minutes would outlast the
  /// budget window it is waiting for.
  static const _rateLimitPause = Duration(seconds: 60);

  List<ChargingPileDevice> loadCatalog() => _catalog;

  /// 分区列表由站点目录给出（含 `key`/`statsKey`/`anchor`），不再来自编译期 enum。
  List<ChargingPileArea> loadAreas() => _areas;

  /// 确保目录已就绪：返回当前快照，必要时等待目录服务首次载入。
  Future<ChargingPileCatalogDocument> ensureCatalog() async {
    final existing = _document;
    if (existing != null) return existing;
    final service = _catalogs;
    if (service == null) {
      throw StateError('目录尚未就绪');
    }
    final document = await service.ensureLoaded();
    if (_disposed) return document;
    if (!identical(_document, document)) {
      _applyCatalog(document);
      _cache.updateCatalog(_catalog);
      _emit();
    }
    return document;
  }

  /// 目录快照更新（站点新增桩位/分区、或首次从远端载入）。
  ///
  /// 设备 id 跨版本稳定，所以已确认的状态按 id 保留；目录里消失的设备丢弃，
  /// 免得被删掉的桩继续出现在列表里。
  void _applyCatalog(ChargingPileCatalogDocument document) {
    _document = document;
    _catalog = List<ChargingPileDevice>.unmodifiable(document.devices);
    _areas = List<ChargingPileArea>.unmodifiable(document.areas);
    _devicesById = {for (final device in _catalog) device.id: device};
    _states.removeWhere((id, _) => !_devicesById.containsKey(id));
  }

  void _catalogChanged() {
    final document = _catalogs?.document;
    if (_disposed || document == null || identical(document, _document)) return;
    _applyCatalog(document);
    _cache.updateCatalog(_catalog);
    // 新目录里可能有上次没见过的设备，需要重新把缓存里能对上的状态读回来。
    _restoreDone = false;
    _refreshUpdatedAt();
    _emit();
    unawaited(ensureCacheRestored());
  }

  /// Devices belonging to one area, identified by [ChargingPileArea.location].
  List<ChargingPileDevice> devicesInArea(String areaId) =>
      List.unmodifiable(_catalog.where((device) => device.location == areaId));

  ChargingPileDevice? deviceFor(String deviceId) => _devicesById[deviceId];

  Map<String, ChargingPileDeviceState> getState() => Map.unmodifiable(_states);
  ChargingPileDeviceState stateFor(String id) =>
      _states[id] ?? const ChargingPileDeviceState();
  DateTime get now => _now();
  bool get isRefreshing => _batches.isNotEmpty;
  DateTime? get updatedAt => _updatedAt;

  /// Time left before another whole-catalog refresh is allowed, or null when
  /// one may start now. Mirrors the source's 60-second manual refresh gate.
  Duration? get refreshCooldown {
    final last = _lastPageAttempt;
    if (last == null || _states.isEmpty) return null;
    final elapsed = _now().difference(last);
    if (elapsed >= _pageDedupWindow) return null;
    return _pageDedupWindow - elapsed;
  }
  int get completed => _batches.fold(0, (sum, batch) => sum + batch.completed);
  int get total => _batches.fold(0, (sum, batch) => sum + batch.total);
  ChargingPileFailure? get failure => _failure;
  DateTime? get pausedUntil => _pausedUntil;
  bool get isPaused => _pausedUntil?.isAfter(_now()) == true;

  /// Consumes the one-shot "this scan was degraded" notice, if any. The source
  /// shows a transient toast for the same situation instead of a banner.
  bool consumeDegradation() {
    final degraded = _lastDegradation != null;
    _lastDegradation = null;
    return degraded;
  }

  /// True when no usable snapshot is on screen: either nothing has been loaded
  /// yet, or the last transaction was cancelled before it completed.
  bool get needsRefresh => _interrupted || _states.isEmpty;

  /// 有成功数据就可展示，不因时间推移失效。
  ChargingPileStatusFreshness freshnessFor(String deviceId) =>
      _states[deviceId]?.status == null
          ? ChargingPileStatusFreshness.unavailable
          : ChargingPileStatusFreshness.live;

  /// 仅决定是否需要刷新，不改变已有数据的展示。
  bool isStale(String deviceId) {
    final status = _states[deviceId]?.status;
    return status == null || _now().difference(status.fetchedAt) >= liveWindow;
  }

  /// 面向用户的可用性：使用最近一次成功数据。
  ///
  /// 筛选、汇总与卡片高亮都必须用它，而不是直接读缓存里的 `freeSlots`。
  ChargingPileAvailability availabilityFor(String deviceId) =>
      chargingPileAvailabilityOf(stateFor(deviceId), freshnessFor(deviceId));

  /// 最近一次成功数据中的空闲插座数；无数据返回 0。
  int confirmedFreeSlots(String deviceId) {
    if (availabilityFor(deviceId) != ChargingPileAvailability.free) return 0;
    return stateFor(deviceId).status?.freeSlots ?? 0;
  }

  /// A page/layer must release when hidden or disposed. The last release stops
  /// queued work/retries and fences in-flight responses.
  VoidCallback acquire() {
    if (_disposed) throw StateError('Repository disposed');
    _consumers++;
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      _consumers--;
      if (_consumers == 0) _cancelWork();
    };
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _cancelWork() {
    _runtime.cancel();
    _runtime = ChargingPileCancellation();
    _pageFlight = null;
    if (_batches.isNotEmpty) {
      // No transaction committed, so the next activation resumes it.
      _lastPageAttempt = null;
      _interrupted = true;
    }
    _batches.clear();
    _inFlight.clear();
    _lastDeviceAttempt.clear();
    _emit();
  }

  void _privacyChanged() {
    // Invalidate immediately, before the async preferences read can complete.
    _privacyGeneration++;
    _cancelWork();
    // A revoked (or re-accepted) agreement must not pull the old snapshot back.
    _restoreDone = true;
    _states.clear();
    _updatedAt = null;
    _failure = ChargingPileFailure.consentRequired;
    _emit();
  }

  /// Starts an explicit retry from a clean slate.
  ///
  /// The source stopped handing out a shared credential on 2026-10-27, so there
  /// is nothing left to sync here. The method keeps its name and signature
  /// because the page's retry action still means "clear the last failure and
  /// let every device be attempted again", and consent is still re-checked
  /// before any request leaves the device.
  Future<void> syncCredential({bool force = false}) async {
    final runtime = _runtime;
    if (runtime.isCancelled || _disposed) return;
    if (!await _consentAllows()) return;
    if (runtime.isCancelled || _disposed) return;
    _failure = null;
    _lastPageAttempt = null;
    _lastDeviceAttempt.clear();
    _emit();
  }

  /// 用站点全校快照铺满一次，再用 `/api/pile` 补齐快照没覆盖的设备。
  ///
  /// 快照来自站点定时采样（白天分钟级、深夜小时级），比 `/api/pile` 旧，
  /// 所以它负责「首屏/回到前台时别空着」，用户主动刷新仍走 [refreshAll]。
  /// 单个分区没取到就保留该区上一次的结果；分区内某台没采到则记为未知 ——
  /// 站点自己的口径是「没采到 = 未知」，不是「占用」。
  ///
  /// ⚠️ 源站的全校快照目前**只覆盖渭水校区**（校本部的 57 台不在
  /// `/api/snap` 里，`area=beiyuan` 会直接回 `snapshot_unavailable`）。
  /// 所以快照之后要把没覆盖到的设备交给 `/api/pile`，否则它们会永远停在
  /// 「未知」——这也让本方法在源站把校本部并入快照后自动退化成一个请求。
  Future<void> refreshSnapshot({bool force = false}) async {
    if (_disposed) return;
    final runtime = _runtime;
    if (runtime.isCancelled) return;
    if (!await _consentAllows()) return;
    if (runtime.isCancelled || _disposed) return;
    await ensureCacheRestored();
    if (runtime.isCancelled || _disposed) return;
    final batch = _RefreshBatch(total: _catalog.length);
    _batches.add(batch);
    _failure = null;
    _emit();
    try {
      final snapshot = await _snapshotClient.fetch(force: force);
      if (_disposed || runtime.isCancelled) return;
      final covered = _applySnapshot(snapshot);
      batch.completed = batch.total;
      _networkFailures = 0;
      _refreshUpdatedAt();
      _emit();
      await _persistCache();
      // 快照没覆盖到的设备（源站的采样范围之外）改用逐台查询补齐。
      final uncovered = <ChargingPileDevice>[
        for (final device in _catalog)
          if (!covered.contains(device.id)) device,
      ];
      if (uncovered.isNotEmpty && !_disposed && !runtime.isCancelled) {
        await _refreshScope(uncovered, force: force, fullCatalog: false);
      }
    } on ChargingPileException catch (error) {
      if (error.failure == ChargingPileFailure.cancelled) return;
      _networkFailures = error.failure == ChargingPileFailure.network
          ? _networkFailures + 1
          : 0;
      _failure = error.failure;
      _emit();
    } catch (_) {
      _failure = ChargingPileFailure.malformed;
      _emit();
    } finally {
      if (_batches.remove(batch)) _emit();
    }
  }

  /// 把快照写进状态，返回**本次真正拿到数据的设备 id**。
  ///
  /// 调用方据此判断哪些设备还需要走 `/api/pile` 补齐。
  Set<String> _applySnapshot(ChargingPileSnapshot snapshot) {
    final covered = <String>{};
    final areaByKey = {for (final area in _areas) area.key: area};
    for (final areaSnapshot in snapshot.areas) {
      // 整个区这次没取到：保留上一次的结果，别把它当成「全部未知」。
      if (!areaSnapshot.hasData) continue;
      final area = areaByKey[areaSnapshot.key];
      // 目录比站点旧时可能不认识这个区；跳过即可，下一次目录刷新会补上。
      if (area == null) continue;
      final sampledAt = areaSnapshot.sampledAt ?? _now();
      for (final device in devicesInArea(area.areaId)) {
        final slots = areaSnapshot.devices[device.id];
        _states[device.id] = slots == null
            ? const ChargingPileDeviceState()
            : ChargingPileDeviceState(
                status: ChargingPileDeviceStatus(
                  device: device,
                  slots: slots,
                  fetchedAt: sampledAt,
                ),
              );
        if (slots != null) covered.add(device.id);
      }
    }
    return covered;
  }

  /// Refresh the entire catalog as one transaction. Consumers share the same
  /// in-flight batch; filters never create their own device requests.
  /// [force] skips the short-lived batch dedupe window for an explicit gesture.
  Future<void> refreshAll({bool force = false}) async {
    if (_disposed) return;
    final pending = _pageFlight;
    if (pending != null) return pending;
    final flight = _refreshScope(
      List<ChargingPileDevice>.of(_catalog),
      force: force,
      fullCatalog: true,
    );
    _pageFlight = flight;
    try {
      await flight;
    } finally {
      if (identical(_pageFlight, flight)) _pageFlight = null;
    }
  }

  /// Refresh only the devices of one area. [areaId] is
  /// [ChargingPileArea.location]; other areas keep their state and their own
  /// query time.
  Future<void> refreshArea(String areaId, {bool force = false}) async {
    if (_disposed) return;
    final devices = devicesInArea(areaId);
    if (devices.isEmpty) return;
    await _refreshScope(devices, force: force, fullCatalog: false);
  }

  /// Refresh exactly one device, for map focus and detail views.
  Future<void> refreshDevice(String deviceId, {bool force = false}) async {
    if (_disposed) return;
    final device = _devicesById[deviceId];
    if (device == null) return;
    await _refreshScope([device], force: force, fullCatalog: false);
  }

  /// Refresh only devices without data or needing an update:
  /// unknown, failed or older than [maxAge] (defaults to [liveWindow]). Used on
  /// foreground resume so a quick app switch does not stampede the platform.
  /// 刷新过期设备。[campusId] 非空时只刷该校区，供按校区渲染的地图图层使用 ——
  /// 在渭水校区看图不该顺带把校本部的 57 台也查一遍。
  Future<void> refreshIfStale({Duration? maxAge, String? campusId}) async {
    if (_disposed) return;
    final limit = maxAge ?? liveWindow;
    final current = _now();
    final devices = _catalog
        .where((device) {
          if (campusId != null && device.campusId != campusId) return false;
          final status = _states[device.id]?.status;
          if (status == null) return true;
          return current.difference(status.fetchedAt) >= limit;
        })
        .toList(growable: false);
    if (devices.isEmpty) return;
    await _refreshScope(devices, force: true, fullCatalog: false);
  }

  /// Restores the persisted snapshot once, before the first network refresh.
  /// Restored states keep their original observation time and never overwrite a
  /// state this process already produced.
  Future<void> ensureCacheRestored() async {
    if (_disposed || _restoreDone) return;
    final pending = _restoring;
    if (pending != null) return pending;
    final flight = _restoreCache();
    _restoring = flight;
    try {
      await flight;
    } finally {
      if (identical(_restoring, flight)) _restoring = null;
    }
  }

  Future<void> _restoreCache() async {
    final generation = _privacyGeneration;
    final restored = await _cache.load();
    if (_disposed || generation != _privacyGeneration) return;
    _restoreDone = true;
    if (restored.isEmpty) return;
    var changed = false;
    for (final entry in restored.entries) {
      if (_states.containsKey(entry.key)) continue;
      _states[entry.key] = entry.value;
      changed = true;
    }
    if (!changed) return;
    _refreshUpdatedAt();
    _emit();
  }

  Future<bool> _consentAllows() async {
    try {
      if (!await _consent()) {
        _failure = ChargingPileFailure.consentRequired;
        _emit();
        return false;
      }
      return true;
    } catch (_) {
      _failure = ChargingPileFailure.storage;
      _emit();
      return false;
    }
  }

  Future<void> _refreshScope(
    List<ChargingPileDevice> devices, {
    required bool force,
    required bool fullCatalog,
  }) async {
    if (_disposed || devices.isEmpty) return;
    final runtime = _runtime;
    if (runtime.isCancelled) return;
    if (!await _consentAllows()) return;
    if (runtime.isCancelled || _disposed) return;
    await ensureCacheRestored();
    if (runtime.isCancelled || _disposed) return;
    // A pause holds automatic work only; an explicit gesture is the user's
    // intent and still goes through, matching the source banner's promise.
    final paused = isPaused;
    if (paused && !force) {
      _failure = _pauseReason;
      _emit();
      return;
    }
    // Mirrors the source's manual refresh gate: the proxy budgets upstream
    // calls per minute, so even an explicit gesture must respect this window.
    // Area and single-device scopes rely on the per-device cooldown and the
    // in-flight table instead.
    if (fullCatalog &&
        _lastPageAttempt != null &&
        _states.isNotEmpty &&
        _now().difference(_lastPageAttempt!) < _pageDedupWindow) {
      return;
    }
    final eligible = devices
        .where((device) => !_deviceCooldownActive(device.id))
        .toList(growable: false);
    if (eligible.isEmpty) return;
    if (fullCatalog) _lastPageAttempt = _now();
    final batch = _RefreshBatch(total: eligible.length);
    _batches.add(batch);
    _failure = null;
    _emit();
    final before = <String, ChargingPileDeviceState?>{};
    final written = <String, ChargingPileDeviceState>{};
    ChargingPileFailure? stopReason;
    var index = 0;
    // A pause is repository-wide: every running scope stops, not only the one
    // that hit the rate limit. An explicit `force` already passed the gate
    // above and must not be stopped by the pause it is retrying.
    bool stopped() =>
        runtime.isCancelled ||
        _disposed ||
        stopReason != null ||
        (paused && !force);

    void publish(ChargingPileDevice device, ChargingPileDeviceState state) {
      before.putIfAbsent(device.id, () => _states[device.id]);
      written[device.id] = state;
      _states[device.id] = state;
    }

    Future<void> worker() async {
      while (!stopped()) {
        final position = index++;
        if (position >= eligible.length) return;
        final device = eligible[position];
        final outcome = await _queryDevice(
          device,
          runtime,
          stopped,
          fresh: force,
        );
        if (runtime.isCancelled || _disposed) return;
        switch (outcome) {
          case _QuerySkipped(:final degraded):
            // The proxy degraded this batch to "keep what you already have".
            // Nothing is published, so the previous snapshot stays on screen;
            // the page only surfaces a one-shot notice after the scan.
            if (degraded) _lastDegradation = ChargingPileFailure.throttled;
            break;
          case _QuerySuccess(:final slots):
            _networkFailures = 0;
            publish(
              device,
              ChargingPileDeviceState(
                status: ChargingPileDeviceStatus(
                  device: device,
                  slots: slots,
                  fetchedAt: _now(),
                ),
              ),
            );
          case _QueryFailure(:final failure):
            if (failure == ChargingPileFailure.cancelled) return;
            _networkFailures =
                failure == ChargingPileFailure.network
                    ? _networkFailures + 1
                    : 0;
            // 与站点口径一致：查询失败就清空插座数据、显示「未知」。
            // 站点在失败记录里写 `ports: []` 并把卡片画成未知状态，这里同样不
            // 保留上一次的绿点——否则「整片超时」会被误读成「刚才还有空位」。
            publish(
              device,
              ChargingPileDeviceState(failure: failure),
            );
            if (failure == ChargingPileFailure.rateLimited) {
              stopReason ??= failure;
              _pauseReason = failure;
              _pausedUntil = _now().add(_rateLimitPause);
              _lastDegradation = failure;
            } else if (_networkFailures >= _networkFailureLimit) {
              stopReason ??= failure;
              _pauseReason = failure;
              _pausedUntil = _now().add(_pauseDuration);
            } else if (failure == ChargingPileFailure.credentialUnavailable ||
                failure == ChargingPileFailure.storage ||
                failure == ChargingPileFailure.consentRequired) {
              stopReason ??= failure;
            }
        }
        if (runtime.isCancelled || _disposed) return;
        batch.completed++;
        _emit(); // Incremental: a listener can render this device immediately.
      }
    }

    try {
      await Future.wait(
        List.generate(
          math.min(_maxConcurrent, eligible.length),
          (_) => worker(),
        ),
      );
      if (_disposed) return;
      if (runtime.isCancelled) {
        // The transaction never committed; keep the previous usable snapshot.
        _rollback(before, written);
        _interrupted = true;
        _emit();
        return;
      }
      // Only failures a person must act on become a banner: a rejected shared
      // credential, a local storage/consent problem, or a network-wide pause.
      // Device-level errors stay on their own card, matching the source, which
      // reserves its banner for the credential failure and the "5 piles in a
      // row did not answer" case.
      _failure = switch (stopReason) {
        ChargingPileFailure.credentialUnavailable ||
        ChargingPileFailure.storage ||
        ChargingPileFailure.consentRequired => stopReason,
        ChargingPileFailure.network when isPaused => stopReason,
        _ => null,
      };
      _refreshUpdatedAt();
      _interrupted = false;
      // One write per committed transaction, never one per device.
      await _persistCache();
    } finally {
      _batches.remove(batch);
      _emit();
    }
  }

  void _rollback(
    Map<String, ChargingPileDeviceState?> before,
    Map<String, ChargingPileDeviceState> written,
  ) {
    for (final entry in written.entries) {
      // Another transaction may have published a newer state meanwhile.
      if (!identical(_states[entry.key], entry.value)) continue;
      final previous = before[entry.key];
      if (previous == null) {
        _states.remove(entry.key);
      } else {
        _states[entry.key] = previous;
      }
    }
    _refreshUpdatedAt();
  }

  bool _deviceCooldownActive(String deviceId) {
    // Every device has a minimum re-query interval, failed ones included: a
    // burst of explicit refreshes must not multiply into a request burst.
    final last = _lastDeviceAttempt[deviceId];
    return last != null && _now().difference(last) < deviceCooldown;
  }

  Future<_QueryOutcome> _queryDevice(
    ChargingPileDevice device,
    ChargingPileCancellation runtime,
    bool Function() stopped, {
    required bool fresh,
  }) async {
    final deviceId = device.id;
    final joined = _inFlight[deviceId];
    if (joined != null) return _settle(joined);
    if (_deviceCooldownActive(deviceId)) return const _QuerySkipped();
    final flight = _requestSlots(device, runtime, stopped, fresh: fresh);
    _inFlight[deviceId] = flight;
    try {
      return await _settle(flight);
    } finally {
      if (identical(_inFlight[deviceId], flight)) _inFlight.remove(deviceId);
      if (!runtime.isCancelled && !_disposed) {
        _lastDeviceAttempt[deviceId] = _now();
      }
    }
  }

  Future<_QueryOutcome> _settle(Future<List<ChargingPileSlot>> flight) async {
    try {
      return _QuerySuccess(await flight);
    } on ChargingPileException catch (error) {
      // `throttled` is the source's documented degradation: this batch was not
      // refreshed, so keep the previous snapshot and carry on. Only a real 429
      // pauses the whole scan.
      if (error.failure == ChargingPileFailure.throttled) {
        return const _QuerySkipped(degraded: true);
      }
      return _QueryFailure(error.failure);
    } catch (_) {
      return const _QueryFailure(ChargingPileFailure.platform);
    }
  }

  Future<List<ChargingPileSlot>> _requestSlots(
    ChargingPileDevice device,
    ChargingPileCancellation runtime,
    bool Function() stopped, {
    required bool fresh,
  }) async {
    // Cancelled generations can still be draining when a new transaction
    // starts. Keep the same global request budget across generations without
    // polling timers.
    while (_activeRequests >= _maxConcurrent) {
      await Future.any([_slotReleased.future, runtime.whenCancelled]);
      runtime.check();
      if (stopped()) {
        throw const ChargingPileException(ChargingPileFailure.cancelled);
      }
    }
    runtime.check();
    if (stopped()) {
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
    _activeRequests++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        runtime.check();
        if (stopped()) {
          throw const ChargingPileException(ChargingPileFailure.cancelled);
        }
        try {
          return await _api.queryDevice(device, runtime, fresh: fresh);
        } on ChargingPileException catch (e) {
          if (e.failure != ChargingPileFailure.network || attempt == 1) rethrow;
          await Future.any([
            Future<void>.delayed(retryDelay),
            runtime.whenCancelled,
          ]);
        }
      }
      throw const ChargingPileException(ChargingPileFailure.platform);
    } finally {
      _activeRequests--;
      final released = _slotReleased;
      _slotReleased = Completer<void>();
      released.complete();
    }
  }

  void _refreshUpdatedAt() {
    DateTime? latest;
    for (final state in _states.values) {
      final fetchedAt = state.status?.fetchedAt;
      if (fetchedAt == null) continue;
      if (latest == null || fetchedAt.isAfter(latest)) latest = fetchedAt;
    }
    _updatedAt = latest;
  }

  /// Coalesces cache writes: a batch that publishes many devices still writes
  /// the store once, and a write requested while one is running is folded into
  /// the next pass.
  Future<void> _persistCache() {
    _cacheDirty = true;
    return _cacheWrites ??= _drainCacheWrites();
  }

  Future<void> _drainCacheWrites() async {
    try {
      while (_cacheDirty) {
        _cacheDirty = false;
        await _cache.save(Map<String, ChargingPileDeviceState>.of(_states));
      }
    } catch (_) {
      // Persistence is best effort and must never break a refresh.
    } finally {
      _cacheWrites = null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    PrivacyAgreementService.revision.removeListener(_privacyChanged);
    _catalogs?.removeListener(_catalogChanged);
    _cancelWork();
    _api.close();
    _snapshotClient.close();
    if (identical(_shared, this)) _shared = null;
    super.dispose();
  }
}

/// Progress of one refresh transaction; aggregated for the page progress bar.
class _RefreshBatch {
  _RefreshBatch({required this.total});
  final int total;
  int completed = 0;
}

sealed class _QueryOutcome {
  const _QueryOutcome();
}

/// The device was skipped: either it was queried within [deviceCooldown], or
/// the proxy degraded the batch and asked us to keep the previous snapshot.
class _QuerySkipped extends _QueryOutcome {
  const _QuerySkipped({this.degraded = false});
  final bool degraded;
}

class _QuerySuccess extends _QueryOutcome {
  const _QuerySuccess(this.slots);
  final List<ChargingPileSlot> slots;
}

class _QueryFailure extends _QueryOutcome {
  const _QueryFailure(this.failure);
  final ChargingPileFailure failure;
}
