import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'app_log_event.dart';
import 'logger_service.dart';
import 'failure_classifier.dart';

export 'failure_details.dart';

export 'app_log_event.dart'
    show DiagnosticLogEvent, UserOperationId, operationForAuthenticatedService;

/// Bounded diagnostics intended for optional user-submitted feedback.
///
/// The default instance is an adapter over the same in-memory event source used
/// by [AppLogger]. Tests and isolated coordinators may provide their own
/// bounded buffer.
class DiagnosticLogBuffer {
  DiagnosticLogBuffer({this.maxEvents = 500})
    : _buffer = AppLogBuffer(maxEntries: maxEvents),
      _shared = false;

  DiagnosticLogBuffer._shared()
    : maxEvents = sharedAppLogBuffer.maxEntries,
      _buffer = sharedAppLogBuffer,
      _shared = true;

  final int maxEvents;
  final AppLogBuffer _buffer;
  final bool _shared;

  UnmodifiableListView<AppLogEvent> get events => snapshotEvents();

  UnmodifiableListView<AppLogEvent> snapshotEvents({int? maxEvents}) {
    return UnmodifiableListView<AppLogEvent>(
      _buffer.snapshot(maxEntries: maxEvents ?? this.maxEvents),
    );
  }

  void recordFailure({
    required UserOperationId operation,
    required Object error,
    DateTime? timestamp,
    int? statusCode,
    bool? renderProcessCrashed,
    int? attempt,
    bool completeAttempt = false,
    Duration? duration,
    FailureStage stage = FailureStage.operation,
  }) {
    RuntimeErrorReporter.markRecorded(error);
    final event = DiagnosticLogEvent(
      timestamp: timestamp ?? DateTime.now(),
      operation: operation,
      exceptionType: error.runtimeType.toString(),
      failureReason: classifyFailure(
        error,
        statusCode: statusCode,
        renderProcessCrashed: renderProcessCrashed,
      ),
      failureStage: stage,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
      fields: {
        if (completeAttempt) 'phase': 'complete',
        if (duration != null) 'durationms': duration.inMilliseconds,
      },
    );
    if (_shared) {
      AppLogger.record(event);
    } else {
      _buffer.add(event);
    }
  }

  void clear([UserOperationId? operation]) {
    if (operation == null) {
      _buffer.clear();
      if (_shared) RuntimeErrorReporter.clearSeen();
      return;
    }
    _buffer.removeWhere((event) => event.operation == operation);
  }

  void addListener(VoidCallback listener) => _buffer.addListener(listener);

  void removeListener(VoidCallback listener) =>
      _buffer.removeListener(listener);
}

final DiagnosticLogBuffer sharedDiagnosticLogBuffer =
    DiagnosticLogBuffer._shared();

class ErrorFeedbackAttempt {
  ErrorFeedbackAttempt(this._coordinator, this.operation);

  final ErrorFeedbackCoordinator _coordinator;
  final UserOperationId operation;
  bool _completed = false;
  final Stopwatch _stopwatch = Stopwatch()..start();

  bool get completed => _completed;

  void fail(
    Object error, {
    int? statusCode,
    bool? renderProcessCrashed,
    int? attempt,
    FailureStage stage = FailureStage.operation,
  }) {
    if (_completed) return;
    _completed = true;
    _stopwatch.stop();
    _coordinator.recordFailure(
      operation,
      error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
      stage: stage,
      completeAttempt: true,
      duration: _stopwatch.elapsed,
    );
  }

  void succeed() {
    if (_completed) return;
    _completed = true;
    _stopwatch.stop();
    if (_coordinator.diagnostics._shared) {
      AppLogger.event(
        level: 'INFO',
        code: 'user.operation.succeeded',
        message: '用户操作完成',
        operation: operation,
        fields: {
          'phase': 'complete',
          'durationms': _stopwatch.elapsedMilliseconds,
        },
      );
    }
  }
}

/// Routes safe user-operation failures into the diagnostic event buffer.
class ErrorFeedbackCoordinator {
  ErrorFeedbackCoordinator({DiagnosticLogBuffer? diagnostics})
    : diagnostics = diagnostics ?? DiagnosticLogBuffer();

  static final ErrorFeedbackCoordinator shared = ErrorFeedbackCoordinator(
    diagnostics: sharedDiagnosticLogBuffer,
  );

  final DiagnosticLogBuffer diagnostics;

  ErrorFeedbackAttempt begin(UserOperationId operation) =>
      ErrorFeedbackAttempt(this, operation);

  void recordFailure(
    UserOperationId operation,
    Object error, {
    int? statusCode,
    bool? renderProcessCrashed,
    int? attempt,
    bool completeAttempt = false,
    Duration? duration,
    FailureStage stage = FailureStage.operation,
  }) {
    diagnostics.recordFailure(
      operation: operation,
      error: error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
      completeAttempt: completeAttempt,
      duration: duration,
      stage: stage,
    );
  }

  void reset() => diagnostics.clear();
}
