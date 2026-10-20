import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capabilities/time_reminder.dart';
import 'auth_service.dart';
import 'privacy_agreement_service.dart';
import 'platform_compatibility_service.dart';
import 'logger_service.dart';
import 'demo_data_service.dart';

export '../capabilities/time_reminder.dart';

class TimeReminderStatus {
  const TimeReminderStatus({
    this.supported = false,
    this.notifications = false,
    this.exact = false,
  });
  final bool supported;
  final bool notifications;
  final bool exact;
  bool get ready => supported && notifications && exact;
}

/// Single host boundary for typed future events. Native storage never fetches
/// campus data. All async work is fenced by the active host session and epoch.
class TimeReminderService {
  static const _channel = MethodChannel('mychu/time_reminders');
  static const settingsKey = 'preferences.time_reminders.v2';
  static final revision = ValueNotifier<int>(0);
  static final _refreshers =
      <TimeReminderCategory, Future<void> Function(String)>{};
  static final _revisions = <TimeReminderCategory, int>{};
  static int _epoch = 0;
  static String? _account;
  static String? _owner;
  static int? _generation;
  static Future<void>? _tail;
  static Future<void>? _initialization;
  static final _refreshBatches = <String, Future<void>>{};
  static final _refreshedAt = <String, DateTime>{};

  @visibleForTesting
  static Future<Object?> Function(String, Object?)? debugInvoke;
  @visibleForTesting
  static Future<String?> Function()? debugAccount;
  @visibleForTesting
  static Future<bool> Function()? debugAccepted;
  @visibleForTesting
  static DateTime Function()? debugClock;

  static bool get isSupported =>
      debugInvoke != null ||
      PlatformCompatibilityService.isAndroid ||
      PlatformCompatibilityService.isApple;
  static Future<Object?> _invoke(String method, [Object? args]) async {
    if (!isSupported) return null;
    try {
      return await (debugInvoke?.call(method, args) ??
          _channel.invokeMethod<Object?>(method, args));
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> _currentAccount() async =>
      debugAccount != null
          ? await debugAccount!()
          : (await AuthService.getCurrentAccount())?.accountKey;
  static Future<bool> _accepted() =>
      debugAccepted?.call() ?? PrivacyAgreementService.isAccepted();
  static Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  static void register(
    TimeReminderCategory category,
    Future<void> Function(String) refresh,
  ) {
    _refreshers[category] = refresh;
  }

  static Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object error) {
        _initialization = null;
        throw error;
      });
  static Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('time_reminders.v2.reset') == true) return;
    // A reset, never a settings import. Native cleanup is separately retryable.
    await _invoke('resetLegacy');
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('preferences.v1.alerts') ||
          key.startsWith('preferences.v1.live_update.') ||
          key.startsWith('alerts.v1.') ||
          key.startsWith('live_update.') ||
          key.startsWith('inapp.notifications.')) {
        if (!await prefs.remove(key)) throw StateError('Reminder reset failed');
      }
    }
    if (!await prefs.setBool('time_reminders.v2.reset', true)) {
      throw StateError('Reminder reset failed');
    }
  }

  static Future<Map<TimeReminderCategory, TimeReminderSetting>>
  settings() async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    Map raw = const {};
    try {
      final value = jsonDecode(prefs.getString(settingsKey) ?? '{}');
      if (value is Map) {
        raw = value;
      }
    } catch (_) {}
    return {
      for (final category in TimeReminderCategory.values)
        category: TimeReminderSetting(
          enabled:
              raw[category.name] is Map
                  ? raw[category.name]['enabled'] != false
                  : true,
          advance: ((raw[category.name] is Map
                          ? raw[category.name]['advance']
                          : null)
                      is num
                  ? (raw[category.name]['advance'] as num).toInt()
                  : category.defaultLead)
              .clamp(category.minLead, category.maxLead),
        ),
    };
  }

  static Future<void> updateSetting(
    TimeReminderCategory category,
    TimeReminderSetting setting,
  ) async {
    // Invalidate builders immediately, before persistence yields.
    _revisions[category] = (_revisions[category] ?? 0) + 1;
    final active = await _currentAccount();
    if (active != null && isSupported) {
      await _activate(active, _epoch, AuthService.sessionRevision);
    }
    await _serial(() async {
      final values = await settings();
      values[category] = TimeReminderSetting(
        enabled: setting.enabled,
        advance: setting.advance.clamp(category.minLead, category.maxLead),
      );
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        settingsKey,
        jsonEncode({
          for (final entry in values.entries)
            entry.key.name: {
              'enabled': entry.value.enabled,
              'advance': entry.value.advance,
            },
        }),
      )) {
        throw StateError('Reminder setting write failed');
      }
      if (_owner != null && !setting.enabled) {
        await _invoke('cancelCategory', {
          'owner': _owner,
          'generation': _generation,
          'category': category.name,
        });
      }
    });
    revision.value++;
    final account = await _currentAccount();
    if (account != null && setting.enabled) {
      await refresh(category, account);
    }
  }

  static Future<TimeReminderStatus> status() async {
    if (!isSupported) return const TimeReminderStatus();
    try {
      await initialize();
      final raw = await _invoke('status');
      if (raw is Map) {
        return TimeReminderStatus(
          supported: true,
          notifications: raw['notifications'] == true,
          exact: raw['exact'] == true,
        );
      }
    } catch (_) {}
    return const TimeReminderStatus();
  }

  static Future<bool> _activate(String account, int epoch, int session) =>
      _serial(() async {
        if (!await _isCurrent(account, epoch, session)) return false;
        if (_account == account && _owner != null && _generation != null) {
          return true;
        }
        await initialize();
        final prefs = await SharedPreferences.getInstance();
        var owner = prefs.getString('time_reminders.v2.owner');
        if (prefs.getString('time_reminders.v2.account') != account ||
            owner == null) {
          final random = Random.secure();
          owner =
              List.generate(
                24,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
              ).join();
          await prefs.setString('time_reminders.v2.owner', owner);
          await prefs.setString('time_reminders.v2.account', account);
        }
        if (!await _isCurrent(account, epoch, session)) return false;
        final generation = await _invoke('activate', {'owner': owner});
        if (!await _isCurrent(account, epoch, session) || generation is! int) {
          return false;
        }
        _account = account;
        _owner = owner;
        _generation = generation;
        return true;
      });

  static Future<bool> _isCurrent(
    String account,
    int epoch,
    int session,
  ) async =>
      epoch == _epoch &&
      session == AuthService.sessionRevision &&
      await _accepted() &&
      await _currentAccount() == account &&
      epoch == _epoch &&
      session == AuthService.sessionRevision;

  static Future<void> replaceEvents(
    String account,
    TimeReminderCategory category,
    FutureOr<List<TimeReminderEvent>?> Function() build, {
    List<int> Function()? coveredDays,
  }) async {
    if (!isSupported || account.isEmpty || DemoDataService.instance.enabled) {
      return;
    }
    final epoch = _epoch;
    final session = AuthService.sessionRevision;
    final version = (_revisions[category] ?? 0) + 1;
    _revisions[category] = version;
    try {
      if (!await _activate(account, epoch, session)) return;
      final setting = (await settings())[category]!;
      final events = setting.enabled ? await build() : <TimeReminderEvent>[];
      if (events == null) return;
      final payloads = buildTimeReminderPayloads(
        category,
        setting,
        events,
        debugClock?.call() ?? DateTime.now().toUtc(),
      );
      await _serial(() async {
        if (_revisions[category] != version ||
            !await _isCurrent(account, epoch, session)) {
          return;
        }
        await _invoke('replaceCategory', {
          'owner': _owner,
          'generation': _generation,
          'category': category.name,
          'events': payloads,
          if (coveredDays != null && setting.enabled)
            'coveredDays': coveredDays(),
          'activeEvents':
              setting.enabled
                  ? [
                    for (final e in events)
                      if (e.at.isAfter(
                        debugClock?.call() ?? DateTime.now().toUtc(),
                      ))
                        '${e.id}|${e.at.toUtc().millisecondsSinceEpoch}',
                  ]
                  : <String>[],
        });
      });
    } catch (error) {
      AppLogger.warn('时间提醒调度失败 (${error.runtimeType})');
    }
  }

  static Future<void> refresh(
    TimeReminderCategory category,
    String account,
  ) async {
    try {
      await _refreshers[category]?.call(account);
    } catch (error) {
      AppLogger.warn('时间提醒刷新失败 (${error.runtimeType})');
    }
  }

  static Future<void> refreshAll({bool force = false}) async {
    final epoch = _epoch;
    if (!isSupported ||
        DemoDataService.instance.enabled ||
        !await _accepted()) {
      return;
    }
    final account = await _currentAccount();
    if (account == null || epoch != _epoch) return;
    final key = '$epoch:$account';
    final pending = _refreshBatches[key];
    if (pending != null) return pending;
    final now = debugClock?.call() ?? DateTime.now();
    final last = _refreshedAt[key];
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(minutes: 3)) {
      // Permission changes can require native rescheduling even while the
      // source data remains fresh. This does not fetch campus data.
      await _serial(() async {
        if (_account == account && epoch == _epoch) {
          await _invoke('reschedule');
        }
      });
      return;
    }
    final future = _refreshAll(account, epoch);
    _refreshBatches[key] = future;
    try {
      await future;
      if (epoch == _epoch) _refreshedAt[key] = now;
    } finally {
      if (identical(_refreshBatches[key], future)) _refreshBatches.remove(key);
    }
  }

  static Future<void> _refreshAll(String account, int epoch) async {
    await Future.wait([
      for (final category in TimeReminderCategory.values)
        refresh(category, account),
    ]);
    await _serial(() async {
      if (_account == account && epoch == _epoch) {
        await _invoke('reschedule');
      }
    });
  }

  static Future<void> clearAll() {
    _refreshedAt.clear();
    _refreshBatches.clear();
    _epoch++;
    _account = null;
    _owner = null;
    _generation = null;
    _revisions.clear();
    return _serial(() async {
      await _invoke('deactivate');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('time_reminders.v2.owner');
      await prefs.remove('time_reminders.v2.account');
    });
  }

  static Future<bool> acceptsLaunch(Map payload) async {
    final account = await _currentAccount();
    if (account == null || !await _accepted()) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('time_reminders.v2.account') != account ||
        prefs.getString('time_reminders.v2.owner') != payload['owner']) {
      return false;
    }
    final category =
        TimeReminderCategory.values
            .where((c) => c.name == payload['category'])
            .firstOrNull;
    if (category == null || category.targetAppId != payload['targetAppId']) {
      return false;
    }
    if (!(await settings())[category]!.enabled) return false;
    return await _invoke('validateLaunch', payload) == true;
  }

  @visibleForTesting
  static void debugReset() {
    _refreshBatches.clear();
    _refreshedAt.clear();
    _epoch++;
    _tail = null;
    _account = null;
    _owner = null;
    _generation = null;
    _initialization = null;
    _revisions.clear();
    _refreshers.clear();
    debugInvoke = null;
    debugAccount = null;
    debugAccepted = null;
    debugClock = null;
  }
}
