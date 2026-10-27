import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/charging_credential_service.dart';
import '../services/privacy_agreement_service.dart';
import 'charging_pile_api_client.dart';
import 'charging_pile_catalog.dart';
import 'charging_pile_models.dart';

/// One process-wide source of truth, shared by native pages and future clients.
/// No polling: consumers explicitly request their visible area/devices.
class ChargingPileRepository extends ChangeNotifier {
  factory ChargingPileRepository.shared() =>
      _shared ??= ChargingPileRepository();
  static ChargingPileRepository? _shared;

  ChargingPileRepository({
    ChargingPileApi? api,
    ChargingCredentialService? credentials,
    List<ChargingPileDevice> catalog = kChargingPileDevices,
    DateTime Function()? now,
    Future<bool> Function()? consent,
    this.retryDelay = const Duration(milliseconds: 800),
  }) : _credentials =
           credentials ?? (api == null ? ChargingCredentialService() : null),
       _catalog = List.unmodifiable(catalog),
       _now = now ?? DateTime.now,
       _consent = consent ?? PrivacyAgreementService.isAccepted {
    _api = api ?? ChargingPileApiClient(_credentials!);
    PrivacyAgreementService.revision.addListener(_privacyChanged);
  }

  final ChargingCredentialService? _credentials;
  late final ChargingPileApi _api;
  final List<ChargingPileDevice> _catalog;
  final DateTime Function() _now;
  final Future<bool> Function() _consent;
  final Duration retryDelay;
  final _cache = <String, ChargingPileCachedDevice>{};
  final _inFlight = <String, Future<void>>{};
  ChargingPileCancellation _runtime = ChargingPileCancellation();
  final _batches = <ChargingPileCancellation>{};
  bool _disposed = false;
  int _consumers = 0;
  int _active = 0;
  int _completed = 0;
  int _total = 0;
  int _networkFailures = 0;
  ChargingPileFailure? _failure;
  DateTime? _pausedUntil;
  ChargingPileFailure? _pauseReason;

  List<ChargingPileDevice> loadCatalog() => _catalog;
  Map<String, ChargingPileCachedDevice> getCachedState() =>
      Map.unmodifiable(_cache);
  ChargingPileCachedDevice stateFor(String id) =>
      _cache[id] ?? const ChargingPileCachedDevice();
  DateTime get now => _now();
  bool get isRefreshing => _batches.isNotEmpty;
  bool isDeviceRefreshing(String id) => _inFlight.containsKey(id);
  int get completed => _completed;
  int get total => _total;
  ChargingPileFailure? get failure => _failure;
  DateTime? get pausedUntil => _pausedUntil;

  /// A page/layer must release when hidden or disposed. The last release stops
  /// queued work/retries and fences in-flight responses; cached data survives.
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
    for (final batch in _batches) {
      batch.cancel();
    }
    _batches.clear();
    _inFlight.clear();
    _credentials?.cancelPending();
    _emit();
  }

  void _privacyChanged() {
    // Invalidate immediately, before the async preferences read can complete.
    _cancelWork();
    _cache.clear();
    _failure = ChargingPileFailure.consentRequired;
    _emit();
  }

  Future<void> syncCredential() async {
    final runtime = _runtime;
    try {
      await _credentials?.syncCredential();
      if (runtime.isCancelled || _disposed) return;
      _failure = null;
      for (final id in _cache.keys.toList()) {
        final entry = _cache[id]!;
        if (entry.failure == ChargingPileFailure.credentialUnavailable ||
            entry.failure == ChargingPileFailure.credentialSync) {
          _cache[id] = ChargingPileCachedDevice(status: entry.status);
        }
      }
    } on ChargingPileException catch (e) {
      if (runtime.isCancelled || _disposed) return;
      _failure = e.failure;
    }
    _emit();
  }

  Future<void> refreshArea(
    ChargingPileArea area, {
    ChargingPileCancellation? cancellation,
  }) => _refresh(
    _catalog.where((device) => device.area == area).toList(),
    cancellation,
  );

  /// Explicit caller intent only; not called on page creation or a timer.
  Future<void> refreshAll({ChargingPileCancellation? cancellation}) =>
      _refresh(_catalog, cancellation);

  Future<void> refreshDevice(
    String id, {
    ChargingPileCancellation? cancellation,
  }) => _refresh([
    _catalog.singleWhere((device) => device.id == id),
  ], cancellation);

  Future<void> _refresh(
    List<ChargingPileDevice> devices,
    ChargingPileCancellation? cancellation,
  ) async {
    if (_disposed) return;
    final runtime = _runtime;
    bool accepted;
    try {
      accepted = await _consent();
    } catch (_) {
      _failure = ChargingPileFailure.storage;
      _emit();
      return;
    }
    if (!accepted) {
      _failure = ChargingPileFailure.consentRequired;
      _emit();
      return;
    }
    if (runtime.isCancelled || _disposed || cancellation?.isCancelled == true)
      return;
    if (_pausedUntil?.isAfter(_now()) == true) {
      _failure = _pauseReason;
      _emit();
      return;
    }
    final batch = cancellation ?? ChargingPileCancellation();
    if (_batches.isEmpty) {
      _completed = 0;
      _total = 0;
      _failure = null;
      _networkFailures = 0;
    }
    _total += devices.length;
    _batches.add(batch);
    _emit();
    var index = 0;
    var stopped = false;
    Future<void> worker() async {
      while (!stopped &&
          !batch.isCancelled &&
          !runtime.isCancelled &&
          !_disposed) {
        if (_pausedUntil?.isAfter(_now()) == true) return;
        final current = index++;
        if (current >= devices.length) return;
        final device = devices[current];
        await _refreshOne(device, runtime);
        if (batch.isCancelled || runtime.isCancelled || _disposed) return;
        final error = stateFor(device.id).failure;
        if (error != null) _failure = error;
        if (error == ChargingPileFailure.credentialUnavailable ||
            error == ChargingPileFailure.credentialSync ||
            error == ChargingPileFailure.storage ||
            error == ChargingPileFailure.consentRequired)
          stopped = true;
        _completed++;
        _emit();
      }
    }

    try {
      await Future.wait(
        List.generate(math.min(6, devices.length), (_) => worker()),
      );
    } finally {
      _batches.remove(batch);
      _emit();
    }
  }

  Future<void> _refreshOne(
    ChargingPileDevice device,
    ChargingPileCancellation runtime,
  ) async {
    final existing = _inFlight[device.id];
    if (existing != null) return existing;
    final attempted = _cache[device.id]?.attemptedAt;
    if (attempted != null &&
        _now().difference(attempted) < const Duration(seconds: 60))
      return;
    final flight = _query(device, runtime);
    _inFlight[device.id] = flight;
    try {
      await flight;
    } finally {
      if (identical(_inFlight[device.id], flight)) _inFlight.remove(device.id);
    }
  }

  Future<void> _query(
    ChargingPileDevice device,
    ChargingPileCancellation runtime,
  ) async {
    // Global across overlapping batches/pages, not six per refresh call.
    while (_active >= 6) {
      await Future.any([
        Future<void>.delayed(const Duration(milliseconds: 20)),
        runtime.whenCancelled,
      ]);
      if (runtime.isCancelled || _disposed) return;
    }
    if (runtime.isCancelled ||
        _disposed ||
        _pausedUntil?.isAfter(_now()) == true)
      return;
    _active++;
    final attemptedAt = _now();
    try {
      List<ChargingPileSlot>? slots;
      for (var attempt = 0; attempt < 2; attempt++) {
        runtime.check();
        if (_pausedUntil?.isAfter(_now()) == true) return;
        try {
          slots = await _api.queryDevice(device.id, runtime);
          break;
        } on ChargingPileException catch (e) {
          if (e.failure != ChargingPileFailure.network || attempt == 1) rethrow;
          await Future.any([
            Future<void>.delayed(retryDelay),
            runtime.whenCancelled,
          ]);
        }
      }
      runtime.check();
      if (_disposed) return;
      _networkFailures = 0;
      _cache[device.id] = ChargingPileCachedDevice(
        status: ChargingPileDeviceStatus(
          device: device,
          slots: slots!,
          fetchedAt: _now(),
        ),
        attemptedAt: attemptedAt,
      );
    } on ChargingPileException catch (e) {
      if (runtime.isCancelled ||
          _disposed ||
          e.failure == ChargingPileFailure.cancelled)
        return;
      _recordFailure(device, e.failure, attemptedAt);
    } catch (_) {
      if (!runtime.isCancelled && !_disposed)
        _recordFailure(device, ChargingPileFailure.platform, attemptedAt);
    } finally {
      _active--;
      _emit();
    }
  }

  void _recordFailure(
    ChargingPileDevice device,
    ChargingPileFailure failure,
    DateTime attemptedAt,
  ) {
    _failure = failure;
    _cache[device.id] = ChargingPileCachedDevice(
      status: _cache[device.id]?.status,
      failure: failure,
      attemptedAt: attemptedAt,
    );
    if (failure == ChargingPileFailure.network) {
      _networkFailures++;
    } else {
      _networkFailures = 0;
    }
    if (failure == ChargingPileFailure.rateLimited || _networkFailures >= 5) {
      _pauseReason = failure;
      _pausedUntil = _now().add(const Duration(minutes: 10));
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    PrivacyAgreementService.revision.removeListener(_privacyChanged);
    _cancelWork();
    _credentials?.close();
    if (identical(_shared, this)) _shared = null;
    super.dispose();
  }
}
