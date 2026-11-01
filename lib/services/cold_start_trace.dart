import 'dart:async';

import 'package:flutter/foundation.dart';

import 'logger_service.dart';

/// Debug-only cold-start summary.
///
/// One structured event per process start is enough to tell a healthy start
/// from a session-recovery storm. The trace is a no-op outside debug builds
/// and only records counts, outcome names and durations: never account keys,
/// hosts, URLs or business content.
class ColdStartTrace {
  ColdStartTrace._();

  static const _settleDelay = Duration(seconds: 3);
  static const _maxWait = Duration(seconds: 20);

  static final Stopwatch _clock = Stopwatch();
  static bool _enabled = kDebugMode;
  static bool _started = false;
  static bool _flushed = false;
  static Timer? _settleTimer;
  static Timer? _maxTimer;

  static String? _probe;
  static String? _silentLogin;
  static final Set<String> _exchangedServices = <String>{};
  static int _exchanges = 0;
  static int _stale = 0;
  static int _requests = 0;
  static int _requestFailures = 0;
  static int _homeReadyMs = -1;

  /// Starts the cold-start clock and guarantees a summary even when the home
  /// page never reaches a ready state.
  static void markLaunch() {
    if (!_enabled) return;
    _started = true;
    _clock
      ..reset()
      ..start();
    _maxTimer?.cancel();
    _maxTimer = Timer(_maxWait, flush);
  }

  /// Records the first unified-identity probe outcome of this process.
  static void probeResult(String status) {
    if (!_enabled) return;
    _probe ??= status;
  }

  /// Records the first silent re-login outcome of this process.
  static void silentLogin(String outcome) {
    if (!_enabled) return;
    _silentLogin ??= outcome;
  }

  /// Records one committed service credential exchange.
  static void exchange(String serviceId) {
    if (!_enabled) return;
    _exchanges++;
    _exchangedServices.add(serviceId);
  }

  /// Records a response discarded because its session generation was replaced.
  static void staleDiscard() {
    if (_enabled) _stale++;
  }

  /// Counts one completed HTTP exchange, including a final non-200 response.
  ///
  /// [requestFailure] counts thrown request errors, so a non-200 response that
  /// is surfaced as an exception appears in both counters: `requests` is the
  /// exchange count and `failures` is the error count.
  static void requestSucceeded() {
    if (_enabled) _requests++;
  }

  static void requestFailure() {
    if (_enabled) _requestFailures++;
  }

  /// Marks the first home snapshot. The summary is emitted after a short settle
  /// window so trailing background requests are included.
  static void homeReady() {
    if (!_enabled || !_started || _homeReadyMs >= 0) return;
    _homeReadyMs = _clock.elapsedMilliseconds;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, flush);
  }

  /// Emits the single summary event for this process. Later calls are ignored.
  ///
  /// A process that exits before the 3s settle window or the 20s ceiling cannot
  /// emit anything; "one per process" assumes the app lived past one of them.
  static void flush() {
    if (!_enabled || !_started || _flushed) return;
    _flushed = true;
    _settleTimer?.cancel();
    _maxTimer?.cancel();
    final services = _exchangedServices.toList()..sort();
    final summary =
        'probe=${_probe ?? 'none'} silent=${_silentLogin ?? 'none'} '
        'exchanges=$_exchanges stale=$_stale requests=$_requests '
        'failures=$_requestFailures homeready=${_homeReadyMs}ms '
        'services=${services.join(',')}';
    // `developer.log` only reaches a host attached to the VM service, so a
    // plain debug build needs one console line to make the summary visible in
    // `adb logcat`.
    // ignore: avoid_print
    print('MyCHU cold_start $summary');
    AppLogger.event(
      level: 'INFO',
      code: 'startup.cold_start',
      message: '冷启动摘要',
      domain: 'startup',
      fields: {
        'probe': _probe ?? 'none',
        'silentlogin': _silentLogin ?? 'none',
        'exchanges': _exchanges,
        'stale': _stale,
        'requests': _requests,
        'failures': _requestFailures,
        'homereadyms': _homeReadyMs,
        'service': services.join(','),
      },
    );
  }

  /// Resets the trace between tests. [enabled] overrides the debug gate so the
  /// release no-op path can be exercised; it defaults to [kDebugMode].
  @visibleForTesting
  static void debugReset({bool? enabled}) {
    _clock
      ..stop()
      ..reset();
    _enabled = enabled ?? kDebugMode;
    _started = false;
    _flushed = false;
    _settleTimer?.cancel();
    _maxTimer?.cancel();
    _settleTimer = null;
    _maxTimer = null;
    _probe = null;
    _silentLogin = null;
    _exchangedServices.clear();
    _exchanges = 0;
    _stale = 0;
    _requests = 0;
    _requestFailures = 0;
    _homeReadyMs = -1;
  }
}
