import 'dart:async';
import 'package:flutter/foundation.dart';
import '../failure_classifier.dart';
import '../usage_analytics_service.dart';
import '../reliability_event.dart';
import 'logger.dart';

class RuntimeErrorReporter {
  RuntimeErrorReporter._();
  static bool _installed = false;
  static final List<int> _reported = [];
  static void Function(FlutterErrorDetails)? _previousFlutter;
  static bool Function(Object, StackTrace)? _previousPlatform;
  static Zone? _previousZone;

  static void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutter = FlutterError.onError;
    _previousPlatform = PlatformDispatcher.instance.onError;
    _previousZone = Zone.current.parent;
    FlutterError.onError = handleFlutterError;
    PlatformDispatcher.instance.onError = handlePlatformError;
  }

  static void handleFlutterError(FlutterErrorDetails details) {
    _record(details.exception, details.stack ?? StackTrace.current, 'flutter');
    if (kDebugMode) _previousFlutter?.call(details);
  }

  static bool handlePlatformError(Object error, StackTrace stack) {
    _record(error, stack, 'platform', fatal: true);
    if (kDebugMode) {
      _previousPlatform?.call(error, stack);
    }
    return true;
  }

  static void handleZoneError(Object error, StackTrace stack) {
    _record(error, stack, 'zone', fatal: true);
    if (kDebugMode && _installed) {
      _previousZone?.handleUncaughtError(error, stack);
    }
  }

  static void _record(
    Object error,
    StackTrace stack,
    String source, {
    bool fatal = false,
  }) {
    final identity = identityHashCode(error);
    if (!_reported.contains(identity)) {
      _reported.add(identity);
      if (_reported.length > 32) _reported.removeAt(0);
      UsageAnalyticsService.recordReliability(
        ReliabilityEvent.runtime(source, classifyFailure(error)),
      );
    }
    AppLogger.error(
      error,
      stackTrace: stack,
      fatal: fatal,
      context: 'Dart $source',
    );
  }

  static void clearSeen() => _reported.clear();
}
