import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../services/privacy_agreement_service.dart';
import 'charging_pile_api_client.dart';
import 'charging_pile_catalog.dart';
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
    List<ChargingPileDevice>? catalog,
    ChargingPileStatusCache? cache,
    DateTime Function()? now,
    Future<bool> Function()? consent,
    this.retryDelay = const Duration(milliseconds: 800),
    this.deviceCooldown = const Duration(seconds: 5),
    this.liveWindow = const Duration(minutes: 2),
  }) : _catalog = List.unmodifiable(catalog ?? kChargingPileDevices),
       _now = now ?? DateTime.now,
       _consent = consent ?? PrivacyAgreementService.isAccepted {
    _api = api ?? ChargingPileApiClient();
    _cache = cache ?? ChargingPileStatusCache(catalog: _catalog);
    _devicesById = {for (final device in _catalog) device.id: device};
    PrivacyAgreementService.revision.addListener(_privacyChanged);
  }

  late final ChargingPileApi _api;
  late final ChargingPileStatusCache _cache;
  late final Map<String, ChargingPileDevice> _devicesById;
  final List<ChargingPileDevice> _catalog;
  final DateTime Function() _now;
  final Future<bool> Function() _consent;

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
  List<ChargingPileArea> loadAreas() =>
      List.unmodifiable(_catalog.map((d) => d.area).toSet());

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
  Future<void> refreshIfStale({Duration? maxAge}) async {
    if (_disposed) return;
    final limit = maxAge ?? liveWindow;
    final current = _now();
    final devices = _catalog
        .where((device) {
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
        final outcome = await _queryDevice(device.id, runtime, stopped);
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
            // 请求失败保留最后一次成功数据；从未成功时仍为无数据。
            publish(
              device,
              ChargingPileDeviceState(
                status: _states[device.id]?.status,
                failure: failure,
              ),
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
    String deviceId,
    ChargingPileCancellation runtime,
    bool Function() stopped,
  ) async {
    final joined = _inFlight[deviceId];
    if (joined != null) return _settle(joined);
    if (_deviceCooldownActive(deviceId)) return const _QuerySkipped();
    final flight = _requestSlots(deviceId, runtime, stopped);
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
    String id,
    ChargingPileCancellation runtime,
    bool Function() stopped,
  ) async {
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
          return await _api.queryDevice(id, runtime);
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
    _cancelWork();
    _api.close();
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
