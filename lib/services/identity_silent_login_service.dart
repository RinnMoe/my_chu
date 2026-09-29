import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'auth_service.dart';
import 'campus_session_store.dart';
import 'identity_login_encryptor.dart';
import 'logger_service.dart';
import 'saved_login_credential_service.dart';
import 'scoped_cookie_jar.dart';
import 'service_endpoints.dart';

/// 静默重登结果。
enum IdentityRecoveryOutcome {
  /// 已重新完成统一身份登录并写回账号。
  success,

  /// 本地没有保存的账号密码，只能引导手动登录。
  noSavedCredential,

  /// 上次失败后仍在冷却期，跳过本次尝试。
  coolingDown,

  /// 服务端要求验证码（图形/滑块），静默登录无法完成。
  captchaRequired,

  /// 账号密码校验失败；已保存凭据会被清除。
  invalidCredential,

  /// 网络异常或登录页结构变化等，无法判定凭据是否有效。
  networkError,
}

class IdentitySilentLoginResult {
  final IdentityRecoveryOutcome outcome;
  final String? detail;

  const IdentitySilentLoginResult(this.outcome, [this.detail]);

  bool get isSuccess => outcome == IdentityRecoveryOutcome.success;
}

/// 统一会话探针判定结果。
enum IdentityProbeStatus { authenticated, unauthenticated, indeterminate }

/// 统一身份静默重登：凭证过期时用已保存的账号密码在后台重新完成 CAS 登录。
///
/// 流程与 CHUAuthSDK 的账密登录一致：
/// 1. GET 登录页，解析 `pwdFromId` 的 `lt`/`execution`/`pwdEncryptSalt`；
/// 2. `checkNeedCaptcha.htl` 预判验证码，需要则立即失败（不盲目提交）；
/// 3. 复刻官方 `encrypt.js` 加密密码后 POST `/authserver/login`；
/// 4. 跟随重定向链收集服务 Cookie；
/// 5. 用 `personalInfo/common/getUserInfo` 探针确认统一会话有效；
/// 6. 成功后把新的统一身份 Cookie 写回当前账号与共享网络会话。
///
/// 单飞 + 失败冷却，避免并发请求反复触发 CAS 登录。
class IdentitySilentLoginService {
  IdentitySilentLoginService._();

  static const _connectionTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 12);
  static const _failureCooldown = Duration(minutes: 2);
  static const _maxRedirects = 12;

  static final Map<String, Future<IdentitySilentLoginResult>> _active = {};
  static DateTime? _cooldownUntil;

  /// 测试钩子：替换真实 HTTP 登录流程，用于验证状态机。
  @visibleForTesting
  static Future<IdentitySilentLoginResult> Function(
    SavedLoginCredential credential,
  )?
  debugRunner;

  /// Test seam for the runtime or explicitly requested identity probe.
  @visibleForTesting
  static Future<IdentityProbeStatus> Function(String accountKey)? debugProbe;

  /// 尝试静默恢复统一身份会话；并发调用共享同一次尝试。
  static Future<IdentitySilentLoginResult> tryRecover({
    String? accountKey,
  }) async {
    final activeKey = accountKey ?? '';
    final active = _active[activeKey];
    if (active != null) return active;
    final future = _recover(accountKey: accountKey);
    _active[activeKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_active[activeKey], future)) _active.remove(activeKey);
    }
  }

  /// 测试辅助：重置静态状态。
  @visibleForTesting
  static void debugReset() {
    _active.clear();
    _cooldownUntil = null;
    debugRunner = null;
    debugProbe = null;
  }

  /// Checks the persisted root session without using the credential broker's
  /// cache as proof of validity. The same response classifiers are shared by
  /// explicit identity checks and runtime recovery.
  static Future<IdentityProbeStatus> probeCurrentSession({
    String? accountKey,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null ||
        (accountKey != null && account.accountKey != accountKey)) {
      return IdentityProbeStatus.unauthenticated;
    }
    final probeOverride = debugProbe;
    if (probeOverride != null) return probeOverride(account.accountKey);
    final sessionStore = await CampusSessionStore.open(
      accountKey: account.accountKey,
    );
    final authCookies = await sessionStore.rootCookieHeader();
    return probeCookies(authCookies);
  }

  /// Probes a just-collected interactive-login cookie header before it is
  /// committed to Account storage.
  static Future<IdentityProbeStatus> probeCookies(String authCookies) async {
    if (authCookies.isEmpty) return IdentityProbeStatus.unauthenticated;

    final client = _newClient();
    final jar =
        ScopedCookieJar()
          ..seed(CampusServiceEndpoints.idsAuthUri, authCookies)
          ..seed(CampusServiceEndpoints.identityRealmUri, authCookies);
    try {
      return await _probeUnifiedSession(client, jar);
    } finally {
      client.close(force: true);
    }
  }

  static Future<IdentitySilentLoginResult> _recover({
    String? accountKey,
  }) async {
    final credential = await SavedLoginCredentialService.read();
    if (credential == null) {
      return const IdentitySilentLoginResult(
        IdentityRecoveryOutcome.noSavedCredential,
      );
    }
    final cooldown = _cooldownUntil;
    if (cooldown != null && cooldown.isAfter(DateTime.now())) {
      return const IdentitySilentLoginResult(
        IdentityRecoveryOutcome.coolingDown,
      );
    }

    IdentitySilentLoginResult result;
    try {
      final runner = debugRunner;
      result =
          runner != null
              ? await runner(credential)
              : await _runHttpRecovery(credential, accountKey: accountKey);
    } catch (error) {
      result = const IdentitySilentLoginResult(
        IdentityRecoveryOutcome.networkError,
        '网络或登录页异常',
      );
    }

    switch (result.outcome) {
      case IdentityRecoveryOutcome.success:
        _cooldownUntil = null;
        AppLogger.event(
          level: 'INFO',
          code: 'identity.silent_login.succeeded',
          message: '统一身份静默重登成功',
          domain: 'identity',
        );
      case IdentityRecoveryOutcome.invalidCredential:
        // 密码已失效：清除本地保存，避免后续反复失败，并进入冷却。
        await SavedLoginCredentialService.clearCredential();
        _cooldownUntil = DateTime.now().add(_failureCooldown);
        AppLogger.event(
          level: 'WARN',
          code: 'identity.silent_login.invalid_credential',
          message: '统一身份静默重登失败，账号密码已失效并清除本地保存',
          domain: 'identity',
        );
      case IdentityRecoveryOutcome.captchaRequired:
        _cooldownUntil = DateTime.now().add(_failureCooldown);
        AppLogger.event(
          level: 'WARN',
          code: 'identity.silent_login.captcha_required',
          message: '统一身份静默重登需要验证码',
          domain: 'identity',
        );
      case IdentityRecoveryOutcome.networkError:
        _cooldownUntil = DateTime.now().add(_failureCooldown);
        AppLogger.event(
          level: 'WARN',
          code: 'identity.silent_login.network_error',
          message: '统一身份静默重登遇到网络或登录页异常',
          domain: 'identity',
        );
      case IdentityRecoveryOutcome.noSavedCredential:
      case IdentityRecoveryOutcome.coolingDown:
        break;
    }
    return result;
  }

  static Future<IdentitySilentLoginResult> _runHttpRecovery(
    SavedLoginCredential credential, {
    String? accountKey,
  }) async {
    final client = _newClient();
    final jar = ScopedCookieJar();
    final loginUri = Uri.parse(
      '${CampusServiceEndpoints.idsAuthBase}/authserver/login',
    );
    try {
      // 1. 登录页：拿表单隐藏字段与会话 Cookie。
      final page = await _get(client, loginUri, jar);
      if (page == null) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.networkError,
          '登录页请求失败',
        );
      }
      final formFields = _parseLoginForm(page);
      if (formFields == null) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.networkError,
          '登录表单解析失败',
        );
      }

      // 2. 验证码预判：需要验证码时静默登录无法完成。
      if (await _needsCaptcha(client, jar, credential.username)) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.captchaRequired,
        );
      }

      // 3. 加密密码并提交账密登录表单。
      final encrypted = IdentityLoginEncryptor.encryptPassword(
        credential.password,
        formFields.salt,
      );
      final body = _formUrlEncoded({
        'username': credential.username,
        'password': encrypted,
        'captcha': '',
        'lt': formFields.lt,
        'dllt': 'generalLogin',
        'cllt': 'userNameLogin',
        'execution': formFields.execution,
        '_eventId': 'submit',
      });
      final postResult = await _postAndFollow(
        client,
        loginUri,
        jar,
        body: body,
      );
      if (postResult == null) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.networkError,
          '登录请求失败',
        );
      }
      AppLogger.event(
        level: 'INFO',
        code: 'identity.silent_login.form_result',
        message: '静默重登表单处理完成',
        domain: 'identity',
        fields: {
          'leftLoginPage': postResult.leftLoginPage,
          'failure': postResult.failure?.name ?? 'none',
        },
      );
      if (!postResult.leftLoginPage) {
        final failure = postResult.failure;
        return IdentitySilentLoginResult(
          failure ?? IdentityRecoveryOutcome.networkError,
          switch (failure) {
            IdentityRecoveryOutcome.invalidCredential => '登录页返回失败提示',
            IdentityRecoveryOutcome.captchaRequired => '登录页要求验证码',
            _ => '登录页状态无法判定 (${_safeUri(postResult.finalUri)})',
          },
        );
      }

      // 4. 探针确认统一会话有效。
      final probe = await _probeUnifiedSession(client, jar);
      if (probe != IdentityProbeStatus.authenticated) {
        return IdentitySilentLoginResult(
          probe == IdentityProbeStatus.unauthenticated
              ? IdentityRecoveryOutcome.invalidCredential
              : IdentityRecoveryOutcome.networkError,
          probe == IdentityProbeStatus.unauthenticated
              ? '统一会话探针未认证'
              : '统一会话探针无法判定 (${_safeUri(_probeUri)})',
        );
      }

      // 5. 写回账号与共享网络会话。
      final authCookies = jar.headerFor(CampusServiceEndpoints.idsAuthUri);
      if (authCookies.isEmpty) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.networkError,
          '未收集到统一身份 Cookie',
        );
      }
      final account = await AuthService.getCurrentAccount();
      if (account == null ||
          (accountKey != null && account.accountKey != accountKey)) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.networkError,
          '当前无登录账号',
        );
      }
      final updated = await AuthService.replaceIdentityCookies(
        account.accountKey,
        authCookies,
      );
      if (updated == null) {
        return const IdentitySilentLoginResult(
          IdentityRecoveryOutcome.networkError,
          '统一身份 Cookie 写回失败',
        );
      }
      return const IdentitySilentLoginResult(IdentityRecoveryOutcome.success);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _get(
    HttpClient client,
    Uri uri,
    ScopedCookieJar jar,
  ) async {
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      final cookies = jar.headerFor(uri);
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      _setBrowserHeaders(request);
      request.followRedirects = false;
      final response = await request.close().timeout(_requestTimeout);
      jar.collect(uri, response);
      final body = await _readBody(response);
      if (response.statusCode != HttpStatus.ok) return null;
      return body;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _needsCaptcha(
    HttpClient client,
    ScopedCookieJar jar,
    String username,
  ) async {
    final uri = Uri.parse(
      '${CampusServiceEndpoints.idsAuthBase}/authserver/checkNeedCaptcha.htl',
    ).replace(
      queryParameters: {
        'username': username,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      final cookies = jar.headerFor(uri);
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      _setBrowserHeaders(request);
      request.followRedirects = false;
      final response = await request.close().timeout(_requestTimeout);
      jar.collect(uri, response);
      final body = await _readBody(response);
      if (response.statusCode != HttpStatus.ok) return false;
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['isNeed'] == true;
    } catch (_) {
      // 预判失败不阻断登录尝试，与参考实现一致。
      return false;
    }
  }

  /// POST 登录表单并手动跟随重定向，返回是否离开了登录页及失败分类。
  static Future<
    ({bool leftLoginPage, Uri finalUri, IdentityRecoveryOutcome? failure})?
  >
  _postAndFollow(
    HttpClient client,
    Uri loginUri,
    ScopedCookieJar jar, {
    required String body,
  }) async {
    try {
      final request = await client
          .postUrl(loginUri)
          .timeout(_connectionTimeout);
      final cookies = jar.headerFor(loginUri);
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      _setBrowserHeaders(request);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.headers.set('Origin', CampusServiceEndpoints.idsAuthBase);
      request.headers.set('Referer', loginUri.toString());
      request.followRedirects = false;
      request.write(body);

      var uri = loginUri;
      var response = await request.close().timeout(_requestTimeout);
      jar.collect(uri, response);

      for (var hop = 0; hop < _maxRedirects; hop++) {
        final isRedirect =
            response.statusCode >= HttpStatus.movedPermanently &&
            response.statusCode < HttpStatus.badRequest;
        final location =
            isRedirect
                ? response.headers.value(HttpHeaders.locationHeader)
                : null;
        final text = await _readBody(response);
        if (!isRedirect || location == null || location.isEmpty) {
          // 未重定向：按最终 URI 与正文分类，离开登录页后交给探针确认。
          final stillLogin = _isIdsLoginPage(uri);
          return (
            leftLoginPage: !stillLogin,
            finalUri: uri,
            failure: classifyPostLoginFailure(
              leftLoginPage: !stillLogin,
              finalUri: uri,
              body: text,
            ),
          );
        }
        uri = uri.resolve(location);
        final next = await client.getUrl(uri).timeout(_connectionTimeout);
        final nextCookies = jar.headerFor(uri);
        if (nextCookies.isNotEmpty) {
          next.headers.set(HttpHeaders.cookieHeader, nextCookies);
        }
        _setBrowserHeaders(next);
        next.followRedirects = false;
        response = await next.close().timeout(_requestTimeout);
        jar.collect(uri, response);
      }
      final stillLogin = _isIdsLoginPage(uri);
      return (
        leftLoginPage: !stillLogin,
        finalUri: uri,
        failure: stillLogin ? IdentityRecoveryOutcome.networkError : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// `personalInfo/common/getUserInfo` 探针：统一会话有效时返回已认证。
  static Future<IdentityProbeStatus> _probeUnifiedSession(
    HttpClient client,
    ScopedCookieJar jar,
  ) async {
    final uri = _probeUri;
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      final cookies = jar.headerFor(uri);
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      _setBrowserHeaders(request);
      request.followRedirects = false;
      final response = await request.close().timeout(_requestTimeout);
      jar.collect(uri, response);
      final body = await _readBody(response);
      final probe = classifyProbeResponse(
        statusCode: response.statusCode,
        location: response.headers.value(HttpHeaders.locationHeader),
        body: body,
      );
      AppLogger.event(
        level: 'INFO',
        code: 'identity.silent_login.probe_user_info',
        message: '统一身份用户信息探针完成',
        domain: 'identity',
        fields: {'result': probe.name},
      );
      if (probe == IdentityProbeStatus.authenticated) {
        return IdentityProbeStatus.authenticated;
      }
      // `getUserInfo` uses the personalInfo path session, which may not be
      // present in a freshly collected CAS cookie set. The authserver index
      // probe validates the same root identity session without depending on
      // that path-specific application session.
      final secondary = await _probeAuthServerIndex(client, jar);
      AppLogger.event(
        level: 'INFO',
        code: 'identity.silent_login.probe_index',
        message: '统一身份入口探针完成',
        domain: 'identity',
        fields: {'result': secondary.name},
      );
      return combineProbeStatuses(primary: probe, secondary: secondary);
    } catch (_) {
      return IdentityProbeStatus.indeterminate;
    }
  }

  static final Uri _probeUri = Uri.parse(
    '${CampusServiceEndpoints.idsAuthBase}/personalInfo/common/getUserInfo',
  );

  static final Uri _authServerIndexUri = Uri.parse(
    '${CampusServiceEndpoints.idsAuthBase}/authserver/index.do',
  );

  /// 二级探针：统一身份根会话有效时，`index.do` 会跳转到个人中心。
  static Future<IdentityProbeStatus> _probeAuthServerIndex(
    HttpClient client,
    ScopedCookieJar jar,
  ) async {
    final uri = _authServerIndexUri;
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      final cookies = jar.headerFor(uri);
      if (cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      _setBrowserHeaders(request);
      request.followRedirects = false;
      final response = await request.close().timeout(_requestTimeout);
      jar.collect(uri, response);
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      AppLogger.event(
        level: 'INFO',
        code: 'identity.silent_login.probe_index_response',
        message: '统一身份入口响应已读取',
        domain: 'identity',
        statusCode: response.statusCode,
        fields: {
          'personCenter':
              location?.contains('/personalInfo/personCenter') ?? false,
          'login': location?.contains('/authserver/login') ?? false,
        },
      );
      return classifyIndexResponse(
        statusCode: response.statusCode,
        location: location,
      );
    } catch (_) {
      return IdentityProbeStatus.indeterminate;
    }
  }

  @visibleForTesting
  static IdentityProbeStatus classifyIndexResponse({
    required int statusCode,
    String? location,
  }) {
    if (statusCode < HttpStatus.movedPermanently ||
        statusCode >= HttpStatus.badRequest) {
      return IdentityProbeStatus.indeterminate;
    }
    final target = location ?? '';
    if (target.contains('/authserver/login')) {
      return IdentityProbeStatus.unauthenticated;
    }
    if (target.contains('/personalInfo/personCenter') ||
        target.contains('/personalInfo/personalMobile/index.html')) {
      return IdentityProbeStatus.authenticated;
    }
    return IdentityProbeStatus.indeterminate;
  }

  /// 探针响应分类：仅明确未认证返回 [IdentityProbeStatus.unauthenticated]，
  /// 空正文、非 JSON、异常等一律返回不可判定，避免误删仍有效凭据。
  @visibleForTesting
  static IdentityProbeStatus classifyProbeResponse({
    required int statusCode,
    String? location,
    required String body,
  }) {
    if (statusCode >= HttpStatus.movedPermanently &&
        statusCode < HttpStatus.badRequest) {
      final target = location ?? '';
      return target.contains('/authserver/login')
          ? IdentityProbeStatus.unauthenticated
          : IdentityProbeStatus.indeterminate;
    }
    if (statusCode != HttpStatus.ok) {
      return IdentityProbeStatus.indeterminate;
    }

    final text = body.trim();
    if (text.isEmpty) return IdentityProbeStatus.indeterminate;

    final decoded = _tryDecodeJson(text);
    if (decoded is Map) {
      final code = decoded['code']?.toString();
      final message = decoded['message']?.toString();
      final datas = decoded['datas'];
      if (code == '0' &&
          message == 'SUCCESS' &&
          datas is Map &&
          _hasNonEmptyUid(datas)) {
        return IdentityProbeStatus.authenticated;
      }
      return _looksLikeAuthFailure(decoded)
          ? IdentityProbeStatus.unauthenticated
          : IdentityProbeStatus.indeterminate;
    }

    final lower = text.toLowerCase();
    if (lower.contains('authserver/login') ||
        lower.contains('cas login') ||
        lower.contains('protocol/openid-connect') ||
        lower.contains('统一身份认证') ||
        lower.contains('未登录') ||
        lower.contains('请先登录') ||
        lower.contains('登录已失效') ||
        lower.contains('登录过期')) {
      return IdentityProbeStatus.unauthenticated;
    }
    return IdentityProbeStatus.indeterminate;
  }

  /// Combines the two independent identity probes. A successful authserver
  /// probe is sufficient even when the personalInfo API rejects a newly
  /// collected path-scoped session cookie.
  @visibleForTesting
  static IdentityProbeStatus combineProbeStatuses({
    required IdentityProbeStatus primary,
    required IdentityProbeStatus secondary,
  }) {
    if (primary == IdentityProbeStatus.authenticated ||
        secondary == IdentityProbeStatus.authenticated) {
      return IdentityProbeStatus.authenticated;
    }
    if (primary == IdentityProbeStatus.unauthenticated ||
        secondary == IdentityProbeStatus.unauthenticated) {
      return IdentityProbeStatus.unauthenticated;
    }
    return IdentityProbeStatus.indeterminate;
  }

  /// 登录页失败分类：离开登录页后不按正文判失败，防止品牌文案误伤。
  @visibleForTesting
  static IdentityRecoveryOutcome? classifyPostLoginFailure({
    required bool leftLoginPage,
    required Uri finalUri,
    required String body,
  }) {
    if (leftLoginPage) return null;
    if (!_isIdsLoginPage(finalUri)) {
      return IdentityRecoveryOutcome.networkError;
    }
    if (_containsAny(body, const ['密码错误', '用户名或密码错误', '登录失败'])) {
      return IdentityRecoveryOutcome.invalidCredential;
    }
    if (_containsAny(body, const [
      '验证码不能为空',
      '请输入正确验证码',
      '验证码错误',
      '请完成滑块验证',
      '滑块验证',
    ])) {
      return IdentityRecoveryOutcome.captchaRequired;
    }
    return IdentityRecoveryOutcome.networkError;
  }

  static bool _hasNonEmptyUid(Map datas) {
    final uid = datas['uid']?.toString().trim() ?? '';
    return uid.isNotEmpty;
  }

  static bool _looksLikeAuthFailure(Map decoded) {
    final message =
        (decoded['message'] ?? decoded['msg'] ?? decoded['errmsg'] ?? '')
            .toString()
            .toLowerCase();
    return _containsAny(message, const [
      'login',
      'session',
      'credential',
      'token',
      '登录',
      '未登录',
      '认证',
      '凭证',
      '无权限',
      '无权',
      '权限不足',
    ]);
  }

  static bool _containsAny(String text, List<String> markers) =>
      markers.any(text.contains);

  static Object? _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String _safeUri(Uri uri) => '${uri.host}${uri.path}';

  static bool _isIdsLoginPage(Uri uri) {
    return uri.host == 'ids.chd.edu.cn' &&
        uri.path.contains('/authserver/login');
  }

  static ({String lt, String execution, String salt})? _parseLoginForm(
    String page,
  ) {
    try {
      final document = html_parser.parse(page);
      final form = document.querySelector('form#pwdFromId');
      final scope = form ?? document;
      final salt = scope.querySelector('#pwdEncryptSalt')?.attributes['value'];
      if (salt == null || salt.isEmpty) return null;
      final lt = scope.querySelector('input[name="lt"]')?.attributes['value'];
      final execution =
          scope.querySelector('input[name="execution"]')?.attributes['value'];
      if (execution == null || execution.isEmpty) return null;
      return (lt: lt ?? '', execution: execution, salt: salt);
    } catch (_) {
      return null;
    }
  }

  static String _formUrlEncoded(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  static Future<String> _readBody(HttpClientResponse response) async {
    try {
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
    } on HttpException {
      // 部分校园服务会提前关闭响应体；已收集的 Cookie 仍然有效。
      return '';
    } on TimeoutException {
      return '';
    }
  }

  static HttpClient _newClient() {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
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
}
