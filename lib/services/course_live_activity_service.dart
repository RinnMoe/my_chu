import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capabilities/academic_schedule/recent_schedule.dart';
import '../capabilities/academic_schedule/recent_schedule_loader.dart';
import '../capabilities/academic_schedule/recent_schedule_repository.dart';
import 'auth_service.dart';
import 'course_live_activity.dart';
import 'demo_data_service.dart';
import 'logger_service.dart';
import 'platform_compatibility_service.dart';
import 'privacy_agreement_service.dart';

export 'course_live_activity.dart';

/// Host boundary for the pre-class and ongoing course activity.
///
/// The shared layer resolves which course may be shown and when; the native
/// layer persists that minimum plan and renders one course at a time. Nothing
/// in this service contacts the campus network, keeps a foreground service or
/// holds an account inside the native plan. All asynchronous work is fenced by
/// the active host session, account and generation.
class CourseLiveActivityService {
  static const _channel = MethodChannel(courseLiveActivityChannel);
  static const settingsKey = courseLiveActivitySettingsKey;

  /// Device-global switch, default on.
  static const _enabledKey = '$settingsKey.enabled';

  /// Per-account ownership binding; dropped on logout and account switch.
  static const _accountsKey = '$settingsKey.accounts';

  /// Marker for the one-time sweep of orphaned bindings.
  static const _sweptKey = '$settingsKey.swept';

  /// Stable root destination for a course-activity tap.
  static const String targetAppId = courseLiveActivityTargetAppId;

  /// Bumped whenever the projected plan or the switch changes, so the settings
  /// page and diagnostics can react without polling.
  static final revision = ValueNotifier<int>(0);

  static int _epoch = 0;
  static String? _account;
  static String? _owner;
  static int? _generation;
  static int _planRevision = 0;
  static CourseLiveActivityPlan? _latest;
  static Future<void>? _tail;
  static Future<void>? _initialization;
  static final Map<String, Future<void>> _refreshBatches = {};
  static final Map<String, DateTime> _refreshedAt = {};
  static final Set<String> _forceReprojection = {};
  static Timer? _boundaryTimer;
  static bool _boundaryListenerAttached = false;
  static bool _foreground = true;
  static bool _developerTest = false;

  /// Debug-only synthetic plan; no campus request or timetable cache write.
  static Future<Map<Object?, Object?>> startDeveloperTest({
    bool delayed = false,
  }) async {
    if (!kDebugMode || !isSupported) {
      throw UnsupportedError('仅 Android Debug 可用');
    }
    final epoch = _epoch;
    if (!await _accepted()) throw StateError('请先同意隐私协议');
    return _serial(() async {
      if (!await _accepted() || epoch != _epoch) {
        throw StateError('宿主状态已变更，请重试');
      }
      _planRevision++;
      _developerTest = true;
      try {
        final result = await _invoke('startDeveloperTest', {
          'delayed': delayed,
        });
        if (result is! Map) throw StateError('测试能力不可用');
        return Map<Object?, Object?>.from(result);
      } catch (_) {
        _developerTest = false;
        rethrow;
      }
    });
  }

  static Future<void> stopDeveloperTest() async {
    if (!kDebugMode || !isSupported) return;
    await _serial(() async {
      await _invoke('stopDeveloperTest');
      _developerTest = false;
      _refreshedAt.clear();
    });
  }

  @visibleForTesting
  static Future<Object?> Function(String method, Object? args)? debugInvoke;
  @visibleForTesting
  static Future<String?> Function()? debugAccount;
  @visibleForTesting
  static Future<bool> Function()? debugAccepted;
  @visibleForTesting
  static DateTime Function()? debugClock;
  @visibleForTesting
  static RecentScheduleRepository? debugRepository;
  @visibleForTesting
  static Future<RecentScheduleWindow?> Function(String)? debugReadWindow;
  @visibleForTesting
  static String? debugBoundOwner;
  @visibleForTesting
  static Future<List<RecentScheduleDay>> Function(
    String,
    List<DateTime>,
    RecentScheduleRepository?,
  )?
  debugLoadDays;

  static bool get isSupported =>
      debugInvoke != null || PlatformCompatibilityService.isAndroid;

  static Future<Object?> _invoke(String method, [Object? args]) async {
    if (!isSupported) return null;
    try {
      return await (debugInvoke?.call(method, args) ??
          _channel.invokeMethod<Object?>(method, args));
    } on MissingPluginException {
      return null;
    }
  }

  /// Business clock: stage and expiry maths for the projected courses.
  static DateTime get _now => (debugClock?.call() ?? DateTime.now()).toUtc();

  /// Policy clock for refresh coalescing only. It deliberately ignores the
  /// business clock so a shifted device clock cannot turn the coalescing
  /// window into a publish decision.
  static DateTime get _refreshStamp => DateTime.now();

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

  static Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object error) {
        _initialization = null;
        throw error;
      });

  static Future<void> _initialize() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_sweptKey) != true) {
      // A one-time sweep of bindings that belong to no account at all. A
      // per-account binding is otherwise dropped on logout, account switch or
      // whenever the owner token changes.
      if (!await AuthService.hasAccounts()) {
        if (!await prefs.remove(_accountsKey)) {
          throw StateError('课程实时动态清理失败');
        }
      }
      if (!await prefs.setBool(_sweptKey, true)) {
        throw StateError('课程实时动态清理失败');
      }
    }
  }

  /// The switch is device-global and is independent of the three reminder
  /// categories. Fresh installs default to enabled.
  static Future<bool> isEnabled() async {
    try {
      await initialize();
    } catch (_) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) != false;
  }

  /// Persists the switch and reconciles native state. Disabling invalidates the
  /// current generation first, then rescinds the notification, the alarms and
  /// the persisted plan.
  static Future<void> updateEnabled(bool enabled) async {
    final epoch = _epoch;
    final account = await _currentAccount();
    if (!enabled) {
      _developerTest = false;
      _epoch++;
      _planRevision++;
      _latest = null;

      _generation = null;
      _refreshedAt.clear();
      _refreshBatches.clear();
      revision.value++;
    }
    await _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_enabledKey, enabled)) {
        throw StateError('课程实时动态设置写入失败');
      }
      if (!enabled) await _invoke('deactivate');
    });
    if (enabled && account != null && epoch == _epoch) {
      await refresh(account, force: true);
    }
    revision.value++;
  }

  /// What the device can actually do, reported per capability instead of
  /// treating a successful interface call as a successful display.
  static Future<CourseLiveActivityStatus> status() async {
    if (!isSupported) return const CourseLiveActivityStatus();
    try {
      final raw = await _invoke('status');
      if (raw is! Map) return const CourseLiveActivityStatus();
      return CourseLiveActivityStatus(
        notifications: raw['notifications'] == true,
        exact: raw['exact'] == true,
        promoted: raw['promoted'] == true,
      );
    } catch (_) {
      return const CourseLiveActivityStatus();
    }
  }

  /// Rebuilds the plan from host-owned cached data. Never fetches campus data
  /// itself: [RecentScheduleRepository] is the single owner of that request.
  static Future<void> refresh(String account, {bool force = false}) async {
    if (_developerTest ||
        !isSupported ||
        account.isEmpty ||
        DemoDataService.instance.enabled ||
        !await isEnabled()) {
      return;
    }
    final epoch = _epoch;
    if (!await _accepted()) return;
    if (epoch != _epoch || await _currentAccount() != account) return;
    final checkedAt = _refreshStamp;
    final last = _refreshedAt[account];
    if (!force &&
        last != null &&
        checkedAt.difference(last) < const Duration(seconds: 30)) {
      // Native permission and channel state can change without new course
      // data. Ask for a local re-coordination instead of re-projecting.
      await _serial(() async {
        if (_account == account && epoch == _epoch) {
          await _invoke('reschedule');
        }
      });
      return;
    }
    final existing = _refreshBatches[account];
    if (existing != null) {
      // A forced call carries a course-data revision. Remember it so the pass
      // that is already running rebuilds once more with the newest data instead
      // of letting the stale projection become the final plan.
      if (force) _forceReprojection.add(account);
      return existing;
    }
    late final Future<void> batch;
    batch = _refresh(account, epoch).whenComplete(() {
      if (identical(_refreshBatches[account], batch)) {
        _refreshBatches.remove(account);
      }
    });
    _refreshBatches[account] = batch;
    return batch;
  }

  static Future<void> _refresh(String account, int epoch) async {
    var more = false;
    try {
      if (!await _activate(account, epoch)) return;
      var attempts = 0;
      while (true) {
        _forceReprojection.remove(account);
        await _project(account, epoch);
        if (epoch != _epoch) return;
        attempts++;
        if (!_forceReprojection.contains(account)) break;
        if (attempts >= _maxProjectionAttempts) {
          // Revisions kept arriving during the last projection. The pending
          // revision is NOT dropped: a follow-up batch rebuilds with it, so the
          // newest data always becomes the published plan.
          more = true;
          break;
        }
      }
      if (epoch == _epoch) _refreshedAt[account] = _refreshStamp;
    } catch (error) {
      AppLogger.warn('课程实时动态刷新失败 (${error.runtimeType})');
    } finally {
      _scheduleBoundaryRefresh();
      if (more) {
        // Keep the pending marker until the follow-up batch picks it up, and
        // start that batch directly so the marker cannot be missed while the
        // current one is still being torn down.
        scheduleMicrotask(() {
          if (epoch != _epoch) {
            _forceReprojection.remove(account);
            return;
          }
          unawaited(_refresh(account, epoch));
        });
      } else {
        _forceReprojection.remove(account);
      }
    }
  }

  /// Bound on projections inside one batch; further revisions start a new batch.
  static const int _maxProjectionAttempts = 3;

  /// Foreground-only coordination at phase boundaries and progress checkpoints.
  /// This local timer also works without exact-alarm access; it never fetches
  /// data or survives the process, and stops when the app leaves the foreground.
  static void _scheduleBoundaryRefresh() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    if (!_boundaryListenerAttached) {
      // The plan can change without a new projection (switch off, logout); the
      // listener only re-arms or cancels the local timer.
      revision.addListener(_onRevisionForBoundaries);
      _boundaryListenerAttached = true;
    }
    final plan = _latest;
    // Foreground only: leaving the foreground must stop the local coordination
    // so a device without the exact-alarm permission really does pause its
    // background reservations.
    if (plan == null || !isSupported || _owner == null || !_foreground) return;
    final now = _now;
    DateTime? nextBoundary;
    for (final course in plan.courses) {
      final boundary = courseLiveActivityNextUpdate(course, now);
      if (boundary != null &&
          (nextBoundary == null || boundary.isBefore(nextBoundary))) {
        nextBoundary = boundary;
      }
    }
    // A short guard keeps a timer from firing marginally before its instant and
    // making the native side schedule the same moment again.
    if (nextBoundary == null) return;
    final delay = nextBoundary.difference(now) + const Duration(seconds: 2);
    _boundaryTimer = Timer(delay, () => unawaited(_coordinateForegroundBoundary()));
  }

  /// Tracks the foreground state so the local boundary timer only runs while
  /// the app is actually in front.
  static void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (value) {
      // Coming back to the front re-coordinates immediately: stages may have
      // changed while the local timer was stopped.
      unawaited(_coordinateForegroundBoundary());
    } else {
      _boundaryTimer?.cancel();
      _boundaryTimer = null;
    }
  }

  static Future<void> _coordinateForegroundBoundary() async {
    if (!_foreground) return;
    final account = _account;
    if (account == null || _owner == null) return;
    if (!await _accepted() || await _currentAccount() != account) return;
    if (!await isEnabled()) return;
    await _serial(() async {
      if (_foreground && _account == account) await _invoke('reschedule');
    });
    // Re-arm from the projected plan; the native side re-derives the stage.
    _scheduleBoundaryRefresh();
  }

  /// Refresh guard used by the foreground lifecycle and timer hooks.
  static Future<void> refreshForCurrentAccount({bool force = false}) async {
    if (!isSupported || DemoDataService.instance.enabled) return;
    final account = await _currentAccount();
    if (account == null) return;
    await refresh(account, force: force);
  }

  static Future<bool> _activate(String account, int epoch) => _serial(() async {
    if (!await _isCurrent(account, epoch)) return false;
    if (_account == account && _owner != null && _generation != null) {
      return true;
    }
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    final records = _records(prefs);
    var record = records[account];
    if (record == null || record['owner'] is! String) {
      final random = Random.secure();
      final owner = List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      record = {'owner': owner};
      records[account] = record;
      if (!await _saveRecords(prefs, records)) {
        throw StateError('课程实时动态归属写入失败');
      }
    }
    if (!await _isCurrent(account, epoch)) return false;
    final owner = record['owner'] as String;
    final bound = debugBoundOwner ?? await _invoke('activatedOwner');
    // Only a *different* previous owner is a new lineage that must not be able
    // to republish anything. A first bind has nothing to clear, and re-attaching
    // the same owner after a process restart keeps the persisted plan and the
    // dismissal ledger, so an offline start or a re-opened app neither drops a
    // pending reservation nor resurrects a course the user already ended.
    if (bound != null && bound != owner) {
      await _invoke('deactivate');
      if (!await _isCurrent(account, epoch)) return false;
      _latest = null;
    } else {
      // Re-attaching after a process restart: load the persisted plan so a
      // partial projection can merge against it instead of overwriting it.
      _latest ??= CourseLiveActivityPlan.fromPayload(
        _decodePlannedPayload(await _invoke('plannedPayload')),
      );
    }
    final generation = await _invoke('activate', {'owner': owner});
    if (!await _isCurrent(account, epoch) || generation is! int) return false;
    _account = account;
    _owner = owner;
    _generation = generation;
    return true;
  });

  static Future<bool> _isCurrent(String account, int epoch) async =>
      !_developerTest &&
      epoch == _epoch &&
      await _accepted() &&
      await _currentAccount() == account &&
      epoch == _epoch;

  static Future<void> _project(String account, int epoch) async {
    final owner = _owner;
    final generation = _generation;
    if (owner == null || generation == null) return;
    final revision = ++_planRevision;
    final now = _now;
    final dates = courseLiveActivityBusinessDates(now);
    final repository = debugRepository ?? RecentScheduleRepository.instance;
    // The repository owns the cache TTL and the day-source precedence; the
    // shared loader below fills the days the ROOMIS window does not cover from
    // the academic timetable.
    if (await _canPublish(account, epoch, revision)) {
      await (debugReadWindow?.call(account) ?? repository.read(account));
    }
    if (!await _canPublish(account, epoch, revision)) return;
    final days = await (debugLoadDays?.call(account, dates, debugRepository) ??
        loadRecentScheduleDays(
          account,
          dates,
          repository: debugRepository,
        ));
    if (!await _canPublish(account, epoch, revision)) return;
    final outcome = projectCourseLiveActivityPlan(
      owner: owner,
      generation: generation,
      now: now,
      days: days,
      dates: dates,
    );
    final confirmed = <CourseLivePlanCourse>[
      if (outcome.plan != null) ...outcome.plan!.courses,
    ];
    final confirmedDates = _confirmedDates(days, dates);
    // A complete projection replaces the plan; a partial one is merged per date
    // so a date that is confirmed to be empty really drops its old courses while
    // the dates this pass could not resolve keep what the device already holds.
    // A complete projection replaces the plan; a partial one is merged per date
    // so a date that is confirmed to be empty really drops its old courses while
    // the dates this pass could not resolve keep what the device already holds.
    final CourseLiveActivityPlan? plan;
    final bool decisive;
    if (outcome.authoritative) {
      plan = outcome.plan;
      // An authoritative pass always acts, including the empty result that
      // revokes the plan.
      decisive = true;
    } else {
      final merged = mergeCourseLiveActivityPlan(
        previous: _latest,
        confirmed: confirmed,
        confirmedDates: confirmedDates,
        now: now,
        owner: owner,
        generation: generation,
      );
      if (merged.courses.isEmpty) {
        // Every date this pass confirmed is now empty, so nothing is left to
        // display. The unresolved dates had nothing valid on them either.
        plan = null;
        decisive = true;
      } else {
        plan = merged;
        decisive = false;
      }
    }
    await _replace(account, epoch, revision, plan, decisive: decisive);
  }

  /// Business dates this projection confirmed. A date inside the cached window
  /// is confirmed even when it has no courses.
  static Set<String> _confirmedDates(
    List<RecentScheduleDay> days,
    List<DateTime> dates,
  ) => {
    for (var index = 0; index < days.length && index < dates.length; index++)
      if (days[index].available) recentScheduleDate(dates[index]),
  };

  static Future<bool> _canPublish(
    String account,
    int epoch,
    int revision,
  ) async =>
      !_developerTest &&
      revision == _planRevision &&
      epoch == _epoch &&
      await _accepted() &&
      await _currentAccount() == account &&
      revision == _planRevision;

  /// A decisive projection always acts, including the empty result that revokes
  /// the plan. A partial projection only replaces what it confirmed: the dates
  /// it could not resolve keep whatever the device already holds, so a `null`
  /// plan with `decisive: false` leaves the native plan untouched.
  static Future<void> _replace(
    String account,
    int epoch,
    int revision,
    CourseLiveActivityPlan? plan, {
    required bool decisive,
  }) async {
    if (plan == null && !decisive) return;
    if (!await _canPublish(account, epoch, revision)) return;
    final payload = plan?.toPayload();
    await _serial(() async {
      if (!await _canPublish(account, epoch, revision)) return;
      if (payload != null) {
        await _invoke('replacePlan', payload);
        _latest = plan;
        return;
      }
      _latest = null;
      if (_owner != null && _generation != null) {
        await _invoke('clearPlan', {
          'owner': _owner,
          'generation': _generation,
        });
      }
    });
  }

  /// Final check before a notification tap may navigate. Ownership, account,
  /// switch and the native record must all still match.
  static Future<bool> acceptsLaunch(Map payload) async {
    if (!isSupported) return false;
    try {
      final account = await _currentAccount();
      if (account == null || !await _accepted() || !await isEnabled()) {
        return false;
      }
      final pref = _records(await SharedPreferences.getInstance())[account];
      if (pref?['owner'] != payload['owner']) return false;
      if (payload['targetAppId'] != courseLiveActivityTargetAppId) return false;
      final eventId = payload['eventId'];
      if (eventId is! String || eventId.trim().isEmpty) return false;
      return await _invoke('validateLaunch', payload) == true;
    } catch (_) {
      return false;
    }
  }

  /// Invalidates the current generation first, then rescinds the native
  /// notification, alarms and plan snapshot. Used for logout, account switch
  /// and agreement withdrawal. Device-global preferences such as the switch
  /// are preserved.
  static Future<void> clearAll() {
    _developerTest = false;
    _epoch++;
    _account = null;
    _owner = null;
    _generation = null;
    _planRevision++;
    _latest = null;
    _refreshedAt.clear();
    _refreshBatches.clear();
    revision.value++;
    return _serial(() async {
      await _invoke('deactivate');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_accountsKey);
        _initialization = null;
      } catch (_) {
        // Binding records are best-effort; the native side is already cleared.
      }
    });
  }

  static Map<String, Map<String, Object?>> _records(SharedPreferences prefs) =>
      _decodeRecords(prefs.getString(_accountsKey));

  /// Decodes the native persisted plan. The native side hands it back as JSON
  /// text because native JSONObject/JSONArray values are not platform-codec
  /// Map/List values.
  static Object? _decodePlannedPayload(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Map<String, Map<String, Object?>> _decodeRecords(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, Map<String, Object?>>{};
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          result[key] = value.cast<String, Object?>();
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<bool> _saveRecords(
    SharedPreferences prefs,
    Map<String, Map<String, Object?>> records,
  ) => prefs.setString(_accountsKey, jsonEncode(records));

  @visibleForTesting
  static void debugReset() {
    _epoch++;
    _tail = null;
    _initialization = null;
    _account = null;
    _owner = null;
    _generation = null;
    _planRevision++;
    _latest = null;
    _refreshBatches.clear();
    _refreshedAt.clear();
    _forceReprojection.clear();
    _foreground = true;
    _developerTest = false;
    _disposeBoundaryTimer();
    debugInvoke = null;
    debugAccount = null;
    debugAccepted = null;
    debugClock = null;
    debugRepository = null;
    debugReadWindow = null;
    debugBoundOwner = null;
    debugLoadDays = null;
  }

  static void _disposeBoundaryTimer() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    if (_boundaryListenerAttached) {
      revision.removeListener(_onRevisionForBoundaries);
      _boundaryListenerAttached = false;
    }
  }

  static void _onRevisionForBoundaries() {
    _scheduleBoundaryRefresh();
  }
}
