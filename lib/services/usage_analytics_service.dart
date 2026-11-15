import 'dart:async';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:aptabase_flutter/storage_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_remote_services_service.dart';
import 'build_info.dart';
import 'logging/logger.dart';
import 'privacy_agreement_service.dart';
import 'reliability_event.dart';
import 'failure_classifier.dart';
import 'failure_details.dart';

/// Aptabase storage scoped to MyCHU's own analytics queue keys.
///
/// The SDK's default SharedPreferences manager imports every `aptabase_` key
/// from the whole app. This manager namespaces every persisted event and never
/// reads unrelated preferences. Revocation writes a purge marker before
/// deleting queued events so a later process cannot replay pre-revocation data.
class AptabaseAnalyticsStorageManager extends StorageManager {
  static const maxQueuedEvents = 200;
  static const String eventKeyPrefix = 'mychu.analytics.aptabase.event.';
  static const String _revocationPendingKey =
      'mychu.analytics.aptabase.revocation_pending';

  final Map<String, String> _events = <String, String>{};
  final Set<Future<void>> _pendingWrites = <Future<void>>{};
  bool _enabled = false;
  int _generation = 0;
  int _sequence = 0;
  Future<void> _persistenceTail = Future<void>.value();

  bool get isEnabled => _enabled;

  @override
  Future<void> init() async {
    final generation = _generation;
    _enabled = false;
    _events.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final purgeOldEvents = prefs.getBool(_revocationPendingKey) == true;
      final storedKeys = prefs
          .getKeys()
          .where((key) => key.startsWith(eventKeyPrefix))
          .toList(growable: false);
      for (final storedKey in storedKeys) {
        if (purgeOldEvents) {
          await prefs.remove(storedKey);
          continue;
        }
        final value = prefs.get(storedKey);
        if (value is String) {
          _events[storedKey.substring(eventKeyPrefix.length)] = value;
        }
      }
      while (_events.length > maxQueuedEvents) {
        final key = _events.keys.first;
        _events.remove(key);
        await prefs.remove('$eventKeyPrefix$key');
      }
      if (purgeOldEvents) await prefs.remove(_revocationPendingKey);
    } catch (error, stackTrace) {
      _events.clear();
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: 'Aptabase 队列读取失败',
      );
    }
    // Keep the in-memory queue usable if local persistence is unavailable.
    _enabled = generation == _generation;
  }

  @override
  Future<Iterable<MapEntry<String, String>>> getItems(int length) async {
    if (!_enabled || length <= 0) return const <MapEntry<String, String>>[];
    return _events.entries.take(length).toList(growable: false);
  }

  @override
  Future<void> addEvent(String key, String event) async {
    if (!_enabled || key.isEmpty) return;
    // SDK keys contain milliseconds and event name; bursts can collide.
    final originalKey = key;
    while (_events.containsKey(key)) {
      key = '$originalKey.${++_sequence}';
    }
    _events[key] = event;
    final evicted = <String>[];
    while (_events.length > maxQueuedEvents) {
      final oldest = _events.keys.first;
      _events.remove(oldest);
      evicted.add(oldest);
    }
    final write = _persistenceTail.then(
      (_) => _persistEvent(key, event, evicted),
    );
    _persistenceTail = write;
    _pendingWrites.add(write);
    try {
      await write;
    } finally {
      _pendingWrites.remove(write);
    }
  }

  Future<void> _persistEvent(
    String key,
    String event,
    List<String> evicted,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final oldKey in evicted) {
        await prefs.remove('$eventKeyPrefix$oldKey');
      }
      await prefs.setString('$eventKeyPrefix$key', event);
    } catch (error, stackTrace) {
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: 'Aptabase 队列写入失败',
      );
    }
  }

  @override
  Future<void> deleteEvents(Set<String> keys) async {
    if (keys.isEmpty) return;
    final ownedKeys = keys.where(_events.containsKey).toSet();
    _events.removeWhere((key, _) => ownedKeys.contains(key));
    if (ownedKeys.isEmpty) return;
    await Future.wait(List<Future<void>>.of(_pendingWrites));
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in ownedKeys) {
        await prefs.remove('$eventKeyPrefix$key');
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: 'Aptabase 队列清理失败',
      );
    }
  }

  /// Stops new queue access before clearing queued events and the on-disk keys.
  Future<void> disableAndClear() async {
    _generation++;
    _enabled = false;
    _events.clear();
    final prefs = await SharedPreferences.getInstance();
    final markerSaved = await prefs.setBool(_revocationPendingKey, true);
    Object? cleanupFailure;
    if (!markerSaved) cleanupFailure = StateError('无法保存队列清理标记');
    await Future.wait(List<Future<void>>.of(_pendingWrites));
    final ownedKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(eventKeyPrefix))
        .toList(growable: false);
    for (final key in ownedKeys) {
      try {
        final removed = await prefs.remove(key);
        if (!removed && prefs.containsKey(key)) {
          cleanupFailure ??= StateError('无法清除 Aptabase 队列');
        }
      } catch (error, stackTrace) {
        AppLogger.error(
          error,
          stackTrace: stackTrace,
          context: '清理 Aptabase 队列',
        );
        cleanupFailure ??= error;
      }
    }
    if (cleanupFailure != null) throw cleanupFailure;
  }
}

/// Narrow SDK boundary so the gate and queue behavior can be tested without
/// initializing Aptabase's process-wide static singleton.
abstract interface class AptabaseGateway {
  Future<void> initialize(
    String appKey,
    InitOptions options,
    StorageManager storage,
  );

  Future<void> trackEvent(String eventName, [Map<String, dynamic>? properties]);
}

class _SdkAptabaseGateway implements AptabaseGateway {
  const _SdkAptabaseGateway();

  @override
  Future<void> initialize(
    String appKey,
    InitOptions options,
    StorageManager storage,
  ) => Aptabase.init(appKey, options, storage);

  @override
  Future<void> trackEvent(
    String eventName, [
    Map<String, dynamic>? properties,
  ]) => Aptabase.instance.trackEvent(eventName, properties);
}

/// Owns the Aptabase runtime behind the application remote-services switch.
class UsageAnalyticsService {
  UsageAnalyticsService._();

  static const String appKey = 'A-SH-6779463479';
  static const String host = 'https://aptabase.rinn.moe';

  static AptabaseGateway _gateway = const _SdkAptabaseGateway();
  static AptabaseAnalyticsStorageManager _storage =
      AptabaseAnalyticsStorageManager();
  static bool _initialized = false;
  static bool _startupEventAttempted = false;
  static Future<void>? _initialization;
  static BuildInfo? _activeBuild;
  static int _generation = 0;
  static int _pendingEvents = 0;
  static final Map<String, DateTime> _recentFaults = {};
  static final Set<Future<void>> _pendingSdkEvents = {};

  @visibleForTesting
  static void Function(ReliabilityEvent)? debugObserver;

  static bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> disableAndClear() async {
    _generation++;

    _recentFaults.clear();
    await _storage.disableAndClear();
    // SDK trackEvent awaits system properties before reaching storage. Wait
    // while storage is disabled so a rapid re-enable cannot accept old events.
    try {
      await Future.wait(List<Future<void>>.of(_pendingSdkEvents));
    } on Object catch (error, stack) {
      AppLogger.error(error, stackTrace: stack, context: '等待 Aptabase 待处理事件结束');
    }
  }

  static Future<void> initializeIfEnabled() =>
      _initializeIfAllowed(BuildInfo.current);

  @visibleForTesting
  static Future<void> initializeForTest(BuildInfo buildInfo) =>
      _initializeIfAllowed(buildInfo);

  static Future<void> _initializeIfAllowed(BuildInfo buildInfo) {
    if (!buildInfo.allowAnalytics || !_supportedPlatform) {
      return Future<void>.value();
    }
    final activeInitialization = _initialization;
    if (activeInitialization != null) return activeInitialization;

    final initialization = _initializeIfEnabled(buildInfo);
    _initialization = initialization;
    return initialization.whenComplete(() {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    });
  }

  static Future<void> _initializeIfEnabled(BuildInfo buildInfo) async {
    final generation = _generation;
    try {
      if (!await _canRun(buildInfo)) return;
      if (generation != _generation) return;
      if (_initialized) {
        if (!_storage.isEnabled) await _storage.init();
        if (!await _canRun(buildInfo) || generation != _generation) {
          await _storage.disableAndClear();
          return;
        }
        _activeBuild = buildInfo;

        return;
      }
      await _gateway.initialize(
        appKey,
        const InitOptions(host: host),
        _storage,
      );
      if (!await _canRun(buildInfo) || generation != _generation) {
        await _storage.disableAndClear();
        return;
      }
      _initialized = true;
      _activeBuild = buildInfo;

      if (_startupEventAttempted) return;
      _startupEventAttempted = true;
      try {
        unawaited(
          _trackSdkEvent('app_started').then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              AppLogger.error(error, stackTrace: stackTrace);
            },
          ),
        );
      } catch (error, stackTrace) {
        AppLogger.error(error, stackTrace: stackTrace);
      }
    } catch (error, stackTrace) {
      // Initialization failures do not delay startup; a later call may retry.
      AppLogger.error(error, stackTrace: stackTrace);
    }
  }

  static Future<bool> _canRun(BuildInfo buildInfo) async {
    if (!buildInfo.allowAnalytics || !_supportedPlatform) return false;
    if (!await PrivacyAgreementService.isAccepted()) return false;
    return AppRemoteServicesService.isEnabled();
  }

  static AnalyticsOperation beginOperation(UserOperationId operation) =>
      AnalyticsOperation(operation);

  static void recordOperation(
    UserOperationId operation, {
    required String result,
    FailureReason? reason,
    FailureStage stage = FailureStage.operation,
    Duration? duration,
    bool complete = false,
  }) => recordReliability(
    ReliabilityEvent.operation(
      operation,
      result: result,
      reason: reason,
      stage: stage,
      duration: duration,
      complete: complete,
    ),
  );

  static void recordReliability(ReliabilityEvent? event) {
    if (event == null) return;
    debugObserver?.call(event);
    if (!_initialized || !_storage.isEnabled || _pendingEvents >= 32) return;
    final generation = _generation;
    _pendingEvents++;
    unawaited(
      _recordReliability(
        event,
        generation,
      ).whenComplete(() => _pendingEvents--),
    );
  }

  static Future<void> _recordReliability(
    ReliabilityEvent event,
    int generation,
  ) async {
    try {
      final build = _activeBuild;
      if (build == null || !await _canRun(build)) return;
      if (generation != _generation || !_storage.isEnabled) return;
      // Complete operations are not throttled, so successes and failures have
      // the same observation policy. Repeated standalone faults are limited.
      if (event.shouldThrottle) {
        final now = DateTime.now();
        _recentFaults.removeWhere(
          (_, time) => now.difference(time) >= const Duration(minutes: 1),
        );
        if (_recentFaults.containsKey(event.signature)) return;
        if (_recentFaults.length >= 128) return;
        _recentFaults[event.signature] = now;
      }
      await _trackSdkEvent(event.name, event.properties);
    } on Object catch (error, stack) {
      // Raw SDK failures stay in the local error log.
      AppLogger.error(error, stackTrace: stack, context: 'Aptabase 事件处理失败');
    }
  }

  static Future<void> _trackSdkEvent(
    String name, [
    Map<String, dynamic>? properties,
  ]) {
    final future = _gateway.trackEvent(name, properties);
    _pendingSdkEvents.add(future);
    return future.whenComplete(() => _pendingSdkEvents.remove(future));
  }

  @visibleForTesting
  static AptabaseAnalyticsStorageManager get storageForTest => _storage;

  @visibleForTesting
  static void resetForTest({AptabaseGateway? gateway}) {
    debugObserver = null;
    _initialized = false;
    _startupEventAttempted = false;
    _initialization = null;
    _generation++;
    _activeBuild = null;
    _recentFaults.clear();

    _storage = AptabaseAnalyticsStorageManager();
    _gateway = gateway ?? const _SdkAptabaseGateway();
  }
}

/// Records one terminal analytics outcome per business operation.
class AnalyticsOperation {
  AnalyticsOperation(this.operation);
  final UserOperationId operation;
  final Stopwatch _watch = Stopwatch()..start();
  bool _finished = false;
  bool get isFinished => _finished;
  void succeed() => _finish('success');
  void cancel() => _finish('cancelled', reason: FailureReason.cancelled);
  void fail(
    Object error, {
    int? statusCode,
    bool? renderProcessCrashed,
    FailureStage stage = FailureStage.operation,
  }) {
    final reason = classifyFailure(
      error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
    );
    _finish(
      reason == FailureReason.cancelled || reason == FailureReason.sessionStale
          ? 'cancelled'
          : 'failed',
      reason: reason,
      stage: stage,
    );
  }

  void _finish(
    String result, {
    FailureReason? reason,
    FailureStage stage = FailureStage.operation,
  }) {
    if (_finished) return;
    _finished = true;
    _watch.stop();
    UsageAnalyticsService.recordOperation(
      operation,
      result: result,
      reason: reason,
      stage: stage,
      duration: _watch.elapsed,
      complete: true,
    );
  }
}
