import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'charging_credential_service.dart';
import '../../services/privacy_agreement_service.dart';
import 'charging_pile_api_client.dart';
import 'charging_pile_catalog.dart';
import 'charging_pile_models.dart';

/// One process-wide source of truth, shared by native pages and future clients.
/// No polling: consumers explicitly refresh the entire page.
class ChargingPileRepository extends ChangeNotifier {
  factory ChargingPileRepository.shared() =>
      _shared ??= ChargingPileRepository();
  static ChargingPileRepository? _shared;

  ChargingPileRepository({
    ChargingPileApi? api,
    ChargingCredentialService? credentials,
    List<ChargingPileDevice>? catalog,
    DateTime Function()? now,
    Future<bool> Function()? consent,
    this.retryDelay = const Duration(milliseconds: 800),
  }) : _credentials =
           credentials ?? (api == null ? ChargingCredentialService() : null),
       _catalog = List.unmodifiable(catalog ?? kChargingPileDevices),
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
  final _states = <String, ChargingPileDeviceState>{};
  Future<void>? _pageFlight;
  ChargingPileCancellation _runtime = ChargingPileCancellation();
  bool _pageLoading = false;
  DateTime? _lastPageAttempt;
  DateTime? _updatedAt;
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
  List<ChargingPileArea> loadAreas() =>
      List.unmodifiable(_catalog.map((d) => d.area).toSet());
  Map<String, ChargingPileDeviceState> getState() => Map.unmodifiable(_states);
  ChargingPileDeviceState stateFor(String id) =>
      _states[id] ?? const ChargingPileDeviceState();
  DateTime get now => _now();
  bool get isRefreshing => _pageLoading;
  DateTime? get updatedAt => _updatedAt;
  int get completed => _completed;
  int get total => _total;
  ChargingPileFailure? get failure => _failure;
  DateTime? get pausedUntil => _pausedUntil;

  /// A page/layer must release when hidden or disposed. The last release stops
  /// queued work/retries and fences in-flight page responses.
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
    if (_pageLoading) _lastPageAttempt = null;
    _pageLoading = false;
    _credentials?.cancelPending();
    _emit();
  }

  void _privacyChanged() {
    // Invalidate immediately, before the async preferences read can complete.
    _cancelWork();
    _states.clear();
    _updatedAt = null;
    _failure = ChargingPileFailure.consentRequired;
    _emit();
  }

  Future<void> syncCredential() async {
    final runtime = _runtime;
    try {
      await _credentials?.syncCredential();
      if (runtime.isCancelled || _disposed) return;
      _failure = null;
      _lastPageAttempt = null;
    } on ChargingPileException catch (e) {
      if (runtime.isCancelled || _disposed) return;
      _failure = e.failure;
    }
    _emit();
  }

  /// Refresh the entire directory as one page transaction. Consumers share the
  /// same in-flight batch; filters never create their own device requests.
  Future<void> refreshAll() async {
    if (_disposed) return;
    final pending = _pageFlight;
    if (pending != null) return pending;
    final runtime = _runtime;
    final flight = _refreshPage(runtime);
    _pageFlight = flight;
    try {
      await flight;
    } finally {
      if (identical(_pageFlight, flight)) _pageFlight = null;
    }
  }

  Future<void> _refreshPage(ChargingPileCancellation runtime) async {
    if (runtime.isCancelled || _disposed) return;
    try {
      if (!await _consent()) {
        _failure = ChargingPileFailure.consentRequired;
        _emit();
        return;
      }
    } catch (_) {
      _failure = ChargingPileFailure.storage;
      _emit();
      return;
    }
    if (runtime.isCancelled || _disposed) return;
    if (_pausedUntil?.isAfter(_now()) == true) {
      _failure = _pauseReason;
      _emit();
      return;
    }
    // Deduplicate the whole page, not individual devices. No time-based expiry
    // is applied to displayed results; the next page transaction replaces them.
    if (_lastPageAttempt != null &&
        _states.isNotEmpty &&
        _now().difference(_lastPageAttempt!) < const Duration(seconds: 60))
      return;
    _lastPageAttempt = _now();
    final devices = List<ChargingPileDevice>.of(_catalog);
    _pageLoading = true;
    _completed = 0;
    _total = devices.length;
    _failure = null;
    _networkFailures = 0;
    _states.clear();
    _updatedAt = null;
    _emit();
    final results = <String, ChargingPileDeviceState>{};
    ChargingPileFailure? stopReason;
    var index = 0;
    bool getStopped() => runtime.isCancelled || _disposed || stopReason != null;

    Future<void> worker() async {
      while (!getStopped()) {
        final position = index++;
        if (position >= devices.length) return;
        final device = devices[position];
        try {
          final slots = await _querySlots(device.id, runtime, getStopped);
          if (runtime.isCancelled || _disposed) return;
          _networkFailures = 0;
          results[device.id] = ChargingPileDeviceState(
            status: ChargingPileDeviceStatus(
              device: device,
              slots: slots,
              fetchedAt: _now(),
            ),
          );
        } on ChargingPileException catch (e) {
          if (runtime.isCancelled || _disposed) return;
          if (e.failure == ChargingPileFailure.cancelled) return;
          results[device.id] = ChargingPileDeviceState(failure: e.failure);
          _failure = e.failure;
          if (e.failure == ChargingPileFailure.network) {
            _networkFailures++;
          } else {
            _networkFailures = 0;
          }
          if (e.failure == ChargingPileFailure.rateLimited ||
              _networkFailures >= 5) {
            stopReason ??= e.failure;
            _pauseReason = e.failure;
            _pausedUntil = _now().add(const Duration(minutes: 10));
          } else if (e.failure == ChargingPileFailure.credentialUnavailable ||
              e.failure == ChargingPileFailure.credentialSync ||
              e.failure == ChargingPileFailure.storage ||
              e.failure == ChargingPileFailure.consentRequired) {
            stopReason ??= e.failure;
          }
        } catch (_) {
          if (runtime.isCancelled || _disposed) return;
          results[device.id] = const ChargingPileDeviceState(
            failure: ChargingPileFailure.platform,
          );
          _failure = ChargingPileFailure.platform;
        }
        if (runtime.isCancelled || _disposed) return;
        _completed++;
        _emit(); // Progress only; device results publish together below.
      }
    }

    try {
      await Future.wait(
        List.generate(math.min(6, devices.length), (_) => worker()),
      );
      if (runtime.isCancelled || _disposed) return;
      final ids = _catalog.map((d) => d.id).toSet();
      for (final device in devices) {
        if (ids.contains(device.id)) {
          _states[device.id] =
              results[device.id] ??
              ChargingPileDeviceState(
                failure: stopReason ?? ChargingPileFailure.platform,
              );
        }
      }
      _failure = stopReason ?? _failure;
      _updatedAt =
          results.values.any((entry) => entry.status != null) ? _now() : null;
    } finally {
      if (identical(runtime, _runtime)) {
        _pageLoading = false;
        _emit();
      }
    }
  }

  Future<List<ChargingPileSlot>> _querySlots(
    String id,
    ChargingPileCancellation runtime,
    bool Function() stopped,
  ) async {
    while (_active >= 6) {
      await Future.any([
        Future<void>.delayed(const Duration(milliseconds: 20)),
        runtime.whenCancelled,
      ]);
      runtime.check();
      if (stopped())
        throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
    runtime.check();
    if (stopped())
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    _active++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        runtime.check();
        if (stopped())
          throw const ChargingPileException(ChargingPileFailure.cancelled);
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
      _active--;
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
