import 'campus_service_id.dart';

/// Authentication policy declared by a campus service definition.
sealed class AuthenticationPolicy {
  const AuthenticationPolicy();
}

class ChdIdentityProvider {
  final String id;
  final List<String> hosts;

  const ChdIdentityProvider({
    this.id = 'chd-identity',
    this.hosts = const ['ids.chd.edu.cn', 'identity.chd.edu.cn'],
  });

  bool owns(Uri uri) =>
      hosts.any((host) => host.toLowerCase() == uri.host.toLowerCase());

  bool isLoginUri(Uri uri) {
    if (!owns(uri)) return false;
    return uri.path.contains('/authserver/login') ||
        uri.path.contains('/protocol/openid-connect/') ||
        uri.path.contains('/auth/realms/');
  }
}

class FederatedAuthentication extends AuthenticationPolicy {
  final ChdIdentityProvider provider;

  const FederatedAuthentication(this.provider);
}

class PublicAuthentication extends AuthenticationPolicy {
  const PublicAuthentication();
}

/// Uses the credential already saved for the unified identity to complete a
/// service-owned login form. The password remains inside the host
/// authentication coordinator and never crosses the feature boundary.
class SavedIdentityPasswordAuthentication extends AuthenticationPolicy {
  const SavedIdentityPasswordAuthentication();
}

/// Scope used for persisted service sessions and request single-flight keys.
sealed class SessionScope {
  const SessionScope();

  String get key;

  String keyFor(Uri uri) => key;
}

class ServiceSessionScope extends SessionScope {
  const ServiceSessionScope();

  @override
  String get key => 'service';
}

class PathPrefixSessionScope extends SessionScope {
  final String prefix;

  const PathPrefixSessionScope(this.prefix);

  @override
  String get key => 'path:$prefix';

  @override
  String keyFor(Uri uri) =>
      _matchesPathPrefix(uri.path, prefix) ? key : 'path-mismatch:$prefix';
}

class ExactUriSessionScope extends SessionScope {
  final Uri uri;

  const ExactUriSessionScope(this.uri);

  @override
  String get key => 'uri:${uri.toString()}';

  @override
  String keyFor(Uri uri) =>
      uri == this.uri ? key : 'uri-mismatch:${this.uri.toString()}';
}

bool _matchesPathPrefix(String path, String prefix) {
  if (prefix == '/') return true;
  final normalized =
      prefix.endsWith('/') ? prefix.substring(0, prefix.length - 1) : prefix;
  return path == normalized || path.startsWith('$normalized/');
}

/// Describes how a successful federated flow becomes usable session state.
sealed class SessionMaterializer {
  const SessionMaterializer();
}

class CookieMaterializer extends SessionMaterializer {
  const CookieMaterializer();
}

class HeaderFromCookie extends SessionMaterializer {
  final String cookieName;
  final String? fallbackCookieName;
  final String headerName;

  const HeaderFromCookie({
    required this.cookieName,
    this.fallbackCookieName,
    required this.headerName,
  });
}

class CompositeMaterializer extends SessionMaterializer {
  final List<SessionMaterializer> materializers;

  const CompositeMaterializer(this.materializers);
}

class TokenFromRedirect extends SessionMaterializer {
  final String queryParameter;
  final String headerName;
  final String prefix;

  const TokenFromRedirect({
    required this.queryParameter,
    required this.headerName,
    this.prefix = '',
  });

  String? valueFrom(Uri? uri) {
    if (uri == null) return null;
    final value = uri.queryParameters[queryParameter];
    return value == null || value.isEmpty ? null : value;
  }

  String? headerValueFrom(Uri? uri) {
    final value = valueFrom(uri);
    return value == null ? null : '$prefix$value';
  }
}

class WebViewSessionMaterializer extends SessionMaterializer {
  final bool ephemeral;

  const WebViewSessionMaterializer({this.ephemeral = true});
}

class CustomPostSsoBootstrap extends SessionMaterializer {
  final CampusServiceId bootstrapId;

  const CustomPostSsoBootstrap(this.bootstrapId);
}

extension SessionMaterializerInspection on SessionMaterializer {
  bool get containsCookieMaterializer => switch (this) {
    CookieMaterializer() => true,
    CompositeMaterializer(:final materializers) => materializers.any(
      (materializer) => materializer.containsCookieMaterializer,
    ),
    HeaderFromCookie() ||
    TokenFromRedirect() ||
    WebViewSessionMaterializer() ||
    CustomPostSsoBootstrap() => false,
  };

  bool get containsWebViewSessionMaterializer => switch (this) {
    WebViewSessionMaterializer() => true,
    CompositeMaterializer(:final materializers) => materializers.any(
      (materializer) => materializer.containsWebViewSessionMaterializer,
    ),
    CookieMaterializer() ||
    HeaderFromCookie() ||
    TokenFromRedirect() ||
    CustomPostSsoBootstrap() => false,
  };

  TokenFromRedirect? get tokenFromRedirect => switch (this) {
    TokenFromRedirect() => this as TokenFromRedirect,
    CompositeMaterializer(:final materializers) => materializers
        .map((materializer) => materializer.tokenFromRedirect)
        .firstWhere((materializer) => materializer != null, orElse: () => null),
    CookieMaterializer() ||
    HeaderFromCookie() ||
    WebViewSessionMaterializer() ||
    CustomPostSsoBootstrap() => null,
  };
}

/// Service-specific authentication failure classification. HTTP status codes
/// are intentionally opt-in; a normal 401/403 is not a global re-login signal.
sealed class AuthFailurePolicy {
  const AuthFailurePolicy();
}

class RedirectAuthFailure extends AuthFailurePolicy {
  final Set<String> hosts;

  const RedirectAuthFailure(this.hosts);
}

class LoginHtmlAuthFailure extends AuthFailurePolicy {
  final List<String> signatures;

  const LoginHtmlAuthFailure(this.signatures);
}

class JsonAuthFailure extends AuthFailurePolicy {
  final List<String> signatures;

  const JsonAuthFailure(this.signatures);
}

class StatusAuthFailure extends AuthFailurePolicy {
  final Set<int> statuses;

  const StatusAuthFailure(this.statuses);
}

class CompositeAuthFailurePolicy extends AuthFailurePolicy {
  final List<AuthFailurePolicy> policies;

  const CompositeAuthFailurePolicy(this.policies);
}

class NoStatusAuthFailure extends AuthFailurePolicy {
  const NoStatusAuthFailure();
}

class AuthFailureClassifier {
  const AuthFailureClassifier._();

  static bool matches({
    required AuthFailurePolicy policy,
    required int statusCode,
    Uri? location,
    required String body,
  }) {
    if (_isStrongGlobalSignal(location, body)) return true;
    return _matchesPolicy(policy, statusCode, location, body);
  }

  static bool _matchesPolicy(
    AuthFailurePolicy policy,
    int statusCode,
    Uri? location,
    String body,
  ) => switch (policy) {
    NoStatusAuthFailure() => false,
    StatusAuthFailure(:final statuses) => statuses.contains(statusCode),
    RedirectAuthFailure(:final hosts) =>
      location != null && hosts.contains(location.host.toLowerCase()),
    LoginHtmlAuthFailure(:final signatures) => _containsAny(
      body.toLowerCase(),
      signatures,
    ),
    JsonAuthFailure(:final signatures) => _containsAny(
      body.toLowerCase(),
      signatures,
    ),
    CompositeAuthFailurePolicy(:final policies) => policies.any(
      (child) => _matchesPolicy(child, statusCode, location, body),
    ),
  };

  static bool _isStrongGlobalSignal(Uri? location, String body) {
    if (location != null && const ChdIdentityProvider().isLoginUri(location)) {
      return true;
    }
    final lower = body.toLowerCase();
    return lower.contains('authserver/login') ||
        lower.contains('identity.chd.edu.cn') && lower.contains('/auth/') ||
        lower.contains('protocol/openid-connect') ||
        lower.contains('keycloak login') ||
        lower.contains('cas login') ||
        lower.contains('统一身份认证');
  }

  static bool _containsAny(String text, List<String> signatures) =>
      signatures.any((signature) => text.contains(signature.toLowerCase()));
}

/// Declares how a service response is checked after authentication.
sealed class ValidationPolicy {
  const ValidationPolicy();
}

class NoValidationPolicy extends ValidationPolicy {
  const NoValidationPolicy();
}

class HttpStatusValidation extends ValidationPolicy {
  const HttpStatusValidation();
}

class CampusHomeValidation extends ValidationPolicy {
  const CampusHomeValidation();
}

class CompositeValidationPolicy extends ValidationPolicy {
  final List<ValidationPolicy> policies;

  const CompositeValidationPolicy(this.policies);
}

/// Transport behaviour shared by the CampusSession request boundary and the
/// credential broker.
class TransportPolicy {
  final Map<String, String> headers;
  final bool closeConnection;
  final Duration postExchangeSettle;
  final String? serializationKey;
  final bool allowTransientReadRetry;
  final bool replaySafeReads;
  final List<String> replaySafePostPaths;

  const TransportPolicy({
    this.headers = const {},
    this.closeConnection = false,
    this.postExchangeSettle = Duration.zero,
    this.serializationKey,
    this.allowTransientReadRetry = true,
    this.replaySafeReads = true,
    this.replaySafePostPaths = const [],
  });
}
