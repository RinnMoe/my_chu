import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class AppleWindowControlsMetrics {
  /// Absolute required insets from the window edge to the adapted top-chrome
  /// region. These values are not increments to add to an existing padding.
  final double leading;
  final double trailing;

  const AppleWindowControlsMetrics({this.leading = 0, this.trailing = 0})
    : assert(leading >= 0),
      assert(trailing >= 0);

  const AppleWindowControlsMetrics.zero() : leading = 0, trailing = 0;

  factory AppleWindowControlsMetrics.fromPlatform(Object? raw) {
    if (raw is! Map) return const AppleWindowControlsMetrics.zero();

    return AppleWindowControlsMetrics(
      leading: _readFiniteNonNegative(raw['leading']),
      trailing: _readFiniteNonNegative(raw['trailing']),
    );
  }

  static double _readFiniteNonNegative(Object? value) {
    final number = value is num ? value.toDouble() : 0.0;
    return number.isFinite && number >= 0 ? number : 0.0;
  }

  bool get isZero => leading == 0 && trailing == 0;

  @override
  bool operator ==(Object other) {
    return other is AppleWindowControlsMetrics &&
        other.leading == leading &&
        other.trailing == trailing;
  }

  @override
  int get hashCode => Object.hash(leading, trailing);

  @override
  String toString() =>
      'AppleWindowControlsMetrics(leading: $leading, trailing: $trailing)';
}

class AppleWindowControlsService {
  AppleWindowControlsService._();

  static const EventChannel _channel = EventChannel(
    'mychu/apple_window_controls',
  );

  /// Replaces the native stream in widget/unit tests.
  @visibleForTesting
  static Stream<AppleWindowControlsMetrics>? debugStream;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Stream<AppleWindowControlsMetrics> get metricsStream {
    final testStream = debugStream;
    if (testStream != null) return testStream;
    if (!isSupported) {
      return Stream<AppleWindowControlsMetrics>.value(
        const AppleWindowControlsMetrics.zero(),
      );
    }

    return _channel.receiveBroadcastStream().map(
      AppleWindowControlsMetrics.fromPlatform,
    );
  }
}
