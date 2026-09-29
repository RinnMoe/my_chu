import 'dart:convert';

import '../models/account.dart';
import 'auth_service.dart';
import 'campus_session.dart';
import 'logger_service.dart';
import 'mobile_campus_user_service.dart';
import 'portal_route_service.dart';
import 'service_endpoints.dart';

/// The account identity and its first-page context are shared by login,
/// homepage and profile code. The primary source is mobile campus
/// `getUserInfo`; the portal `getLoginUser` remains the compatibility fallback.
class PortalIdentityService {
  static const _ttl = Duration(minutes: 5);
  static final Map<String, Future<Account?>> _nameRefreshes = {};
  static final Map<String, Future<PortalIdentity?>> _loads = {};
  static final Map<String, _CachedPortalIdentity> _cache = {};

  static bool hasDisplayName(String? name) =>
      !const {'', '用户', 'CHUer', '我在长大用户'}.contains(name?.trim() ?? '');

  static bool hasIdentity(String? identity) =>
      identity != null && identity.trim().isNotEmpty;

  /// Completes a provisional account name from the account profile source.
  ///
  /// The mobile campus response can contain the student number without a
  /// display name. Refreshes only accounts that still have a provisional
  /// display name or missing profile fields, so both a new login and an older
  /// stored account use the same application session.
  static Future<Account?> refreshAccountName() async {
    final account = await AuthService.getCurrentAccount();
    if (account == null ||
        (hasDisplayName(account.name) &&
            account.uid != null &&
            hasIdentity(account.identity))) {
      return account;
    }

    final sessionRevision = AuthService.sessionRevision;
    final refreshKey = '${account.accountKey}:$sessionRevision';
    final pending = _nameRefreshes[refreshKey];
    if (pending != null) return pending;

    final refresh = _refreshAccountName(account, sessionRevision);
    _nameRefreshes[refreshKey] = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_nameRefreshes[refreshKey], refresh)) {
        _nameRefreshes.remove(refreshKey);
      }
    }
  }

  static Future<Account?> _refreshAccountName(
    Account account,
    int sessionRevision,
  ) async {
    try {
      final identity = await fetchCurrent();
      if (identity == null ||
          (!hasDisplayName(identity.name) && !hasIdentity(identity.identity))) {
        AppLogger.warn('门户资料未返回可用账号资料，保留当前账号信息');
        return account;
      }

      final latest = await AuthService.getCurrentAccount();
      if (latest == null ||
          latest.accountKey != account.accountKey ||
          AuthService.sessionRevision != sessionRevision) {
        return latest;
      }
      AppLogger.info('已通过共享门户会话补全账号资料');
      return latest;
    } catch (error) {
      AppLogger.warn('补全账号姓名失败 (${error.runtimeType})');
      return account;
    }
  }

  static Future<PortalIdentity?> fetchCurrent({
    bool forceCredentialRefresh = false,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) return null;
    final key = account.accountKey;
    final sessionRevision = AuthService.sessionRevision;
    final cached = _cache[key];
    if (!forceCredentialRefresh &&
        cached != null &&
        cached.sessionRevision == sessionRevision &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return cached.identity;
    }
    final loadKey = '$key:$sessionRevision';
    final pending = _loads[loadKey];
    if (pending != null) return pending;

    final load = _fetch(account, forceCredentialRefresh, sessionRevision);
    _loads[loadKey] = load;
    try {
      return await load;
    } finally {
      if (identical(_loads[loadKey], load)) _loads.remove(loadKey);
    }
  }

  static Future<PortalIdentity?> _fetch(
    Account account,
    bool forceCredentialRefresh,
    int sessionRevision,
  ) async {
    try {
      final profile = await MobileCampusUserService.fetchProfile(
        forceRefreshCredential: forceCredentialRefresh,
      );
      if (profile != null) {
        if (AuthService.sessionRevision != sessionRevision) return null;
        final current = await AuthService.getCurrentAccount();
        final mobileIdentity = PortalIdentity(
          uid: profile.userName,
          name: profile.displayName,
          identity: profile.identity ?? current?.identity ?? '',
        );
        final updated = await AuthService.patchAccount(
          account.accountKey,
          (current) => current.copyWith(
            uid: mobileIdentity.uid,
            name:
                hasDisplayName(mobileIdentity.name)
                    ? mobileIdentity.name
                    : current.name,
            identity:
                hasIdentity(mobileIdentity.identity)
                    ? mobileIdentity.identity
                    : current.identity,
          ),
          expectedRevision: sessionRevision,
        );
        if (updated != null && hasIdentity(mobileIdentity.identity)) {
          _cache[account.accountKey] = _CachedPortalIdentity(
            mobileIdentity,
            DateTime.now().add(_ttl),
            sessionRevision,
          );
          AppLogger.info('移动校园用户信息成功');
          return mobileIdentity;
        }
        if (updated != null) {
          AppLogger.info('移动校园用户资料已更新，身份继续使用门户资料');
        }
      }
      return await _fetchPortalIdentity(
        account,
        forceCredentialRefresh,
        sessionRevision,
      );
    } catch (error) {
      AppLogger.warn('移动校园用户资料获取失败 (${error.runtimeType})');
      return _fetchPortalIdentity(
        account,
        forceCredentialRefresh,
        sessionRevision,
      );
    }
  }

  static Future<PortalIdentity?> _fetchPortalIdentity(
    Account account,
    bool forceCredentialRefresh,
    int sessionRevision,
  ) async {
    try {
      if (AuthService.sessionRevision != sessionRevision) return null;
      CampusSession? session;
      if (forceCredentialRefresh) {
        session = await CampusSession.open(accountKey: account.accountKey);
        await session.invalidateService(CampusServices.informationPortal);
      }
      var identity = await _requestCurrentIdentity();
      if (AuthService.sessionRevision != sessionRevision) return null;
      if (identity == null && !forceCredentialRefresh) {
        // Older versions could persist the preliminary portal cookie from an
        // incomplete CAS exchange. The endpoint then responds with HTTP 200
        // but no authenticated profile, which the generic transport cannot
        // distinguish from a successful business response. Refresh this one
        // service and retry exactly once so existing accounts self-heal.
        AppLogger.warn('门户用户信息无效，刷新门户会话后重试');
        session ??= await CampusSession.open(accountKey: account.accountKey);
        await session.invalidateService(CampusServices.informationPortal);
        identity = await _requestCurrentIdentity();
        if (AuthService.sessionRevision != sessionRevision) return null;
      }
      final resolvedIdentity = identity;
      if (resolvedIdentity == null) return null;

      final updated = await AuthService.patchAccount(
        account.accountKey,
        (current) => current.copyWith(
          uid: resolvedIdentity.uid,
          name:
              hasDisplayName(resolvedIdentity.name)
                  ? resolvedIdentity.name
                  : current.name,
          identity:
              hasIdentity(resolvedIdentity.identity)
                  ? resolvedIdentity.identity
                  : current.identity,
        ),
        expectedRevision: sessionRevision,
      );
      if (updated == null) return null;
      _cache[account.accountKey] = _CachedPortalIdentity(
        resolvedIdentity,
        DateTime.now().add(_ttl),
        sessionRevision,
      );
      AppLogger.info('门户用户信息成功');
      return resolvedIdentity;
    } catch (error) {
      AppLogger.warn('门户用户信息获取失败 (${error.runtimeType})');
      return null;
    }
  }

  static Future<PortalIdentity?> _requestCurrentIdentity() async {
    AppLogger.info('门户 getLoginUser 开始获取用户信息');
    final account = await AuthService.getCurrentAccount();
    final route = PortalRoute.fromIdentity(account?.identity);
    return PortalIdentity.fromResponse(
      await CampusSession.client(CampusServices.informationPortal).get(
        CampusServiceEndpoints.portalGetLoginUserUri
            .replace(
              queryParameters: {
                '_t': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            )
            .toString(),
        extraHeaders: {
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'X-Requested-With': 'XMLHttpRequest',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
              'Chrome/131.0.6778.200 Mobile Safari/537.36',
          ...?route?.cardHeaders,
        },
      ),
    );
  }

  static String extractDisplayName(Object? value) {
    final map = _asMap(value);
    if (map == null) return '';
    for (final key in const [
      'name',
      'userName',
      'cn',
      'nickName',
      'nickname',
      'realname',
      'realName',
    ]) {
      final name = map[key]?.toString().trim() ?? '';
      if (hasDisplayName(name)) return name;
    }
    for (final key in const ['data', 'datas', 'profile', 'user', 'account']) {
      final name = extractDisplayName(map[key]);
      if (hasDisplayName(name)) return name;
    }
    return '';
  }

  /// Extracts the most specific student/staff identity from portal categories.
  ///
  /// The current endpoint returns values such as “学生/研究生”. The UI only
  /// needs the specific segment (“研究生”), not the full category path.
  static String extractIdentity(Object? value) {
    final map = _asMap(value);
    if (map == null) return '';
    for (final key in const ['categoryName', 'deptName']) {
      final identity = _identityLabel(map[key]);
      if (identity.isNotEmpty) return identity;
    }
    for (final key in const ['data', 'datas', 'profile', 'user', 'account']) {
      final identity = extractIdentity(map[key]);
      if (identity.isNotEmpty) return identity;
    }
    return '';
  }

  static String _identityLabel(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final segments = raw
        .split(RegExp(r'[/／|｜>＞]'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    const markers = [
      '博士后',
      '博士研究生',
      '硕士研究生',
      '研究生',
      '本科生',
      '专科生',
      '留学生',
      '交换生',
      '教职工',
      '教师',
      '职工',
      '学生',
    ];
    for (final segment in segments.reversed) {
      if (markers.any((marker) => segment.contains(marker))) return segment;
    }
    return segments.length > 1 ? segments.last : raw;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    value = _decodeNestedJson(value);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static Object? _decodeNestedJson(Object? value) {
    var decoded = value;
    for (var index = 0; index < 3 && decoded is String; index++) {
      final text = decoded.trim();
      if (!(text.startsWith('{') || text.startsWith('['))) break;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        break;
      }
    }
    return decoded;
  }

  static Iterable<Map<String, dynamic>> _profileMaps(
    Object? value, [
    int depth = 0,
  ]) sync* {
    if (depth > 8) return;
    final decoded = _decodeNestedJson(value);
    final map = _asMap(decoded);
    if (map != null) {
      yield map;
      for (final child in map.values) {
        yield* _profileMaps(child, depth + 1);
      }
    } else if (decoded is List) {
      for (final child in decoded) {
        yield* _profileMaps(child, depth + 1);
      }
    }
  }
}

class PortalIdentity {
  final String uid;
  final String name;
  final String identity;

  const PortalIdentity({
    required this.uid,
    required this.name,
    this.identity = '',
  });

  static PortalIdentity? fromResponse(Object? value) {
    final root = PortalIdentityService._asMap(value);
    if (root == null) return null;
    final errorCode = root['errcode'];
    if (errorCode != null && errorCode.toString() != '0') return null;
    final code = root['code'];
    if (code != null && code.toString() != '0') return null;

    for (final profile in PortalIdentityService._profileMaps(
      root['data'] ?? root,
    )) {
      final uid = profile['userAccount']?.toString().trim() ?? '';
      if (uid.isEmpty) continue;
      return PortalIdentity(
        uid: uid,
        name: PortalIdentityService.extractDisplayName(profile),
        identity: PortalIdentityService.extractIdentity(profile),
      );
    }
    return null;
  }
}

class _CachedPortalIdentity {
  final PortalIdentity identity;
  final DateTime expiresAt;
  final int sessionRevision;

  const _CachedPortalIdentity(
    this.identity,
    this.expiresAt,
    this.sessionRevision,
  );
}
