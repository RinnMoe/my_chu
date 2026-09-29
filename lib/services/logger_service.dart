import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, VoidCallback, kDebugMode;

import '../capabilities/east8_time.dart';
import 'app_log_event.dart';

export 'app_log_event.dart'
    show
        AppLogEvent,
        DiagnosticLogEvent,
        LogEntry,
        UserOperationId,
        operationForAuthenticatedService;

/// Shared structured runtime log. The same event buffer powers the Debug log
/// page and the public diagnostics export.
class AppLogger {
  static List<AppLogEvent> get entries => sharedAppLogBuffer.entries;

  static void info(String message) => _legacy('INFO', message);

  static void warn(String message) => _legacy('WARN', message);

  static void error(String message) => _legacy('ERROR', message);

  /// Records a failure without allowing exception text or stack traces to
  /// cross the diagnostics boundary. [AppLogEvent] performs a second
  /// allow-list/sanitization pass for the message and fields.
  static void recordSafeFailure({
    required String code,
    required String message,
    required Object error,
    String? domain,
    String level = 'ERROR',
    UserOperationId? operation,
    Map<String, Object?> fields = const {},
    int? statusCode,
    bool? renderProcessCrashed,
    int? attempt,
  }) {
    // A feature-level catch may record the same object before it escapes into
    // one of the process-wide handlers. Mark it first so the global fallback
    // does not emit a second diagnostics event for that failure.
    RuntimeErrorReporter.markRecorded(error);
    event(
      level: level,
      code: code,
      message: message,
      domain: domain,
      operation: operation,
      fields: fields,
      exceptionType: error.runtimeType.toString(),
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
    );
  }

  static void event({
    required String level,
    required String code,
    required String message,
    Map<String, Object?> fields = const {},
    UserOperationId? operation,
    String? domain,
    String? exceptionType,
    int? statusCode,
    bool? renderProcessCrashed,
    int? attempt,
  }) {
    _add(
      AppLogEvent(
        timestamp: east8Now(),
        level: _normalizeLevel(level),
        code: code,
        message: message,
        fields: fields,
        operation: operation,
        domain: domain,
        exceptionType: exceptionType,
        statusCode: statusCode,
        renderProcessCrashed: renderProcessCrashed,
        attempt: attempt,
      ),
    );
  }

  static void record(AppLogEvent event) => _add(event);

  static void _legacy(String level, String message) {
    _add(
      AppLogEvent(
        timestamp: east8Now(),
        level: level,
        code: 'legacy.${level.toLowerCase()}',
        message: message,
      ),
    );
  }

  static void _add(AppLogEvent event) {
    if (kDebugMode) {
      developer.log(
        event.toSafeLine(),
        name: 'MyCHU',
        level: _logLevel(event.level),
      );
    }
    sharedAppLogBuffer.add(event);
  }

  static void clear() {
    sharedAppLogBuffer.clear();
    RuntimeErrorReporter.clearSeen();
  }

  static void addListener(VoidCallback listener) =>
      sharedAppLogBuffer.addListener(listener);

  static void removeListener(VoidCallback listener) =>
      sharedAppLogBuffer.removeListener(listener);

  static String _normalizeLevel(String level) => switch (level.toUpperCase()) {
    'ERROR' => 'ERROR',
    'WARN' || 'WARNING' => 'WARN',
    _ => 'INFO',
  };

  static int _logLevel(String level) => switch (level) {
    'ERROR' => 1000,
    'WARN' => 900,
    _ => 800,
  };
}

/// Installs privacy-preserving handlers for errors that escape a feature's
/// normal async boundary. Each error object is recorded at most once across
/// the Flutter, platform and Zone handlers, while the bounded identity set
/// avoids retaining an unbounded number of failed objects.
class RuntimeErrorReporter {
  static const _maxSeenErrors = 32;
  static final List<Object> _seenErrors = <Object>[];
  static bool _installed = false;
  static void Function(FlutterErrorDetails)? _previousFlutterErrorHandler;
  static bool Function(Object, StackTrace)? _previousPlatformErrorHandler;
  static Zone? _previousZone;

  static void install() {
    if (_installed) return;
    // Capture the handlers installed by Flutter, the embedder, or another
    // integration before installing the safe boundary. Release builds keep
    // the boundary terminal; Debug forwards to these handlers below.
    _previousFlutterErrorHandler = FlutterError.onError;
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    _previousZone = Zone.current.parent;
    _installed = true;
    FlutterError.onError = handleFlutterError;
    PlatformDispatcher.instance.onError = handlePlatformError;
  }

  static void handleFlutterError(FlutterErrorDetails details) {
    _recordOnce(
      details.exception,
      code: 'runtime.flutter.framework',
      message: 'Flutter 框架异常',
      domain: 'runtime',
    );
    _forwardFlutterError(details);
  }

  static bool handlePlatformError(Object error, StackTrace stackTrace) {
    _recordOnce(
      error,
      code: 'runtime.platform.unhandled',
      message: '平台异步异常',
      domain: 'runtime',
    );
    if (kDebugMode) {
      if (_installed) {
        final previous = _previousPlatformErrorHandler;
        if (previous != null) return previous(error, stackTrace);
      }
      // Returning false preserves the engine's default platform error path
      // when no application handler was installed before MyCHU.
      return false;
    }
    return true;
  }

  static void handleZoneError(Object error, StackTrace stackTrace) {
    _recordOnce(
      error,
      code: 'runtime.zone.unhandled',
      message: '未处理的异步异常',
      domain: 'runtime',
    );
    if (kDebugMode && _installed) {
      _previousZone?.handleUncaughtError(error, stackTrace);
    }
  }

  /// Marks a failure that was already recorded by a feature-level boundary.
  /// This intentionally does not emit an event; it only shares the bounded
  /// identity set with the process-wide fallbacks.
  static void markRecorded(Object error) {
    _remember(error);
  }

  /// Clears deduplication state together with an explicit diagnostics reset.
  static void clearSeen() => _seenErrors.clear();

  static void _recordOnce(
    Object error, {
    required String code,
    required String message,
    required String domain,
  }) {
    if (!_remember(error)) return;
    AppLogger.recordSafeFailure(
      code: code,
      message: message,
      error: error,
      domain: domain,
    );
  }

  static bool _remember(Object error) {
    if (_seenErrors.any((seen) => identical(seen, error))) return false;
    _seenErrors.add(error);
    if (_seenErrors.length > _maxSeenErrors) _seenErrors.removeAt(0);
    return true;
  }

  static void _forwardFlutterError(FlutterErrorDetails details) {
    if (!kDebugMode || !_installed) return;
    final previous = _previousFlutterErrorHandler;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }
}
