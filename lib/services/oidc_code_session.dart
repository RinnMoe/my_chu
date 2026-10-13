import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'federated_session.dart';
import 'service_endpoints.dart';

/// Host-only acquisition. No password or token is exposed to a feature.
class OidcCodeSession {
  static Future<({String? token, bool authExpired})> acquire(
    CampusServiceDefinition definition,
    OidcCodeMaterializer policy,
    String rootCookies,
  ) async {
    final random = Random.secure();
    final state = base64Url.encode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final authUri = policy.authorizationUri.replace(
      queryParameters: {
        'client_id': policy.clientId,
        'redirect_uri': policy.redirectUri.toString(),
        'response_type': 'code',
        'scope': 'openid',
        'state': state,
      },
    );
    bool isCallback(Uri uri) =>
        uri.scheme == policy.redirectUri.scheme &&
        uri.host == policy.redirectUri.host &&
        uri.port == policy.redirectUri.port &&
        uri.path == policy.redirectUri.path;
    final exchange = await FederatedSession.exchange(
      startUri: authUri,
      identityCookieHeader: rootCookies,
      label: definition.id.value,
      definition: definition,
      stopAtRedirect: isCallback,
    );
    final callback = exchange.finalUri;
    if (!isCallback(callback) ||
        callback.queryParameters['state'] != state ||
        callback.queryParameters['code']?.isNotEmpty != true) {
      return (token: null, authExpired: exchange.endedAtIdentityLogin);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      Future<Map<String, dynamic>?> post(
        Uri uri, {
        String? bearer,
        String? body,
      }) async {
        final request = await client
            .postUrl(uri)
            .timeout(const Duration(seconds: 12));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (bearer != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $bearer',
          );
        }
        if (body != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'utf-8',
          );
          request.write(body);
        }
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        final bytes = await response
            .fold<List<int>>([], (all, part) {
              if (all.length + part.length > 1024 * 1024) {
                throw const FormatException('认证响应过大');
              }
              return all..addAll(part);
            })
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) return null;
        final decoded = jsonDecode(utf8.decode(bytes));
        return decoded is Map<String, dynamic> ? decoded : null;
      }

      final form =
          Uri(
            queryParameters: {
              'grant_type': 'authorization_code',
              'client_id': policy.clientId,
              'redirect_uri': policy.redirectUri.toString(),
              'code': callback.queryParameters['code']!,
            },
          ).query;
      final identity = await post(policy.tokenUri, body: form);
      final identityToken = identity?['access_token'];
      if (identityToken is! String || identityToken.isEmpty) {
        return (token: null, authExpired: false);
      }
      final service = await post(policy.conversionUri, bearer: identityToken);
      // The SPA's access-token model maps OAuth snake_case fields.
      final token = service?['access_token'];
      return (
        token: token is String && token.isNotEmpty ? token : null,
        authExpired: false,
      );
    } catch (_) {
      return (token: null, authExpired: false);
    } finally {
      client.close(force: true);
    }
  }
}
