/// Finite, non-identifying categories. Never construct these from error text.
enum FailureReason {
  unexpected('unexpected', 'unexpected'),
  businessRejected('business_rejected', 'application'),
  timeout('timeout', 'timeout'),
  dns('dns', 'network'),
  connection('connection', 'network'),
  tls('tls', 'tls'),
  httpTransport('http_transport', 'http_transport'),
  httpAuthentication('http_authentication', 'authentication'),
  httpNotFound('http_not_found', 'http_client'),
  httpRateLimited('http_rate_limited', 'http_client'),
  riskGuardPage('risk_guard_page', 'http_client'),
  httpClient('http_client', 'http_client'),
  httpServer('http_server', 'server'),
  authentication('authentication_required', 'authentication'),
  identityUnavailable('identity_unavailable', 'authentication'),
  sessionStale('session_stale', 'session'),
  sessionUnavailable('session_unavailable', 'session'),
  cookieRead('cookie_read_failed', 'session'),
  cookieWrite('cookie_write_failed', 'session'),
  cookieManagerReset('cookie_manager_reset', 'session'),
  malformedResponse('malformed_response', 'malformed_response'),
  loginFormChanged('login_form_changed', 'malformed_response'),
  recoveryUnconfirmed('recovery_unconfirmed', 'network_or_response'),
  platform('platform_failure', 'platform'),
  pluginUnavailable('plugin_unavailable', 'platform'),
  rendererCrashed('renderer_crashed', 'renderer_crashed'),
  rendererExited('renderer_exited', 'renderer_exited'),
  cancelled('request_cancelled', 'cancelled'),
  redirectLoop('redirect_loop', 'http_transport'),
  unsupportedResource('unsupported_resource', 'http_transport'),
  framework('framework_error', 'framework'),
  invalidState('invalid_state', 'application'),
  invalidArgument('invalid_argument', 'application'),
  typeMismatch('type_mismatch', 'application'),
  assertion('assertion_failed', 'application'),
  networkOrResponse('network_or_response', 'network_or_response');

  const FailureReason(this.key, this.kind);
  final String key;
  final String kind;
}

enum FailureStage {
  operation('operation'),
  request('request'),
  sessionPrepare('session_prepare'),
  mainFrame('main_frame'),
  sessionRecovery('session_recovery'),
  proxy('proxy'),
  runtime('runtime');

  const FailureStage(this.key);
  final String key;
}

/// Implement at the source when a generic StateError would lose the cause.
abstract interface class ClassifiedFailure {
  FailureReason get failureReason;
}

class ClassifiedStateError extends StateError implements ClassifiedFailure {
  ClassifiedStateError(this.failureReason, String message) : super(message);
  @override
  final FailureReason failureReason;
}

FailureReason? classifyHttpFailure(int? status) => switch (status ?? 0) {
  401 || 403 => FailureReason.httpAuthentication,
  404 => FailureReason.httpNotFound,
  429 => FailureReason.httpRateLimited,
  >= 500 && <= 599 => FailureReason.httpServer,
  >= 400 && <= 499 => FailureReason.httpClient,
  _ => null,
};
