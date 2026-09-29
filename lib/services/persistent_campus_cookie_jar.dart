import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'campus_service_id.dart';
import 'session_storage_support.dart';
import 'session_materialization.dart';

/// Complete cookie metadata retained by the account-scoped session store.
class PersistentCampusCookie {
  final String name;
  final String value;
  final String domain;
  final bool hostOnly;
  final String path;
  final DateTime? expires;
  final int? maxAge;
  final bool secure;
  final bool httpOnly;
  final String? sameSite;
  final DateTime createdAt;
  final String identityEpoch;
  final String sessionScope;

  const PersistentCampusCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.expires,
    required this.maxAge,
    required this.secure,
    required this.httpOnly,
    required this.sameSite,
    required this.createdAt,
    required this.identityEpoch,
    required this.sessionScope,
  });

  String get identity => '$domain|$hostOnly|$path|$name';

  bool isExpired(DateTime now) {
    if (maxAge != null) {
      return !createdAt.toUtc().add(Duration(seconds: maxAge!)).isAfter(now);
    }
    return expires != null && !expires!.isAfter(now);
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'hostOnly': hostOnly,
    'path': path,
    if (expires != null) 'expires': expires!.toUtc().toIso8601String(),
    if (maxAge != null) 'maxAge': maxAge,
    'secure': secure,
    'httpOnly': httpOnly,
    if (sameSite != null) 'sameSite': sameSite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'identityEpoch': identityEpoch,
    'sessionScope': sessionScope,
  };

  static PersistentCampusCookie? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final value = raw['value'];
    final domain = raw['domain'];
    final hostOnly = raw['hostOnly'];
    final path = raw['path'];
    final createdAt = _date(raw['createdAt']);
    final identityEpoch = raw['identityEpoch'];
    final sessionScope = raw['sessionScope'];
    if (name is! String ||
        name.isEmpty ||
        value is! String ||
        domain is! String ||
        domain.isEmpty ||
        hostOnly is! bool ||
        path is! String ||
        !path.startsWith('/') ||
        createdAt == null ||
        identityEpoch is! String ||
        sessionScope is! String) {
      return null;
    }
    final maxAge = raw['maxAge'];
    if (maxAge != null && maxAge is! int) return null;
    final expires = raw['expires'] == null ? null : _date(raw['expires']);
    if (raw['expires'] != null && expires == null) return null;
    final secure = raw['secure'];
    final httpOnly = raw['httpOnly'];
    if (secure is! bool || httpOnly is! bool) return null;
    final sameSite = raw['sameSite'];
    if (sameSite != null && sameSite is! String) return null;
    return PersistentCampusCookie(
      name: name,
      value: value,
      domain: domain.toLowerCase(),
      hostOnly: hostOnly,
      path: path,
      expires: expires,
      maxAge: maxAge,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
      createdAt: createdAt,
      identityEpoch: identityEpoch,
      sessionScope: sessionScope,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// Account-scoped, persistent cookie jar with domain/path/secure semantics.
class PersistentCampusCookieJar {
  PersistentCampusCookieJar({
    required this.accountKey,
    required this.serviceId,
    required this.sessionScope,
    required this.identityEpoch,
    FlutterSecureStorage? storage,
    DateTime Function()? now,
    String? materializationKey,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _now = now ?? DateTime.now,
       _materializationKeyOverride = materializationKey;

  final String accountKey;
  final CampusServiceId serviceId;
  final String sessionScope;
  final String identityEpoch;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final String? _materializationKeyOverride;
  final Map<String, PersistentCampusCookie> _cookies = {};
  Future<void>? _openFuture;
  var _opened = false;

  String get storageKey => SessionStorageKeys.cookieKey(
    accountKey: accountKey,
    serviceId: serviceId.value,
    scopeKey: sessionScope,
  );

  String get materializationKey =>
      _materializationKeyOverride ??
      SessionMaterializationRegistry.serviceKey(accountKey, serviceId);

  Future<void> open() {
    if (_opened) return Future<void>.value();
    final pending = _openFuture;
    if (pending != null) return pending;
    final future = _load();
    _openFuture = future;
    return future;
  }

  Future<void> _load() async {
    try {
      await _reloadFromStorage();
    } finally {
      _opened = true;
    }
  }

  Future<void> collectSetCookieHeaders(
    Uri requestUri,
    Iterable<String> values, {
    SessionMaterializationMutation? mutation,
  }) async {
    await collectSetCookieHeadersIfCurrent(
      requestUri,
      values,
      isCurrent: () => true,
      verifyIdentityEpoch: true,
      mutation: mutation,
    );
  }

  /// Merges response cookies while holding the account storage queue.
  ///
  /// The reload is deliberately inside the queue. Separate store instances
  /// are allowed to exist during a cold start, so an instance's in-memory
  /// snapshot is not a safe base for a read-modify-write operation.
  Future<bool> collectSetCookieHeadersIfCurrent(
    Uri requestUri,
    Iterable<String> values, {
    required bool Function() isCurrent,
    bool verifyIdentityEpoch = true,
    SessionMaterializationMutation? mutation,
  }) async {
    return _runMutation(
      mutation: mutation,
      action: () async {
        await open();
        return AccountSessionStorageQueue.run(accountKey, () async {
          if (!isCurrent() ||
              verifyIdentityEpoch && !await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return false;
          }
          await _reloadFromStorage();
          if (!isCurrent() ||
              verifyIdentityEpoch && !await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return false;
          }
          final now = _now().toUtc();
          for (final value in values) {
            _applySetCookie(requestUri, value, now);
          }
          await _persist();
          return true;
        });
      },
    );
  }

  Future<void> seedCookieHeader(
    Uri uri,
    String header, {
    SessionMaterializationMutation? mutation,
  }) async {
    await seedCookieHeaderIfCurrent(
      uri,
      header,
      isCurrent: () => true,
      verifyIdentityEpoch: true,
      mutation: mutation,
    );
  }

  /// Seeds a compatibility cookie projection without allowing an old store
  /// instance to rewrite the current identity epoch.
  Future<bool> seedCookieHeaderIfCurrent(
    Uri uri,
    String header, {
    required bool Function() isCurrent,
    bool verifyIdentityEpoch = true,
    SessionMaterializationMutation? mutation,
  }) async {
    if (header.isEmpty) return true;
    return _runMutation(
      mutation: mutation,
      action: () async {
        await open();
        return AccountSessionStorageQueue.run(accountKey, () async {
          if (!isCurrent() ||
              verifyIdentityEpoch && !await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return false;
          }
          await _reloadFromStorage();
          if (!isCurrent() ||
              verifyIdentityEpoch && !await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return false;
          }
          final now = _now().toUtc();
          for (final entry in parseCookieHeader(header).entries) {
            _upsert(
              PersistentCampusCookie(
                name: entry.key,
                value: entry.value,
                domain: uri.host.toLowerCase(),
                hostOnly: true,
                path: '/',
                expires: null,
                maxAge: null,
                secure: false,
                httpOnly: false,
                sameSite: null,
                createdAt: now,
                identityEpoch: identityEpoch,
                sessionScope: sessionScope,
              ),
            );
          }
          await _persist();
          return true;
        });
      },
    );
  }

  Future<void> importCookie(
    PersistentCampusCookie cookie, {
    SessionMaterializationMutation? mutation,
  }) async {
    if (cookie.identityEpoch != identityEpoch ||
        cookie.sessionScope != sessionScope) {
      throw StateError('cookie identity epoch or scope mismatch');
    }
    await _runVoidMutation(
      mutation: mutation,
      action: () async {
        await open();
        await AccountSessionStorageQueue.run(accountKey, () async {
          if (!await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return;
          }
          await _reloadFromStorage();
          if (!await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return;
          }
          _upsert(cookie);
          await _persist();
        });
      },
    );
  }

  Future<List<PersistentCampusCookie>> cookiesFor(Uri uri) async {
    final currentCookies = await _currentSnapshot();
    final now = _now().toUtc();
    final result =
        currentCookies
            .where(
              (cookie) =>
                  !cookie.isExpired(now) &&
                  _domainMatches(cookie, uri.host) &&
                  _pathMatches(uri.path, cookie.path) &&
                  (!cookie.secure || uri.scheme.toLowerCase() == 'https'),
            )
            .toList();
    result.sort((a, b) {
      final pathOrder = b.path.length.compareTo(a.path.length);
      if (pathOrder != 0) return pathOrder;
      return a.createdAt.compareTo(b.createdAt);
    });
    return result;
  }

  Future<String> headerFor(Uri uri) async => (await cookiesFor(
    uri,
  )).map((cookie) => '${cookie.name}=${cookie.value}').join('; ');

  Future<List<PersistentCampusCookie>> snapshot() async {
    final currentCookies = await _currentSnapshot();
    final now = _now().toUtc();
    return currentCookies
        .where((cookie) => !cookie.isExpired(now))
        .toList(growable: false);
  }

  Future<void> clear({SessionMaterializationMutation? mutation}) async {
    await _runVoidMutation(
      mutation: mutation,
      action: () async {
        await AccountSessionStorageQueue.run(accountKey, () async {
          if (!await _identityEpochMatchesStorage()) {
            _cookies.clear();
            return;
          }
          _cookies.clear();
          await _storage.delete(key: storageKey);
        });
      },
    );
  }

  Future<T> _runMutation<T>({
    required SessionMaterializationMutation? mutation,
    required Future<T> Function() action,
  }) async {
    final owned =
        mutation == null
            ? await SessionMaterializationRegistry.beginMutation(
              keys: [materializationKey],
            )
            : null;
    mutation?.requireKey(materializationKey);
    try {
      final result = await action();
      if (owned != null) await owned.end(commit: result is! bool || result);
      return result;
    } catch (_) {
      if (owned != null) await owned.end(commit: false);
      rethrow;
    }
  }

  Future<void> _runVoidMutation({
    required SessionMaterializationMutation? mutation,
    required Future<void> Function() action,
  }) async {
    final owned =
        mutation == null
            ? await SessionMaterializationRegistry.beginMutation(
              keys: [materializationKey],
            )
            : null;
    mutation?.requireKey(materializationKey);
    try {
      await action();
      if (owned != null) await owned.end(commit: true);
    } catch (_) {
      if (owned != null) await owned.end(commit: false);
      rethrow;
    }
  }

  /// Reloads the jar under the account queue before exposing any credential.
  ///
  /// An already-open jar may outlive a root identity replacement performed by
  /// another [CampusSessionStore] instance. Filtering against this jar's
  /// captured epoch alone would otherwise make stale in-memory cookies look
  /// valid.
  Future<List<PersistentCampusCookie>> _currentSnapshot() async {
    await open();
    return AccountSessionStorageQueue.run(accountKey, () async {
      if (!await _identityEpochMatchesStorage()) {
        _cookies.clear();
        return const <PersistentCampusCookie>[];
      }
      await _reloadFromStorage();
      if (!await _identityEpochMatchesStorage()) {
        _cookies.clear();
        return const <PersistentCampusCookie>[];
      }
      return List<PersistentCampusCookie>.of(_cookies.values);
    });
  }

  Future<void> _reloadFromStorage() async {
    _cookies.clear();
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    for (final item in decoded) {
      final cookie = PersistentCampusCookie.fromJson(item);
      if (cookie == null ||
          cookie.identityEpoch != identityEpoch ||
          cookie.sessionScope != sessionScope ||
          cookie.isExpired(_now().toUtc())) {
        continue;
      }
      _cookies[cookie.identity] = cookie;
    }
  }

  Future<bool> _identityEpochMatchesStorage() async {
    final current = await _storage.read(
      key: SessionStorageKeys.identityEpochKey(accountKey),
    );
    return current == identityEpoch;
  }

  void _applySetCookie(Uri requestUri, String raw, DateTime now) {
    final parts = raw.split(';');
    if (parts.isEmpty) return;
    final pair = parts.first.trim();
    final separator = pair.indexOf('=');
    if (separator <= 0) return;
    final name = pair.substring(0, separator).trim();
    final value = pair.substring(separator + 1).trim();
    if (name.isEmpty) return;

    var domain = requestUri.host.toLowerCase();
    var hostOnly = true;
    var path = _defaultPath(requestUri);
    DateTime? expires;
    int? maxAge;
    var secure = false;
    var httpOnly = false;
    String? sameSite;
    var invalidDomain = false;
    for (final attribute in parts.skip(1)) {
      final trimmed = attribute.trim();
      if (trimmed.isEmpty) continue;
      final attributeSeparator = trimmed.indexOf('=');
      final key =
          (attributeSeparator < 0
                  ? trimmed
                  : trimmed.substring(0, attributeSeparator))
              .trim()
              .toLowerCase();
      final attributeValue =
          attributeSeparator < 0
              ? ''
              : trimmed.substring(attributeSeparator + 1).trim();
      switch (key) {
        case 'domain':
          if (attributeValue.isEmpty) {
            invalidDomain = true;
            continue;
          }
          domain =
              attributeValue.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
          hostOnly = false;
          if (!_domainAttributeMatches(requestUri.host, domain)) {
            invalidDomain = true;
          }
        case 'path':
          if (attributeValue.startsWith('/')) path = attributeValue;
        case 'expires':
          try {
            expires = HttpDate.parse(attributeValue).toUtc();
          } catch (_) {
            expires = DateTime.tryParse(attributeValue)?.toUtc();
          }
        case 'max-age':
          maxAge = int.tryParse(attributeValue);
        case 'secure':
          secure = true;
        case 'httponly':
          httpOnly = true;
        case 'samesite':
          sameSite = attributeValue.toLowerCase();
      }
    }
    if (invalidDomain) return;
    if (maxAge != null && maxAge <= 0) {
      _remove(domain, hostOnly, path, name);
      return;
    }
    if (maxAge == null && expires != null && !expires.isAfter(now)) {
      _remove(domain, hostOnly, path, name);
      return;
    }
    _upsert(
      PersistentCampusCookie(
        name: name,
        value: value,
        domain: domain,
        hostOnly: hostOnly,
        path: path,
        expires: expires,
        maxAge: maxAge,
        secure: secure,
        httpOnly: httpOnly,
        sameSite: sameSite,
        createdAt: now,
        identityEpoch: identityEpoch,
        sessionScope: sessionScope,
      ),
    );
  }

  Future<void> _persist() async {
    final value = jsonEncode(
      _cookies.values.map((cookie) => cookie.toJson()).toList(),
    );
    await _storage.write(key: storageKey, value: value);
  }

  void _upsert(PersistentCampusCookie cookie) {
    _cookies[cookie.identity] = cookie;
  }

  void _remove(String domain, bool hostOnly, String path, String name) {
    _cookies.remove('$domain|$hostOnly|$path|$name');
  }

  static bool _domainAttributeMatches(String sourceHost, String domain) {
    final source = sourceHost.toLowerCase();
    final normalized = domain.toLowerCase();
    return source == normalized || source.endsWith('.$normalized');
  }

  static bool _domainMatches(PersistentCampusCookie cookie, String host) {
    final normalizedHost = host.toLowerCase();
    if (cookie.hostOnly) return normalizedHost == cookie.domain;
    return _domainAttributeMatches(normalizedHost, cookie.domain);
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    if (cookiePath == '/') return true;
    if (requestPath == cookiePath) return true;
    if (!requestPath.startsWith(cookiePath)) return false;
    return cookiePath.endsWith('/') ||
        (requestPath.length > cookiePath.length &&
            requestPath[cookiePath.length] == '/');
  }

  static String _defaultPath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || path == '/' || !path.contains('/')) return '/';
    final lastSlash = path.lastIndexOf('/');
    return lastSlash == 0 ? '/' : path.substring(0, lastSlash);
  }

  static Map<String, String> parseCookieHeader(String header) {
    final result = <String, String>{};
    for (final part in header.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      if (name.isEmpty) continue;
      result[name] = part.substring(separator + 1).trim();
    }
    return result;
  }
}
