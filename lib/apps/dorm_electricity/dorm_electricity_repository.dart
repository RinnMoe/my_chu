import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../capabilities/dorm_electricity.dart';
import '../../services/privacy_agreement_service.dart';
import '../../services/dorm_electricity_storage_service.dart';
import '../../capabilities/east8_time.dart';
import '../../services/remote_feature_policy/feature_access_guard.dart';
import '../../services/remote_feature_policy/remote_feature_policy_service.dart';
import 'dorm_electricity_models.dart';
import 'dorm_electricity_parser.dart';
import 'dorm_electricity_period.dart';

class ElectricityStore {
  ElectricityStore({FlutterSecureStorage? storage})
    : _storage = DormElectricityStorageService(storage: storage);
  static const key = DormElectricityStorageService.key;
  final DormElectricityStorageService _storage;

  Future<ElectricityRecord?> read() async {
    try {
      final raw = await _storage.read();
      return raw == null
          ? null
          : ElectricityRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      throw const DormElectricityException('storage');
    }
  }

  Future<void> write(ElectricityRecord? record, bool Function() current) async {
    try {
      final saved = await _storage.write(
        record == null ? null : jsonEncode(record.toJson()),
        current,
      );
      if (!saved) throw const DormElectricityException('cancelled');
    } on DormElectricityException {
      rethrow;
    } catch (_) {
      throw const DormElectricityException('storage');
    }
  }
}

class ElectricityBilling {
  ElectricityBill? bill;
  List<ElectricityDailyUsage>? daily;
  DormElectricityException? billError, dailyError;
  bool loadingBill = false, loadingDaily = false;
  DateTime? billFetchedAt, dailyFetchedAt;
}

class _ElectricityBillingJob {
  _ElectricityBillingJob(
    this.key,
    this.month,
    this.meter,
    this.kind,
    this.state,
    this.generation, {
    required this.preload,
  });
  final String key, month, meter;
  final DormElectricityQuery kind;
  final ElectricityBilling state;
  final int generation;
  final request = DormElectricityRequest();
  final done = Completer<void>();
  bool preload, running = false;
}

/// One page owns one controller; storage is device-scoped, never campus-scoped.
class ElectricityRepository extends ChangeNotifier {
  ElectricityRepository({
    DormElectricityCapability? capability,
    ElectricityStore? store,
    Future<bool> Function()? allowed,
    DateTime Function()? now,
    bool observeGates = true,
  }) : _capability = capability ?? DormElectricityCapability(),
       _store = store ?? ElectricityStore(),
       _allowed = allowed ?? _defaultAllowed,
       _now = now ?? DateTime.now,
       _observeGates = observeGates {
    DormElectricityStorageService.revision.addListener(_signedOut);
    if (_observeGates) {
      PrivacyAgreementService.revision.addListener(_gateChanged);
      RemoteFeaturePolicyService.instance.revision.addListener(_gateChanged);
    }
  }

  static Future<bool> _defaultAllowed() async {
    if (!await PrivacyAgreementService.isAccepted()) return false;
    final decision = FeatureAccessGuard.instance.decide(
      featureId: dormElectricityFeatureId,
    );
    return decision.canLaunch && decision.isEntryVisible;
  }

  final DormElectricityCapability _capability;
  final ElectricityStore _store;
  final Future<bool> Function() _allowed;
  final DateTime Function() _now;
  final bool _observeGates;
  final _requests = <DormElectricityRequest>{};
  static const billingConcurrency = 4;
  static const billingCacheTtl = Duration(minutes: 5);
  static const _cachedMonthLimit = 24;
  final _billingJobs = <String, _ElectricityBillingJob>{};
  final _cachedMonths = <String, Map<String, ElectricityBilling>>{};
  int _generation = 0, _periodGeneration = 0;
  bool _disposed = false;
  Future<void>? _balanceFlight;
  Future<void>? _billingFlight;
  ElectricityRecord? record;
  final billingByMonth = <String, Map<String, ElectricityBilling>>{};
  Iterable<ElectricityBilling> get billingStates =>
      billingByMonth.values.expand((states) => states.values);
  String? _periodKey;

  final balanceErrors = <String, DormElectricityException>{};
  DormElectricityException? saveError;
  bool loadingBalance = false;
  bool get stale =>
      record?.meters.any((meter) => isStale(meter.balance)) ?? false;
  bool isStale(ElectricityBalance balance) =>
      _now().difference(balance.fetchedAt) >= const Duration(seconds: 60);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void cancelPending() {
    _generation++;
    _periodGeneration++;
    _periodKey = null;
    _cancelBillingJobs((_) => true);
    for (final request in _requests.toList()) {
      request.cancel();
    }
    _requests.clear();
    _balanceFlight = null;
    _billingFlight = null;
    loadingBalance = false;
    for (final state in billingStates) {
      state.loadingBill = state.loadingDaily = false;
    }
  }

  void _gateChanged() {
    cancelPending();
    record = null;
    billingByMonth.clear();
    _cachedMonths.clear();
    _periodKey = null;
    balanceErrors.clear();
    saveError = null;
    _changed();
    final generation = _generation;
    unawaited(
      _allowed()
          .then((allowed) async {
            final saved = allowed ? await _store.read() : null;
            if (!_current(generation)) return;
            record = saved;
            _changed();
          })
          .catchError((Object _) {
            if (_current(generation)) {
              saveError = const DormElectricityException('storage');
              _changed();
            }
          }),
    );
  }

  Future<void> restore() async {
    final generation = _generation;
    final saved = await _store.read();
    if (!await _allowed() || !_current(generation)) return;
    record = saved;
    _changed();
  }

  Future<List<ElectricityMeter>> resolveRoom(
    String roomId,
    String buildingInfo,
  ) async {
    final generation = _generation;
    final request = DormElectricityRequest();
    _requests.add(request);
    try {
      if (!await _allowed()) throw const DormElectricityException('blocked');
      request.check();
      final response = await _capability.resolveRoom(
        roomId: roomId,
        buildingInfo: buildingInfo,
        request: request,
      );
      if (!_current(generation) || !await _allowed()) {
        throw const DormElectricityException('cancelled');
      }
      request.check();
      return ElectricityParser.meterRows(response);
    } finally {
      _requests.remove(request);
    }
  }

  Future<void> select({
    required String label,
    required List<ElectricityMeter> meters,
  }) async {
    if (meters.isEmpty) throw const DormElectricityException('empty');
    cancelPending();
    final generation = _generation;
    loadingBalance = true;
    saveError = null;
    _changed();
    try {
      final readings = <ElectricityMeterRecord>[];
      for (final meter in meters) {
        final balance = await _fetchBalance(meter.id, generation);
        readings.add(ElectricityMeterRecord(meter, balance));
      }
      final next = ElectricityRecord(label, List.unmodifiable(readings));
      await _store.write(next, () => _current(generation));
      if (!_current(generation)) return;
      record = next;
      billingByMonth.clear();
      _cachedMonths.clear();
      _periodKey = null;
      balanceErrors.clear();
    } finally {
      if (_current(generation)) {
        loadingBalance = false;
        _changed();
      }
    }
  }

  Future<ElectricityBalance> _fetchBalance(String meter, int generation) async {
    if (!_current(generation)) {
      throw const DormElectricityException('cancelled');
    }
    final request = DormElectricityRequest();
    _requests.add(request);
    try {
      if (!await _allowed()) throw const DormElectricityException('blocked');
      request.check();
      if (!_current(generation)) {
        throw const DormElectricityException('cancelled');
      }
      final response = await _capability.query(
        meter: meter,
        kind: DormElectricityQuery.balance,
        request: request,
      );
      if (!_current(generation) || !await _allowed()) {
        throw const DormElectricityException('cancelled');
      }
      request.check();
      return ElectricityParser.balance(response, now: _now());
    } finally {
      _requests.remove(request);
    }
  }

  Future<void> refresh({bool force = false}) {
    if (_balanceFlight != null) return _balanceFlight!;
    final saved = record;
    if (saved == null || (!force && !stale)) return Future.value();
    final generation = _generation;
    loadingBalance = true;
    saveError = null;
    balanceErrors.clear();
    _changed();
    final flight = () async {
      try {
        final readings = saved.meters.toList();
        var updated = false;
        for (var index = 0; index < readings.length; index++) {
          final previous = readings[index];
          if (!force && !isStale(previous.balance)) continue;
          try {
            final balance = await _fetchBalance(previous.meter.id, generation);
            if (!_current(generation)) return;
            readings[index] = ElectricityMeterRecord(previous.meter, balance);
            updated = true;
          } on DormElectricityException catch (error) {
            if (!_current(generation) || error.code == 'cancelled') return;
            balanceErrors[previous.meter.id] = error;
          }
        }
        if (updated) {
          final next = ElectricityRecord(
            saved.label,
            List.unmodifiable(readings),
          );
          await _store.write(next, () => _current(generation));
          if (_current(generation)) record = next;
        }
      } on DormElectricityException catch (error) {
        if (_current(generation) && error.code != 'cancelled') {
          saveError = error;
        }
      } finally {
        if (_current(generation)) {
          loadingBalance = false;
          _balanceFlight = null;
          _changed();
        }
      }
    }();
    _balanceFlight = flight;
    return flight;
  }

  DateTime get _today {
    final date = _now().toUtc().add(east8Offset);
    return DateTime.utc(date.year, date.month, date.day);
  }

  Future<void> loadPeriod(ElectricityPeriod period, {bool force = false}) {
    final saved = record;
    if (saved == null) return Future.value();
    if (!force && _periodKey == period.key && _billingFlight != null) {
      return _billingFlight!;
    }
    final months = period.monthsThrough(_today);
    final daily = period.scale != ElectricityScale.year;
    final generation = _generation;
    final periodGeneration = ++_periodGeneration;
    _cancelBillingJobs(
      (job) =>
          !months.contains(job.month) ||
          (!daily && job.kind == DormElectricityQuery.daily),
    );
    _periodKey = period.key;
    billingByMonth.clear();
    final pending = <Future<void>>[];
    for (final month in months) {
      final states = _monthStates(month);
      billingByMonth[month] = states;
      for (final meter in saved.meters) {
        for (final kind in [
          DormElectricityQuery.bill,
          if (daily) DormElectricityQuery.daily,
        ]) {
          pending.add(
            _enqueueBilling(
              month,
              meter.meter.id,
              kind,
              states[meter.meter.id]!,
              preload: false,
              force: force,
            ),
          );
        }
      }
    }
    _pruneBillingCache();
    _changed();
    final flight = Future.wait(pending).then((_) {
      if (_current(generation) && periodGeneration == _periodGeneration) {
        _billingFlight = null;
        _changed();
      }
    });
    _billingFlight = flight;
    _drainBillingQueue();
    return flight;
  }

  /// The page starts this only after its visible period finishes. Background
  /// jobs use two slots and never add loading or errors to the visible period.
  Future<void> preload(ElectricityPeriod period) {
    final saved = record;
    if (saved == null ||
        _periodKey != period.key ||
        _disposed ||
        _billingFlight != null) {
      return Future.value();
    }
    final months = <String, bool>{};
    if (period.scale != ElectricityScale.year) {
      for (final adjacent in [period.shifted(-1), period.shifted(1)]) {
        if (adjacent.start.year < 2000) continue;
        for (final month in adjacent.monthsThrough(_today)) {
          months[month] = true;
        }
      }
    }
    final year = ElectricityPeriod(ElectricityScale.year, period.anchor);
    for (final month in year.monthsThrough(_today).reversed) {
      months.putIfAbsent(month, () => false);
    }
    final pending = <Future<void>>[];
    for (final entry in months.entries) {
      if (billingByMonth.containsKey(entry.key)) continue;
      final states = _monthStates(entry.key);
      for (final meter in saved.meters) {
        for (final kind in [
          DormElectricityQuery.bill,
          if (entry.value) DormElectricityQuery.daily,
        ]) {
          pending.add(
            _enqueueBilling(
              entry.key,
              meter.meter.id,
              kind,
              states[meter.meter.id]!,
              preload: true,
            ),
          );
        }
      }
    }
    _pruneBillingCache();
    _drainBillingQueue();
    return Future.wait(pending).then((_) {});
  }

  Map<String, ElectricityBilling> _monthStates(String month) {
    final states =
        _cachedMonths.remove(month) ?? <String, ElectricityBilling>{};
    for (final meter in record!.meters) {
      states.putIfAbsent(meter.meter.id, ElectricityBilling.new);
    }
    _cachedMonths[month] = states;
    return states;
  }

  void _pruneBillingCache() {
    final protected = {
      ...billingByMonth.keys,
      for (final job in _billingJobs.values) job.month,
    };
    for (final month in _cachedMonths.keys.toList()) {
      if (_cachedMonths.length <= _cachedMonthLimit) break;
      if (!protected.contains(month)) _cachedMonths.remove(month);
    }
  }

  bool _billingFresh(ElectricityBilling state, DormElectricityQuery kind) {
    final bill = kind == DormElectricityQuery.bill;
    final fetchedAt = bill ? state.billFetchedAt : state.dailyFetchedAt;
    if (fetchedAt == null ||
        (bill ? state.billError : state.dailyError) != null) {
      return false;
    }
    final age = _now().difference(fetchedAt);
    return !age.isNegative && age < billingCacheTtl;
  }

  Future<void> _enqueueBilling(
    String month,
    String meter,
    DormElectricityQuery kind,
    ElectricityBilling state, {
    required bool preload,
    bool force = false,
  }) {
    final key = '$month|$meter|${kind.name}';
    final existing = _billingJobs[key];
    if (existing != null) {
      if (!preload) existing.preload = false;
      return existing.done.future;
    }
    if (!force && _billingFresh(state, kind)) return Future.value();
    if (kind == DormElectricityQuery.bill) {
      state.loadingBill = true;
      state.billError = null;
    } else {
      state.loadingDaily = true;
      state.dailyError = null;
    }
    final job = _ElectricityBillingJob(
      key,
      month,
      meter,
      kind,
      state,
      _generation,
      preload: preload,
    );
    _billingJobs[key] = job;
    return job.done.future;
  }

  void _cancelBillingJobs(bool Function(_ElectricityBillingJob) matches) {
    for (final job in _billingJobs.values.toList().where(matches)) {
      job.request.cancel();
      _billingJobs.remove(job.key);
      _requests.remove(job.request);
      _finishBillingState(job);
      job.done.complete();
    }
  }

  void _finishBillingState(_ElectricityBillingJob job) {
    if (job.kind == DormElectricityQuery.bill) {
      job.state.loadingBill = false;
    } else {
      job.state.loadingDaily = false;
    }
  }

  void _drainBillingQueue() {
    if (_disposed) return;
    while (_billingJobs.values.where((job) => job.running).length <
        billingConcurrency) {
      final waiting = _billingJobs.values.where((job) => !job.running);
      final foreground = waiting.where((job) => !job.preload).firstOrNull;
      final preloads =
          _billingJobs.values.where((job) => job.running && job.preload).length;
      final job = foreground ?? (preloads < 2 ? waiting.firstOrNull : null);
      if (job == null) return;
      job.running = true;
      unawaited(_runBillingJob(job));
    }
  }

  Future<void> _runBillingJob(_ElectricityBillingJob job) async {
    bool current() =>
        _current(job.generation) && identical(_billingJobs[job.key], job);
    final state = job.state;
    _requests.add(job.request);
    try {
      if (!await _allowed()) throw const DormElectricityException('blocked');
      if (!current()) return;
      job.request.check();
      final response = await _capability.query(
        meter: job.meter,
        kind: job.kind,
        month: job.month,
        request: job.request,
      );
      if (!current() || !await _allowed()) return;
      job.request.check();
      if (job.kind == DormElectricityQuery.bill) {
        state.bill = ElectricityParser.bill(response, job.month);
        state.billFetchedAt = _now();
      } else {
        state.daily = ElectricityParser.daily(response, job.month);
        state.dailyFetchedAt = _now();
      }
    } catch (error) {
      final failure =
          error is DormElectricityException
              ? error
              : const DormElectricityException('network');
      if (current() && !job.request.cancelled && failure.code != 'cancelled') {
        if (job.kind == DormElectricityQuery.bill) {
          state.billError = failure;
        } else {
          state.dailyError = failure;
        }
      }
    } finally {
      _requests.remove(job.request);
      if (current()) {
        _billingJobs.remove(job.key);
        _finishBillingState(job);
        job.done.complete();
        if (identical(billingByMonth[job.month]?[job.meter], state)) _changed();
        _drainBillingQueue();
      }
    }
  }

  List<ElectricityDailyUsage> readings(ElectricityPeriod period, String meter) {
    final result = <ElectricityDailyUsage>[];
    for (final entry in billingByMonth.entries) {
      final state = entry.value[meter];
      if (period.scale == ElectricityScale.year) {
        final bill = state?.bill;
        if (bill != null) {
          result.add(
            ElectricityDailyUsage(
              // The period anchor is UTC; a local DateTime here would sit in the
              // previous month for any positive UTC offset.
              DateTime.utc(
                int.parse(entry.key.substring(0, 4)),
                int.parse(entry.key.substring(5, 7)),
                1,
              ),
              bill.kwh,
              bill.amount,
            ),
          );
        }
      } else {
        result.addAll(
          (state?.daily ?? const <ElectricityDailyUsage>[]).where(
            (day) =>
                !DateTime.utc(
                  day.date.year,
                  day.date.month,
                  day.date.day,
                ).isBefore(period.start) &&
                DateTime.utc(
                  day.date.year,
                  day.date.month,
                  day.date.day,
                ).isBefore(period.end),
          ),
        );
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  void _signedOut() {
    cancelPending();
    record = null;
    billingByMonth.clear();
    _cachedMonths.clear();
    _periodKey = null;
    balanceErrors.clear();
    saveError = null;
    _changed();
  }

  Future<void> clear() async {
    cancelPending();
    final generation = _generation;
    await _store.write(null, () => _current(generation));
    if (!_current(generation)) return;
    record = null;
    billingByMonth.clear();
    _cachedMonths.clear();
    _periodKey = null;
    balanceErrors.clear();
    saveError = null;
    _changed();
  }

  @override
  void dispose() {
    cancelPending();
    _disposed = true;
    DormElectricityStorageService.revision.removeListener(_signedOut);
    if (_observeGates) {
      PrivacyAgreementService.revision.removeListener(_gateChanged);
      RemoteFeaturePolicyService.instance.revision.removeListener(_gateChanged);
    }
    super.dispose();
  }
}
