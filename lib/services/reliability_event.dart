import 'app_log_event.dart';

/// A second, strict boundary: diagnostic text and arbitrary fields never enter
/// remote analytics. Only fixed identifiers and categories are projected.
class ReliabilityEvent {
  const ReliabilityEvent._(this.name, this.properties);

  final String name;
  final Map<String, String> properties;

  bool get isCompleteOperation =>
      name == 'operation_finished' && properties['coverage'] == 'complete';

  String get signature => '$name:${properties.values.join(':')}';

  bool get shouldThrottle =>
      name == 'runtime_fault' ||
      (name == 'operation_finished' && !isCompleteOperation);

  static ReliabilityEvent? fromLog(AppLogEvent event) {
    final operation = event.operation;
    // Interactive login is not a reliability operation being monitored.
    if (operation == UserOperationId.manualWebView) return null;

    if (operation != null &&
        (event is DiagnosticLogEvent ||
            event.code == 'user.operation.failed' ||
            event.code == 'user.operation.succeeded')) {
      final succeeded = event.code == 'user.operation.succeeded';
      return ReliabilityEvent._('operation_finished', {
        'operation': operation.key,
        'result': succeeded ? 'success' : 'failed',
        'failure_kind': succeeded ? 'none' : _failure(event),
        'coverage':
            event.fields['phase'] == 'complete' ? 'complete' : 'failure_only',
        if (event.fields['phase'] == 'complete')
          'duration_bucket': _durationBucket(event.fields['durationms']),
      });
    }

    final runtimeSource = switch (event.code) {
      'runtime.flutter.framework' => 'flutter',
      'runtime.platform.unhandled' => 'platform',
      'runtime.zone.unhandled' => 'zone',
      _ => null,
    };
    if (runtimeSource != null) {
      return ReliabilityEvent._('runtime_fault', {
        'source': runtimeSource,
        'failure_kind': _failure(event),
      });
    }

    final recovery = switch (event.code) {
      'identity.silent_login.succeeded' => ('identity', 'success', 'none'),
      'identity.silent_login.invalid_credential' => (
        'identity',
        'failed',
        'authentication',
      ),
      'identity.silent_login.captcha_required' => (
        'identity',
        'interaction_required',
        'none',
      ),
      // The existing outcome combines network and login-page errors; do not
      // incorrectly claim that it distinguishes timeout/TLS/response failures.
      'identity.silent_login.network_error' => (
        'identity',
        'failed',
        'network_or_response',
      ),
      // loadUrl accepted the recovered bootstrap; it is not proof that the
      // destination authenticated successfully. Keep that distinction visible.
      'webview.session.recovered' => ('webview', 'reload_requested', 'none'),
      'webview.session.recovery_failed' => (
        'webview',
        'failed',
        _failure(event),
      ),
      _ => null,
    };
    if (recovery == null) return null;
    return ReliabilityEvent._('recovery_finished', {
      'source': recovery.$1,
      'result': recovery.$2,
      'failure_kind': recovery.$3,
      if (recovery.$1 == 'webview' && operation != null)
        'operation': operation.key,
    });
  }

  static String _failure(AppLogEvent event) {
    if (event.renderProcessCrashed != null) {
      return event.renderProcessCrashed!
          ? 'renderer_crashed'
          : 'renderer_exited';
    }
    final status = event.statusCode;
    if (status == 401 || status == 403) return 'authentication';
    if (status != null && status >= 500 && status <= 599) return 'server';
    if (status != null && status >= 400 && status <= 499) return 'http_client';
    return switch (event.exceptionType) {
      'TimeoutException' => 'timeout',
      'SocketException' => 'network',
      'HandshakeException' || 'TlsException' => 'tls',
      'FormatException' => 'malformed_response',
      'HttpException' => 'http_transport',
      'PlatformException' || 'MissingPluginException' => 'platform',
      'AcademicAffairsAuthenticationException' ||
      'LoginExpiredException' => 'authentication',
      // Unknown types are deliberately not transmitted as property values.
      _ => 'unexpected',
    };
  }

  static String _durationBucket(Object? value) {
    if (value is! num || !value.isFinite || value < 0) return 'unknown';
    if (value < 1000) return 'under_1s';
    if (value < 3000) return '1_to_3s';
    if (value < 10000) return '3_to_10s';
    return 'over_10s';
  }
}
