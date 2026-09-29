import 'dart:convert';
import 'dart:io';

import '../models/account.dart';
import '../models/mobile_campus_user_profile.dart';
import 'account_network_session_service.dart';
import 'auth_service.dart';
import 'campus_session.dart';
import 'logger_service.dart';
import 'mobile_campus_request_signer.dart';
import 'service_endpoints.dart';

class MobileCampusUserAuthenticationException implements Exception {
  final String message;

  const MobileCampusUserAuthenticationException([
    this.message = '移动校园登录状态已失效，请重新登录后重试。',
  ]);

  @override
  String toString() => message;
}

class MobileCampusUserApiException implements Exception {
  final String message;

  const MobileCampusUserApiException(this.message);

  @override
  String toString() => message;
}

/// Reads the mobile campus account profile used for the host account header.
class MobileCampusUserService {
  static const _requestTimeout = Duration(seconds: 12);

  static bool _isValidUserId(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0;
  }

  static Future<MobileCampusUserProfile?> fetchProfile({
    bool forceRefreshCredential = false,
  }) async {
    var account = await AuthService.getCurrentAccount();
    if (account == null) return null;

    if (forceRefreshCredential) {
      final refreshed =
          await CampusSession.client(CampusServices.mobileCampus).refresh();
      if (!refreshed) return null;
      account = await AuthService.getCurrentAccount();
      if (account == null) return null;
    }

    var userId = account.mobileCampusUserId;
    if (userId == null || userId.trim().isEmpty) {
      // skipLogin 成功响应里会带回 userBaseInfo.userId，首次调用时补上。
      final refreshed =
          await CampusSession.client(CampusServices.mobileCampus).refresh();
      if (!refreshed) return null;
      account = await AuthService.getCurrentAccount();
      if (account == null) return null;
      userId = account.mobileCampusUserId;
    }
    if (userId == null || !_isValidUserId(userId.trim())) return null;

    try {
      return await _fetchOnce(account, userId.trim());
    } on MobileCampusUserAuthenticationException {
      final refreshed =
          await CampusSession.client(CampusServices.mobileCampus).refresh();
      if (!refreshed) return null;
      account = await AuthService.getCurrentAccount();
      if (account == null || account.mobileCampusUserId == null) return null;
      return _fetchOnce(account, account.mobileCampusUserId!.trim());
    } on MobileCampusUserApiException {
      return null;
    } catch (error) {
      AppLogger.warn('移动校园用户资料请求失败 (${error.runtimeType})');
      return null;
    }
  }

  static Future<MobileCampusUserProfile?> _fetchOnce(
    Account account,
    String userId,
  ) async {
    final response = await CampusSession.client(
      CampusServices.mobileCampus,
    ).request(
      'POST',
      CampusServiceEndpoints.mobileCampusUserInfoUri.toString(),
      body: MobileCampusRequestSigner.signedBody({
        'campusType': 1,
        'userId': int.parse(userId),
        'parentUserName': null,
        'wxCode': null,
        'client': null,
        'openId': null,
      }),
      contentType: ContentType.json,
      requestTimeout: _requestTimeout,
      responseTimeout: _requestTimeout,
      throwOnHttpError: false,
      autoExchangeService: false,
      extraHeaders: const {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'cn',
        'Origin': 'file://',
        'X-Requested-With': 'com.lantu.MobileCampus.chd',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Version/4.0 Chrome/139.0 Mobile '
            'Safari/537.36 lantuMobilecampus lantuMC',
      },
    );
    return MobileCampusUserParser.parseResponse(response);
  }
}

class MobileCampusUserParser {
  static MobileCampusUserProfile? parseResponse(
    AccountNetworkResponse response,
  ) {
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden ||
        (response.statusCode >= HttpStatus.multipleChoices &&
            response.statusCode < HttpStatus.badRequest)) {
      throw const MobileCampusUserAuthenticationException();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw MobileCampusUserApiException(
        '移动校园用户资料返回 HTTP ${response.statusCode}',
      );
    }
    final raw =
        response.body.startsWith('\uFEFF')
            ? response.body.substring(1)
            : response.body;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (decoded == null) {
      if (looksLikeAuthenticationPage(raw)) {
        throw const MobileCampusUserAuthenticationException();
      }
      throw const MobileCampusUserApiException('移动校园用户资料返回了无法识别的数据');
    }
    return parseProfile(decoded);
  }

  static MobileCampusUserProfile? parseProfile(Object? raw) {
    final map = _asMapOrNull(raw);
    if (map == null) return null;
    throwIfFailed(map);
    final base = _asMapOrNull(map['userBaseInfo']);
    final login = _asMapOrNull(map['userLoginInfo']);
    if (base == null || login == null) return null;

    final userId = _string(base['userId']);
    if (!_isValidUserId(userId)) return null;

    final userName = _firstNonEmpty(
      _string(login['userName']),
      _string(login['parentUserName']),
    );
    final displayName = _firstNonEmpty(
      _string(base['nickName']),
      _string(base['realName']),
    );
    if (userName.isEmpty || displayName.isEmpty) return null;
    final role = _int(base['role']);
    return MobileCampusUserProfile(
      userId: userId,
      userName: userName,
      displayName: displayName,
      role: role,
      identity: MobileCampusUserProfile.identityForRole(role),
    );
  }

  static void throwIfFailed(Map<String, dynamic> map) {
    final msgState = map['msgState'];
    if (msgState != null && msgState.toString() != '1') {
      final message = _string(map['msg']);
      if (_looksLikeAuthenticationFailure(message)) {
        throw MobileCampusUserAuthenticationException(message);
      }
      throw MobileCampusUserApiException(
        message.isEmpty ? '移动校园用户资料请求失败' : message,
      );
    }
    final errorCode = map['errcode'];
    if (errorCode != null && errorCode.toString() != '0') {
      final message = _string(map['errmsg']);
      if (_looksLikeAuthenticationFailure(message)) {
        throw MobileCampusUserAuthenticationException(message);
      }
      throw MobileCampusUserApiException(
        message.isEmpty ? '移动校园用户资料请求失败' : message,
      );
    }
  }

  static bool looksLikeAuthenticationPage(String rawBody) {
    final lower = rawBody.toLowerCase();
    return lower.contains('authserver/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('cas login') ||
        lower.contains('protocol/openid-connect') ||
        (lower.contains('<html') && lower.contains('登录'));
  }

  static bool _looksLikeAuthenticationFailure(String message) {
    final lower = message.toLowerCase();
    return lower.contains('login') ||
        lower.contains('session') ||
        lower.contains('token') ||
        message.contains('登录') ||
        message.contains('未登录') ||
        message.contains('凭证') ||
        message.contains('认证') ||
        message.contains('无权限') ||
        message.contains('无权');
  }

  static String _firstNonEmpty(String first, String second) =>
      first.trim().isEmpty ? second.trim() : first.trim();

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static bool _isValidUserId(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0;
  }

  static int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

  static Map<String, dynamic>? _asMapOrNull(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
