import 'dart:io';

/// Minimal domain-aware cookie jar for server-side SSO redirect exchanges.
///
/// Flutter's [HttpClient] does not retain cookies between requests. Keeping
/// cookies scoped by host prevents same-named cookies (notably JSESSIONID)
/// from different CHD applications from overwriting each other.
class ScopedCookieJar {
  final Map<String, Map<String, Map<String, String>>> _cookiesByDomainPath = {};

  void seed(Uri uri, String cookieHeader) {
    _mergeHeader(_cookiesFor(uri.host, '/'), cookieHeader);
  }

  /// Seeds cookies under an explicit path prefix so a sub-application session
  /// (e.g. `/qljfwapp/`) does not overwrite the portal root session cookie.
  void seedAt(String host, String path, String cookieHeader) {
    if (path.isEmpty) path = '/';
    _mergeHeader(_cookiesFor(host, path), cookieHeader);
  }

  /// Removes all cookies stored for one host/path scope.
  ///
  /// Credential replacement must not leave a stale service session in the
  /// long-lived account session while the persisted Account is being rebuilt.
  void clearAt(String host, String path) {
    final domain = _cookiesByDomainPath[host.toLowerCase()];
    if (domain == null) return;
    domain.remove(path.isEmpty ? '/' : path);
    if (domain.isEmpty) _cookiesByDomainPath.remove(host.toLowerCase());
  }

  void collect(Uri requestUri, HttpClientResponse response) {
    response.headers.forEach((name, values) {
      if (name.toLowerCase() != HttpHeaders.setCookieHeader) return;
      collectSetCookieHeaders(requestUri, values);
    });
  }

  void collectSetCookieHeaders(Uri requestUri, Iterable<String> values) {
    for (final value in values) {
      final parts = value.split(';');
      if (parts.isEmpty) continue;
      final pair = parts.first.trim();
      final equalsIndex = pair.indexOf('=');
      if (equalsIndex <= 0) continue;

      var domain = requestUri.host.toLowerCase();
      var path = _defaultPath(requestUri);
      var remove = false;
      for (final attribute in parts.skip(1)) {
        final trimmed = attribute.trim();
        final attributeEquals = trimmed.indexOf('=');
        final key =
            (attributeEquals < 0
                    ? trimmed
                    : trimmed.substring(0, attributeEquals))
                .trim()
                .toLowerCase();
        final attributeValue =
            attributeEquals < 0
                ? ''
                : trimmed.substring(attributeEquals + 1).trim();
        if (key == 'domain' && attributeValue.isNotEmpty) {
          domain =
              attributeValue.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        } else if (key == 'path' && attributeValue.startsWith('/')) {
          path = attributeValue;
        } else if (key == 'max-age' && attributeValue == '0') {
          remove = true;
        }
      }

      final cookieName = pair.substring(0, equalsIndex).trim();
      final domainCookies = _cookiesFor(domain, path);
      if (remove) {
        domainCookies.remove(cookieName);
      } else {
        domainCookies[cookieName] = pair.substring(equalsIndex + 1).trim();
      }
    }
  }

  String headerFor(Uri uri) {
    return _matchingCookies(
      uri,
    ).map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  String? valueFor(Uri uri, String name) {
    for (final cookie in _matchingCookies(uri)) {
      if (cookie.name == name) return cookie.value;
    }
    return null;
  }

  Map<String, String> _cookiesFor(String domain, String path) =>
      _cookiesByDomainPath
          .putIfAbsent(domain.toLowerCase(), () => {})
          .putIfAbsent(path, () => {});

  List<_ScopedCookie> _matchingCookies(Uri uri) {
    final result = <_ScopedCookie>[];
    final host = uri.host.toLowerCase();
    for (final domainEntry in _cookiesByDomainPath.entries) {
      final domain = domainEntry.key;
      if (host != domain && !host.endsWith('.$domain')) continue;
      for (final pathEntry in domainEntry.value.entries) {
        if (!_pathMatches(uri.path, pathEntry.key)) continue;
        for (final cookieEntry in pathEntry.value.entries) {
          result.add(
            _ScopedCookie(
              name: cookieEntry.key,
              value: cookieEntry.value,
              path: pathEntry.key,
            ),
          );
        }
      }
    }
    result.sort((a, b) => b.path.length.compareTo(a.path.length));
    return result;
  }

  static String _defaultPath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || path == '/' || !path.contains('/')) return '/';
    final lastSlash = path.lastIndexOf('/');
    return lastSlash == 0 ? '/' : path.substring(0, lastSlash);
  }

  static bool _pathMatches(String requestPath, String cookiePath) =>
      cookiePath == '/' ||
      requestPath == cookiePath ||
      (requestPath.startsWith(cookiePath) &&
          (cookiePath.endsWith('/') ||
              (requestPath.length > cookiePath.length &&
                  requestPath[cookiePath.length] == '/')));

  static void _mergeHeader(Map<String, String> target, String header) {
    target.addAll(parseCookieHeader(header));
  }

  /// Parses a raw `Cookie` header string into name/value pairs.
  static Map<String, String> parseCookieHeader(String header) {
    final result = <String, String>{};
    for (final part in header.split(';')) {
      final cookie = part.trim();
      final equalsIndex = cookie.indexOf('=');
      if (equalsIndex <= 0) continue;
      result[cookie.substring(0, equalsIndex).trim()] =
          cookie.substring(equalsIndex + 1).trim();
    }
    return result;
  }
}

class _ScopedCookie {
  final String name;
  final String value;
  final String path;

  const _ScopedCookie({
    required this.name,
    required this.value,
    required this.path,
  });
}
