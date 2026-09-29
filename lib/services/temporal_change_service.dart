import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../capabilities/east8_time.dart';

class TemporalChangeService with WidgetsBindingObserver {
  static const _channel = MethodChannel('mychu/temporal_changes');
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static DateTime _lastDay = _day(east8Now());
  static Duration _lastOffset = DateTime.now().timeZoneOffset;
  static bool _initialized = false;
  static Timer? _midnightTimer;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(TemporalChangeService());
    _scheduleMidnightTimer();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') {
        _publishIfChanged(force: true);
        _scheduleMidnightTimer();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _publishIfChanged();
      _scheduleMidnightTimer();
    }
  }

  static void _publishIfChanged({bool force = false}) {
    final day = _day(east8Now());
    final offset = DateTime.now().timeZoneOffset;
    if (!force && day == _lastDay && offset == _lastOffset) return;
    _lastDay = day;
    _lastOffset = offset;
    revision.value++;
  }

  /// Publishes a date revision even when the process remains alive overnight.
  ///
  /// The native temporal-change receiver covers device date/time changes, but
  /// a foreground Flutter process may not receive a platform broadcast at the
  /// normal midnight boundary.  This short-lived one-shot timer is only a
  /// local UI invalidation; it does not refresh network credentials or data.
  static void _scheduleMidnightTimer() {
    _midnightTimer?.cancel();
    final now = east8Now();
    final next = DateTime(now.year, now.month, now.day + 1);
    // `east8Now` is a wall-clock value, so convert both endpoints to UTC
    // instants before computing the delay. This keeps the timer correct on a
    // device whose local timezone crosses a DST transition overnight.
    final delay = east8WallClockToUtcInstant(next).difference(
      DateTime.now().toUtc(),
    );
    _midnightTimer = Timer(
      delay.isNegative || delay == Duration.zero
          ? const Duration(milliseconds: 1)
          : delay,
      () {
        _publishIfChanged(force: true);
        _scheduleMidnightTimer();
      },
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
