import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'app_log_event.dart';
import 'logger_service.dart';

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
  }) {
    RuntimeErrorReporter.markRecorded(error);
    final event = DiagnosticLogEvent(
      timestamp: timestamp ?? DateTime.now(),
      operation: operation,
      exceptionType: error.runtimeType.toString(),
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
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

  bool get completed => _completed;

  void fail(
    Object error, {
    int? statusCode,
    bool? renderProcessCrashed,
    int? attempt,
  }) {
    if (_completed) return;
    _completed = true;
    _coordinator.recordFailure(
      operation,
      error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
    );
  }

  void succeed() {
    if (_completed) return;
    _completed = true;
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
  }) {
    diagnostics.recordFailure(
      operation: operation,
      error: error,
      statusCode: statusCode,
      renderProcessCrashed: renderProcessCrashed,
      attempt: attempt,
    );
  }

  void reset() => diagnostics.clear();
}
