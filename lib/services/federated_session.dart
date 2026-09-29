import 'dart:async';
import 'dart:io';

import 'auth_service.dart';
import 'campus_session_store.dart';
import 'scoped_cookie_jar.dart';
import 'session_artifact_store.dart';
import 'session_materialization.dart';
import 'session_runtime_fence.dart';
import 'service_endpoints.dart';

class FederatedSetCookieEvent {
  const FederatedSetCookieEvent({
    required this.requestUri,
    required this.values,
  });

  final Uri requestUri;
  final List<String> values;
}

class FederatedExchangeResult {
  final ScopedCookieJar jar;
  final Uri finalUri;
  final bool endedAtIdentityLogin;
  final List<FederatedSetCookieEvent> cookieEvents;
  final bool committed;

  const FederatedExchangeResult({
    required this.jar,
    required this.finalUri,
    required this.endedAtIdentityLogin,
    this.cookieEvents = const [],
    this.committed = true,
  });
}

/// Request-driven CAS/OIDC redirect session.
///
/// The redirect loop, temporary cookie jar and identity-login classifier live
/// here; service definitions provide only the declared materializer-specific
/// headers. Persistent account state is owned by [CampusSessionStore] in the
/// next cutover phase, not by this ephemeral exchange jar.
class FederatedSession {
  const FederatedSession._();

  static const connectionTimeout = Duration(seconds: 8);
  static const requestTimeout = Duration(seconds: 12);
  static const maxRedirects = 12;

  /// Runs a federated exchange from the persisted root identity and commits
  /// only the response cookies/artifacts allowed by [definition]. Root
  /// identity cookies and service cookies remain separate scopes.
  static Future<FederatedExchangeResult> exchangeForStore({
    required CampusSessionStore store,
    required CampusServiceDefinition definition,
    required SessionRuntimeFence fence,
    Uri? startUri,
    String? label,
  }) async {
    final effectiveStartUri = startUri ?? definition.startUri;
    if (!definition.allowsExchangeStartUri(effectiveStartUri)) {
      throw ArgumentError.value(
        effectiveStartUri,
        'startUri',
        '不属于 ${definition.id.value} 声明的 host/path',
      );
    }
    final scopeKey = definition
        .scopeFor(effectiveStartUri)
        .keyFor(effectiveStartUri);
    if (fence.accountKey != store.accountKey ||
        fence.serviceId != definition.id ||
        fence.scopeKey != scopeKey) {
      throw StateError('Federated exchange fence 与当前 service scope 不匹配');
    }
    if (!definition.sessionScopeKeys.every(
      fence.serviceGenerations.containsKey,
    )) {
      throw StateError('Federated exchange fence 未覆盖所有声明的 service scope');
    }
    final identityCookieHeader = await store.rootCookieHeader();
    final result = await exchange(
      startUri: effectiveStartUri,
      identityCookieHeader: identityCookieHeader,
      label: label ?? definition.id.value,
      definition: definition,
    );
    final committed = await _persistResult(store, definition, result, fence);
    return FederatedExchangeResult(
      jar: result.jar,
      finalUri: result.finalUri,
      endedAtIdentityLogin: result.endedAtIdentityLogin,
      cookieEvents: result.cookieEvents,
      committed: committed,
    );
  }

  static Future<FederatedExchangeResult> exchange({
    required Uri startUri,
    required String identityCookieHeader,
    required String label,
    CampusServiceDefinition? definition,
  }) async {
    final client = _newClient();
    final jar =
        ScopedCookieJar()
          ..seed(CampusServiceEndpoints.idsAuthUri, identityCookieHeader)
          ..seed(CampusServiceEndpoints.identityRealmUri, identityCookieHeader);
    var finalUri = startUri;
    var endedAtIdentityLogin = false;
    final cookieEvents = <FederatedSetCookieEvent>[];
    final identityProvider = _identityProviderFor(definition);
    try {
      var uri = startUri;
      final visitedStates = <String>{};
      var reachedRedirectLimit = true;
      for (var redirect = 0; redirect < maxRedirects; redirect++) {
        final cookies = jar.headerFor(uri);
        if (!registerRedirectState(visitedStates, uri, cookies)) {
          endedAtIdentityLogin = isIdentityLoginUri(
            uri,
            provider: identityProvider,
          );
          reachedRedirectLimit = false;
          break;
        }
        final request = await client.getUrl(uri).timeout(connectionTimeout);
        if (cookies.isNotEmpty) {
          request.headers.set(HttpHeaders.cookieHeader, cookies);
        }
        for (final entry in headersFor(definition, jar, uri).entries) {
          request.headers.set(entry.key, entry.value);
        }
        _setBrowserHeaders(request);
        request.followRedirects = false;
        final response = await request.close().timeout(requestTimeout);
        jar.collect(uri, response);
        final setCookieValues = response.headers[HttpHeaders.setCookieHeader];
        if (setCookieValues != null && setCookieValues.isNotEmpty) {
          cookieEvents.add(
            FederatedSetCookieEvent(
              requestUri: uri,
              values: List<String>.unmodifiable(setCookieValues),
            ),
          );
        }

        final isRedirect =
            response.statusCode >= HttpStatus.multipleChoices &&
            response.statusCode < HttpStatus.badRequest;
        final location =
            isRedirect
                ? response.headers.value(HttpHeaders.locationHeader)
                : null;
        await _drain(response);
        if (!isRedirect || location == null || location.isEmpty) {
          endedAtIdentityLogin = isIdentityLoginUri(
            uri,
            provider: identityProvider,
          );
          reachedRedirectLimit = false;
          break;
        }
        uri = uri.resolve(location);
        finalUri = uri;
      }
      if (reachedRedirectLimit) {
        endedAtIdentityLogin = isIdentityLoginUri(
          finalUri,
          provider: identityProvider,
        );
      }
    } catch (_) {
      // The caller decides whether a transport failure is retryable. Cookies
      // collected before the failure remain available in the result.
    } finally {
      client.close(force: true);
    }
    return FederatedExchangeResult(
      jar: jar,
      finalUri: finalUri,
      endedAtIdentityLogin: endedAtIdentityLogin,
      cookieEvents: List<FederatedSetCookieEvent>.unmodifiable(cookieEvents),
    );
  }

  static Future<bool> _persistResult(
    CampusSessionStore store,
    CampusServiceDefinition definition,
    FederatedExchangeResult result,
    SessionRuntimeFence fence,
  ) async {
    bool isCurrent() => fence.isCurrent(
      currentAccountKey: store.accountKey,
      currentSessionRevision: AuthService.sessionRevision,
    );

    bool isCurrentForEvent(Uri requestUri) {
      final scopeKey = definition.scopeFor(requestUri).keyFor(requestUri);
      return isCurrent() &&
          fence.isCurrentForScope(
            targetScopeKey: scopeKey,
            currentAccountKey: store.accountKey,
            currentSessionRevision: AuthService.sessionRevision,
          );
    }

    if (!isCurrent()) return false;
    final rootJar = store.rootCookieJar;
    final isEphemeral =
        definition.sessionMaterializer.containsWebViewSessionMaterializer;
    final identityProvider = _identityProviderFor(definition);

    final mutationKeys = <String>{};
    for (final event in result.cookieEvents) {
      final host = event.requestUri.host.toLowerCase();
      final writesRoot =
          !isEphemeral && identityProvider.owns(event.requestUri) ||
          definition.rootIdentity &&
              definition.hosts.any((candidate) => candidate == host);
      final writesService =
          !isEphemeral &&
          event.requestUri.host.toLowerCase() == definition.host &&
          definition.allowsUri(event.requestUri);
      if (writesRoot) {
        mutationKeys.add(
          SessionMaterializationRegistry.rootKey(store.accountKey),
        );
      } else if (writesService) {
        mutationKeys.add(
          SessionMaterializationRegistry.serviceKey(
            store.accountKey,
            definition.id,
          ),
        );
      }
    }
    if (_tokenFromResult(definition, result.finalUri) case final token?
        when token.isNotEmpty) {
      mutationKeys.add(
        SessionMaterializationRegistry.serviceKey(
          store.accountKey,
          definition.id,
        ),
      );
    }
    if (mutationKeys.isEmpty) return true;
    final mutation = await SessionMaterializationRegistry.beginMutation(
      keys: mutationKeys,
    );
    var ended = false;

    try {
      for (final event in result.cookieEvents) {
        final host = event.requestUri.host.toLowerCase();
        if (!isEphemeral && identityProvider.owns(event.requestUri)) {
          final committed = await rootJar.collectSetCookieHeadersIfCurrent(
            event.requestUri,
            event.values,
            isCurrent: () => isCurrentForEvent(event.requestUri),
            verifyIdentityEpoch: true,
            mutation: mutation,
          );
          if (!committed) {
            await mutation.end(commit: false);
            ended = true;
            return false;
          }
          continue;
        }
        if (definition.rootIdentity &&
            definition.hosts.any((candidate) => candidate == host)) {
          final committed = await rootJar.collectSetCookieHeadersIfCurrent(
            event.requestUri,
            event.values,
            isCurrent: () => isCurrentForEvent(event.requestUri),
            verifyIdentityEpoch: true,
            mutation: mutation,
          );
          if (!committed) {
            await mutation.end(commit: false);
            ended = true;
            return false;
          }
          continue;
        }
        if (!isEphemeral &&
            event.requestUri.host.toLowerCase() == definition.host &&
            definition.allowsUri(event.requestUri)) {
          final committed = await store
              .cookieJar(
                definition.id,
                scope: definition.scopeFor(event.requestUri),
              )
              .collectSetCookieHeadersIfCurrent(
                event.requestUri,
                event.values,
                isCurrent: () => isCurrentForEvent(event.requestUri),
                verifyIdentityEpoch: true,
                mutation: mutation,
              );
          if (!committed) {
            await mutation.end(commit: false);
            ended = true;
            return false;
          }
        }
      }

      final token = _tokenFromResult(definition, result.finalUri);
      if (token != null && token.isNotEmpty) {
        final committed = await store.artifacts.writeIfCurrent(
          TokenArtifact(
            serviceId: definition.id,
            rawValue: token,
            createdAt: DateTime.now().toUtc(),
            expiresAt: null,
            identityEpoch: store.identityEpoch,
          ),
          isCurrent: isCurrent,
          verifyIdentityEpoch: true,
          mutation: mutation,
        );
        if (!committed) {
          await mutation.end(commit: false);
          ended = true;
          return false;
        }
      }
      await mutation.end(commit: true);
      ended = true;
      return true;
    } finally {
      if (!ended) await mutation.end(commit: false);
    }
  }

  static String? _tokenFromResult(
    CampusServiceDefinition definition,
    Uri finalUri,
  ) {
    final materializer = definition.sessionMaterializer.tokenFromRedirect;
    return materializer?.valueFrom(finalUri);
  }

  static Map<String, String> headersFor(
    CampusServiceDefinition? definition,
    ScopedCookieJar jar,
    Uri uri,
  ) {
    final materializer = definition?.sessionMaterializer;
    if (materializer == null) return const {};
    final headers = <String, String>{};
    void visit(SessionMaterializer current) {
      switch (current) {
        case HeaderFromCookie(
          :final cookieName,
          :final fallbackCookieName,
          :final headerName,
        ):
          final value =
              jar.valueFor(uri, cookieName) ??
              (fallbackCookieName == null
                  ? null
                  : jar.valueFor(uri, fallbackCookieName));
          if (value != null && value.isNotEmpty) headers[headerName] = value;
        case CompositeMaterializer(:final materializers):
          for (final child in materializers) {
            visit(child);
          }
        case CookieMaterializer():
        case TokenFromRedirect():
        case WebViewSessionMaterializer():
        case CustomPostSsoBootstrap():
      }
    }

    visit(materializer);
    return headers;
  }

  static bool registerRedirectState(
    Set<String> visitedStates,
    Uri uri,
    String cookieHeader,
  ) => visitedStates.add('${uri.toString()}\n$cookieHeader');

  static bool isIdentityLoginUri(
    Uri uri, {
    ChdIdentityProvider provider = const ChdIdentityProvider(),
  }) => provider.isLoginUri(uri);

  static ChdIdentityProvider _identityProviderFor(
    CampusServiceDefinition? definition,
  ) {
    final authentication = definition?.authentication;
    return switch (authentication) {
      FederatedAuthentication(:final provider) => provider,
      _ => const ChdIdentityProvider(),
    };
  }

  static HttpClient _newClient() {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    client.badCertificateCallback =
        (certificate, host, port) => CampusServiceEndpoints.isChdHost(host);
    return client;
  }

  static void _setBrowserHeaders(HttpClientRequest request) {
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    );
    request.headers.set(
      'Accept',
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    );
    request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
  }

  static Future<void> _drain(HttpClientResponse response) async {
    try {
      await response.drain<void>().timeout(requestTimeout);
    } on HttpException {
      // Redirect exchange only needs headers; an early body close is safe.
    } on SocketException {
      // Same as above for a server that closes after Set-Cookie/Location.
    } on TimeoutException {
      // The next validation/request will decide whether the session is usable.
    }
  }
}
