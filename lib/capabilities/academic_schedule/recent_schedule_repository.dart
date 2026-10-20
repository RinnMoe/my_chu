import 'dart:async';
import 'package:flutter/foundation.dart';
import '../persistent_summary_cache.dart';
import '../east8_time.dart';
import '../../services/auth_service.dart';
import '../../services/host_auth_state.dart';
import '../../services/privacy_agreement_service.dart';
import '../../services/roomis_schedule_service.dart';
import 'recent_schedule.dart';

/// Only explicit host opens/refreshes perform network work. Consumers read cache.
class RecentScheduleRepository {
  static final instance = RecentScheduleRepository();
  final PersistentSummaryCache<RecentScheduleWindow> _cache;
  final Future<RecentScheduleWindow> Function(DateTime) _fetch;
  final Future<String?> Function() _account;
  final Future<bool> Function() _consent;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _pending = {};
  final Map<String, RecentScheduleWindow> _fresh = {};
  final Map<String, DateTime> _failedUntil = {};
  int _generation = 0;

  RecentScheduleRepository({
    PersistentSummaryCache<RecentScheduleWindow>? cache,
    Future<RecentScheduleWindow> Function(DateTime)? fetch,
    Future<String?> Function()? account,
    Future<bool> Function()? consent,
    DateTime Function()? clock,
  }) : _cache =
           cache ??
           PersistentSummaryCache<RecentScheduleWindow>(
             storageKey: 'roomis.recent_schedule.v1',
             ttl: const Duration(days: 7),
             persistTtl: const Duration(days: 7),
             maxEntries: 8,
             fromJson: RecentScheduleWindow.fromJson,
             toJson: (value) => value.toJson(),
           ),
       _fetch = fetch ?? RoomisScheduleService().fetch,
       _account =
           account ??
           (() async => (await AuthService.getCurrentAccount())?.accountKey),
       _consent = consent ?? PrivacyAgreementService.isAccepted,
       _clock = clock ?? east8Now;

  ValueNotifier<int> get revision => _cache.revision;

  Future<RecentScheduleWindow?> read(String accountKey) async {
    final generation = _generation;
    final revision = AuthService.sessionRevision;
    if (!await _consent() || await _account() != accountKey) return null;
    final value =
        _cache.peek(accountKey, 'week') ??
        await _cache.readFromDisk(accountKey, 'week');
    if (!await _consent() ||
        await _account() != accountKey ||
        generation != _generation ||
        revision != AuthService.sessionRevision) {
      return null;
    }
    return value;
  }

  bool isFresh(String accountKey, RecentScheduleWindow window) =>
      identical(_fresh[accountKey], window);

  Future<void> refresh({bool force = true}) async {
    if (HostAuthState.initialized &&
        HostAuthState.snapshot.value.blocksRequests) {
      return;
    }
    if (!await _consent()) return;
    final key = await _account();
    if (key == null) return;
    final existing = _pending[key];
    if (existing != null) return existing;
    if (!force) {
      final now = east8WallClockToUtcInstant(_clock());
      if (_failedUntil[key]?.isAfter(now) ?? false) return;
      final cached = await read(key);
      if (cached != null &&
          cached.startDate == recentScheduleDate(_clock()) &&
          now.difference(cached.fetchedAt) < const Duration(minutes: 15)) {
        _fresh[key] = cached;
        return;
      }
    }
    final revision = AuthService.sessionRevision;
    final future = _refresh(key, revision, _generation);
    _pending[key] = future;
    try {
      await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<void> clear() async {
    _generation++;
    _fresh.clear();
    _failedUntil.clear();
    _pending.clear();
    await _cache.clearAll();
  }

  Future<void> _refresh(String key, int revision, int generation) async {
    _fresh.remove(key);
    try {
      final window = await _cache.load(key, 'week', () async {
        final result = await _fetch(_clock());
        if (await _account() != key ||
            !await _consent() ||
            AuthService.sessionRevision != revision ||
            generation != _generation) {
          throw const RecentScheduleInvalidated();
        }
        return result;
      }, force: true);
      if (await _account() == key &&
          await _consent() &&
          AuthService.sessionRevision == revision &&
          generation == _generation) {
        _fresh[key] = window;
        _failedUntil.remove(key);
      }
    } catch (_) {
      if (generation == _generation) {
        _failedUntil[key] = east8WallClockToUtcInstant(
          _clock(),
        ).add(const Duration(seconds: 30));
      }
      // Keep the last successfully obtained range; the resolver owns fallback.
    }
    this.revision.value++;
  }
}

class RecentScheduleInvalidated implements Exception {
  const RecentScheduleInvalidated();
}
