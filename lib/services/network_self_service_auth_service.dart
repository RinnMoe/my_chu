import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

import '../models/account.dart';
import 'auth_service.dart';
import 'logger_service.dart';
import 'network_self_service_ocr.dart';
import 'saved_login_credential_service.dart';
import 'scoped_cookie_jar.dart';
import 'service_endpoints.dart';
import 'session_runtime_fence.dart';

/// Host-owned state of the network self-service login flow.
enum NetworkSelfServiceAuthStatus {
  ready,
  missingCredential,
  captchaInputRequired,
  smsInputRequired,
  invalidCredential,
  networkError,
  coolingDown,
}

/// Public login state. It intentionally contains only a short-lived captcha
/// image and opaque challenge ID; cookies, CSRF values, passwords and RSA
/// ciphertext remain inside [NetworkSelfServiceAuthService].
class NetworkSelfServiceAuthState {
  final NetworkSelfServiceAuthStatus status;
  final String? challengeId;
  final Uint8List? captchaBytes;
  final String? message;

  const NetworkSelfServiceAuthState(
    this.status, {
    this.challengeId,
    this.captchaBytes,
    this.message,
  });

  bool get isReady => status == NetworkSelfServiceAuthStatus.ready;
}

/// A successful service session returned only to the credential broker.
class NetworkSelfServiceLoginSession {
  final String cookieHeader;

  const NetworkSelfServiceLoginSession(this.cookieHeader);
}

/// Core coordinator for the Yii self-service portal at port 8800.
///
/// The coordinator is deliberately independent of feature widgets. It owns
/// the temporary cookie jar, login form state, RSA encryption and captcha/SMS
/// challenges. A feature can submit an opaque challenge ID, but never receives
/// the session or credential values.
class NetworkSelfServiceAuthService {
  NetworkSelfServiceAuthService._();

  static const _challengeLifetime = Duration(minutes: 2);
  static const _failureCooldown = Duration(minutes: 2);
  static const _connectionTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 12);
  static const _maxCaptchaOcrAttempts = 3;

  static final Map<String, _NetworkSelfServiceTransaction> _transactions = {};
  static final Map<String, Future<NetworkSelfServiceLoginSession?>> _active =
      {};
  static final Map<String, NetworkSelfServiceAuthState> _states = {};
  static final Map<String, DateTime> _cooldownUntil = {};

  /// Test seam for the non-HTTP part of the broker.
  @visibleForTesting
  static Future<NetworkSelfServiceLoginSession?> Function(
    Account account,
    SessionRuntimeFence fence,
  )?
  debugAcquire;

  /// Test-only RSA smoke-test seam. Production callers use [acquire], which
  /// keeps the encrypted value inside this coordinator.
  @visibleForTesting
  static String encryptPasswordForTesting(String password, String pem) {
    return _encryptPassword(password, pem);
  }

  /// Starts or resumes one account-scoped login flight. The callback is
  /// supplied by [CampusServiceSessionService] so a service invalidation can
  /// cancel a transaction without exposing the generation implementation.
  static Future<NetworkSelfServiceLoginSession?> acquire(
    Account account, {
    required SessionRuntimeFence fence,
  }) async {
    final override = debugAcquire;
    if (override != null) {
      final result = await override(account, fence);
      if (result != null) {
        _states[account.accountKey] = const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.ready,
        );
      }
      return result;
    }

    final activeKey = _activeKey(fence);
    final running = _active[activeKey];
    if (running != null) return running;

    final future = _acquire(account, fence: fence);
    _active[activeKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_active[activeKey], future)) _active.remove(activeKey);
    }
  }

  static Future<NetworkSelfServiceLoginSession?> _acquire(
    Account account, {
    required SessionRuntimeFence fence,
  }) async {
    final key = account.accountKey;
    if (!_fenceIsCurrent(fence)) {
      _setState(
        key,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.networkError,
          message: '账号状态已变化，请重试。',
        ),
      );
      return null;
    }

    final cooldown = _cooldownUntil[key];
    if (cooldown != null && cooldown.isAfter(DateTime.now())) {
      _setState(
        key,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.coolingDown,
          message: '登录失败次数较多，请稍后再试。',
        ),
      );
      return null;
    }

    var transaction = _transactions[key];
    if (transaction != null &&
        (!_transactionIsCurrent(transaction) ||
            transaction.expiresAt.isBefore(DateTime.now()))) {
      _discardTransaction(key, transaction);
      transaction = null;
    }
    if (transaction != null) {
      if (transaction.captchaCode == null ||
          (transaction.smsRequired &&
              transaction.smsCode == null &&
              transaction.validatedSmsCode == null)) {
        return null;
      }
      return _continueTransaction(transaction);
    }

    final credential = await SavedLoginCredentialService.read();
    if (credential == null) {
      _setState(
        key,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.missingCredential,
          message: '请退出 MyCHU 后重新进行统一身份登录；登录成功后账号凭据会自动安全保存。',
        ),
      );
      return null;
    }

    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    client.badCertificateCallback =
        (certificate, host, port) => CampusServiceEndpoints.isChdHost(host);
    transaction = _NetworkSelfServiceTransaction(
      accountKey: key,
      fence: fence,
      username: credential.username,
      client: client,
    );
    _transactions[key] = transaction;

    try {
      final login = await _request(
        transaction,
        'GET',
        CampusServiceEndpoints.networkSelfServiceLoginUri,
      );
      if (!_fenceIsCurrent(fence)) {
        _discardTransaction(key, transaction);
        return null;
      }
      if (login.statusCode != HttpStatus.ok) {
        return _failTransaction(key, '登录页暂时不可用，请稍后重试。', transaction);
      }
      final document = html_parser.parse(_decode(login.bytes));
      final csrfToken =
          document
              .querySelector('meta[name="csrf-token"]')
              ?.attributes['content']
              ?.replaceAll(RegExp(r'\s+'), '') ??
          '';
      final csrfParam =
          document
              .querySelector('meta[name="csrf-param"]')
              ?.attributes['content']
              ?.trim() ??
          '_csrf-8800';
      final publicKey =
          document.querySelector('#public')?.attributes['value']?.trim() ?? '';
      if (csrfToken.isEmpty || publicKey.isEmpty) {
        return _failTransaction(key, '登录页结构已变化，请稍后重试。', transaction);
      }
      transaction
        ..csrfToken = csrfToken
        ..csrfParam = csrfParam
        ..encryptedPassword = _encryptPassword(credential.password, publicKey);

      await _fetchCaptcha(transaction);
      for (var attempt = 0; attempt < _maxCaptchaOcrAttempts; attempt++) {
        if (attempt > 0) {
          // OCR retries only replace the image. Keep the original local
          // challenge ID and expiry so the retry remains one UI challenge.
          await _fetchCaptcha(transaction, updateChallengeMetadata: false);
        }
        final candidate = await NetworkSelfServiceOcr.recognize(
          transaction.captchaBytes!,
        );
        if (!_transactionIsCurrent(transaction)) {
          _discardTransaction(key, transaction);
          return null;
        }
        if (candidate != null) {
          transaction.captchaCode = candidate;
          return await _continueTransaction(transaction);
        }
        AppLogger.event(
          level: 'WARN',
          code: 'network.self_service.captcha.ocr_failed',
          message: '网络自服验证码识别失败',
          attempt: attempt + 1,
        );
      }
      // A disagreement or unavailable recognizer must never be submitted.
      // Leave the latest challenge for manual entry after bounded retries.
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.captcha.ocr_exhausted',
        message: '网络自服验证码识别失败，已转为手动输入',
      );
      _showCaptcha(transaction);
      return null;
    } on _NetworkSelfServiceRequestException catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.request_failed',
        message: '网络自服登录请求失败',
        fields: {'phase': error.kind},
        exceptionType: error.runtimeType.toString(),
      );
      return _failTransaction(key, '网络自服暂时无法连接，请稍后重试。', transaction);
    } catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.login_failed',
        message: '网络自服登录流程失败',
        exceptionType: error.runtimeType.toString(),
      );
      return _failTransaction(key, '网络自服登录暂时失败，请稍后重试。', transaction);
    }
  }

  static Future<NetworkSelfServiceLoginSession?> _continueTransaction(
    _NetworkSelfServiceTransaction transaction,
  ) async {
    final key = transaction.accountKey;
    try {
      if (!_transactionIsCurrent(transaction)) {
        _discardTransaction(key, transaction);
        return null;
      }
      if (transaction.captchaCode != null && !transaction.userValidated) {
        final response = await _request(
          transaction,
          'POST',
          CampusServiceEndpoints.networkSelfServiceValidateUserUri,
          body: _formBody({
            'LoginForm[username]': transaction.username,
            'LoginForm[password]': transaction.encryptedPassword,
            'LoginForm[verifyCode]': transaction.captchaCode!,
          }),
          headers: _ajaxHeaders(transaction),
          contentType: _formContentType,
        );
        if (!_transactionIsCurrent(transaction)) {
          _discardTransaction(key, transaction);
          return null;
        }
        final result = _jsonObject(response.bytes);
        if (response.statusCode != HttpStatus.ok || result == null) {
          AppLogger.event(
            level: 'WARN',
            code: 'network.self_service.captcha.validation_failed',
            message: '网络自服验证码校验失败',
            exceptionType: 'HttpStatus',
            statusCode: response.statusCode,
          );
          return _failTransaction(key, '账号或验证码校验失败，请稍后重试。', transaction);
        }
        if (result['success'] != true) {
          if (_looksLikeInvalidCredential(result['message'])) {
            return _invalidCredential(key, transaction);
          }
          AppLogger.event(
            level: 'WARN',
            code: 'network.self_service.captcha.validation_retry',
            message: '网络自服验证码校验失败，已刷新验证码',
          );
          await _fetchCaptcha(transaction);
          _showCaptcha(transaction, message: '验证码未通过，请重新输入。');
          if (identical(_transactions[key], transaction)) {
            transaction.captchaCode = null;
          }
          return null;
        }
        AppLogger.event(
          level: 'INFO',
          code: 'network.self_service.captcha.validation_succeeded',
          message: '网络自服验证码校验成功',
        );
        transaction.userValidated = true;
        if (result['inputSms'] == true) {
          transaction.smsRequired = true;
          transaction.smsCode = null;
          _setStateForTransaction(
            transaction,
            NetworkSelfServiceAuthState(
              NetworkSelfServiceAuthStatus.smsInputRequired,
              challengeId: transaction.challengeId,
              message: '请输入发送到绑定手机的短信验证码。',
            ),
          );
          return null;
        }
      }

      if (transaction.userValidated && transaction.smsCode != null) {
        final submittedSmsCode = transaction.smsCode!;
        final response = await _request(
          transaction,
          'POST',
          CampusServiceEndpoints.networkSelfServiceValidateSmsUri,
          body: _formBody({
            'uname': transaction.username,
            'code': submittedSmsCode,
          }),
          headers: _ajaxHeaders(transaction),
          contentType: _formContentType,
        );
        if (!_transactionIsCurrent(transaction)) {
          _discardTransaction(key, transaction);
          return null;
        }
        final result = _jsonObject(response.bytes);
        if (response.statusCode != HttpStatus.ok ||
            result?['success'] != true) {
          _setStateForTransaction(
            transaction,
            NetworkSelfServiceAuthState(
              NetworkSelfServiceAuthStatus.smsInputRequired,
              challengeId: transaction.challengeId,
              message: '短信验证码不正确或已过期，请重试。',
            ),
          );
          return null;
        }
        transaction.validatedSmsCode = submittedSmsCode;
        transaction.smsCode = null;
      }

      final response = await _request(
        transaction,
        'POST',
        CampusServiceEndpoints.networkSelfServiceLoginUri,
        body: _formBody({
          transaction.csrfParam: transaction.csrfToken,
          'LoginForm[username]': transaction.username,
          'LoginForm[password]': transaction.encryptedPassword,
          'LoginForm[smsCode]': transaction.validatedSmsCode ?? '',
          'LoginForm[verifyCode]': transaction.captchaCode!,
        }),
        contentType: _formContentType,
      );
      if (!_transactionIsCurrent(transaction)) {
        _discardTransaction(key, transaction);
        return null;
      }
      final location = response.location;
      final resolved =
          location == null || location.isEmpty
              ? null
              : CampusServiceEndpoints.networkSelfServiceLoginUri.resolve(
                location,
              );
      if (response.statusCode < HttpStatus.multipleChoices ||
          response.statusCode >= HttpStatus.badRequest ||
          resolved?.scheme !=
              CampusServiceEndpoints.networkSelfServiceLoginUri.scheme ||
          resolved?.host !=
              CampusServiceEndpoints.networkSelfServiceLoginUri.host ||
          resolved?.port !=
              CampusServiceEndpoints.networkSelfServiceLoginUri.port ||
          resolved?.path !=
              CampusServiceEndpoints.networkSelfServiceHomeUri.path) {
        return _failTransaction(key, '账号或验证码校验失败，请稍后重试。', transaction);
      }

      final home = await _request(
        transaction,
        'GET',
        CampusServiceEndpoints.networkSelfServiceHomeUri,
      );
      if (!_transactionIsCurrent(transaction)) {
        _discardTransaction(key, transaction);
        return null;
      }
      if (home.statusCode != HttpStatus.ok || _looksLikeLoginHtml(home.bytes)) {
        return _failTransaction(key, '登录状态未建立，请稍后重试。', transaction);
      }
      final cookies = transaction.jar.headerFor(
        CampusServiceEndpoints.networkSelfServiceHomeUri,
      );
      if (cookies.isEmpty) {
        return _failTransaction(key, '登录状态未建立，请稍后重试。', transaction);
      }
      _cooldownUntil.remove(key);
      _setStateForTransaction(
        transaction,
        const NetworkSelfServiceAuthState(NetworkSelfServiceAuthStatus.ready),
      );
      _discardTransaction(key, transaction);
      return NetworkSelfServiceLoginSession(cookies);
    } on _NetworkSelfServiceRequestException catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.request_failed',
        message: '网络自服登录请求失败',
        fields: {'phase': error.kind},
        exceptionType: error.runtimeType.toString(),
      );
      return _failTransaction(key, '网络自服暂时无法连接，请稍后重试。', transaction);
    } catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.login_submit_failed',
        message: '网络自服登录提交失败',
        exceptionType: error.runtimeType.toString(),
      );
      return _failTransaction(key, '网络自服登录暂时失败，请稍后重试。', transaction);
    }
  }

  /// Returns the last host-owned state for an account.
  static NetworkSelfServiceAuthState stateFor(String accountKey) =>
      _states[accountKey] ??
      const NetworkSelfServiceAuthState(
        NetworkSelfServiceAuthStatus.missingCredential,
      );

  /// Records a user correction; the actual request is performed by the
  /// credential broker on the next [CampusServiceSessionService.get] call.
  static bool provideCaptcha(
    String accountKey,
    String challengeId,
    String code,
  ) {
    final transaction = _transactions[accountKey];
    if (transaction == null || transaction.challengeId != challengeId) {
      return false;
    }
    if (transaction.expiresAt.isBefore(DateTime.now())) {
      _discardTransaction(accountKey, transaction);
      _setState(
        accountKey,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.networkError,
          message: '验证码已过期，请重试。',
        ),
      );
      return false;
    }
    if (transaction.userValidated) return false;
    final normalized = code.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(normalized)) return false;
    transaction.captchaCode = normalized;
    return true;
  }

  static bool provideSms(String accountKey, String challengeId, String code) {
    final transaction = _transactions[accountKey];
    if (transaction == null || transaction.challengeId != challengeId) {
      return false;
    }
    if (transaction.expiresAt.isBefore(DateTime.now())) {
      _discardTransaction(accountKey, transaction);
      _setState(
        accountKey,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.networkError,
          message: '短信验证码已过期，请重试。',
        ),
      );
      return false;
    }
    if (!transaction.userValidated) return false;
    final normalized = code.trim();
    if (normalized.isEmpty || normalized.length > 32) return false;
    transaction.smsCode = normalized;
    return true;
  }

  static Future<NetworkSelfServiceAuthState> refreshCaptcha(
    String accountKey,
    String challengeId,
  ) async {
    final transaction = _transactions[accountKey];
    if (transaction == null ||
        transaction.challengeId != challengeId ||
        transaction.userValidated) {
      return stateFor(accountKey);
    }
    try {
      await _fetchCaptcha(transaction);
      if (!identical(_transactions[accountKey], transaction)) {
        transaction.client.close(force: true);
        return stateFor(accountKey);
      }
      transaction.captchaCode = null;
      _showCaptcha(transaction);
    } on _NetworkSelfServiceRequestException catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.captcha.refresh_failed',
        message: '网络自服验证码刷新失败',
        fields: {'phase': error.kind},
        exceptionType: error.runtimeType.toString(),
      );
      _setStateForTransaction(
        transaction,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.networkError,
          message: '验证码刷新失败，请稍后重试。',
        ),
      );
    } catch (error) {
      AppLogger.event(
        level: 'WARN',
        code: 'network.self_service.captcha.refresh_failed',
        message: '网络自服验证码刷新失败',
        exceptionType: error.runtimeType.toString(),
      );
      _setStateForTransaction(
        transaction,
        const NetworkSelfServiceAuthState(
          NetworkSelfServiceAuthStatus.networkError,
          message: '验证码刷新失败，请稍后重试。',
        ),
      );
    }
    return stateFor(accountKey);
  }

  /// Called by account replacement and logout before their session stores are
  /// cleared, so no pending transaction can finish into another account.
  static void clearAccount(String accountKey) {
    _active.removeWhere((key, _) => key.startsWith('$accountKey|'));
    _discardTransaction(accountKey);
    _states.remove(accountKey);
    _cooldownUntil.remove(accountKey);
  }

  static void clearAll() {
    _active.clear();
    for (final key in _transactions.keys.toList()) {
      _discardTransaction(key);
    }
    _states.clear();
    _cooldownUntil.clear();
  }

  static Future<void> _fetchCaptcha(
    _NetworkSelfServiceTransaction transaction, {
    bool updateChallengeMetadata = true,
  }) async {
    final uri = CampusServiceEndpoints.networkSelfServiceCaptchaUri.replace(
      queryParameters: {'v': DateTime.now().microsecondsSinceEpoch.toString()},
    );
    final response = await _request(transaction, 'GET', uri);
    if (response.statusCode != HttpStatus.ok || response.bytes.isEmpty) {
      throw const _NetworkSelfServiceRequestException('captcha');
    }
    transaction.captchaBytes = Uint8List.fromList(response.bytes);
    if (updateChallengeMetadata) {
      transaction
        ..challengeId = _newChallengeId()
        ..expiresAt = DateTime.now().add(_challengeLifetime);
    }
  }

  static void _showCaptcha(
    _NetworkSelfServiceTransaction transaction, {
    String? message,
  }) {
    _setStateForTransaction(
      transaction,
      NetworkSelfServiceAuthState(
        NetworkSelfServiceAuthStatus.captchaInputRequired,
        challengeId: transaction.challengeId,
        captchaBytes: transaction.captchaBytes,
        message: message ?? '正在自动识别失败，请输入图形验证码。',
      ),
    );
  }

  static NetworkSelfServiceLoginSession? _invalidCredential(
    String key,
    _NetworkSelfServiceTransaction transaction,
  ) {
    if (!identical(_transactions[key], transaction)) {
      transaction.client.close(force: true);
      return null;
    }
    _cooldownUntil[key] = DateTime.now().add(_failureCooldown);
    _setState(
      key,
      const NetworkSelfServiceAuthState(
        NetworkSelfServiceAuthStatus.invalidCredential,
        message: '网络自服账号或密码不正确，请在统一身份登录安全设置中更新凭证。',
      ),
    );
    _discardTransaction(key, transaction);
    return null;
  }

  static NetworkSelfServiceLoginSession? _failTransaction(
    String key,
    String message,
    _NetworkSelfServiceTransaction? transaction,
  ) {
    if (transaction != null && !identical(_transactions[key], transaction)) {
      transaction.client.close(force: true);
      return null;
    }
    _cooldownUntil[key] = DateTime.now().add(_failureCooldown);
    _setState(
      key,
      NetworkSelfServiceAuthState(
        NetworkSelfServiceAuthStatus.networkError,
        message: message,
      ),
    );
    _discardTransaction(key, transaction);
    return null;
  }

  static Map<String, String> _ajaxHeaders(
    _NetworkSelfServiceTransaction transaction,
  ) => {
    'X-Requested-With': 'XMLHttpRequest',
    'X-CSRF-Token': transaction.csrfToken,
    'Referer': CampusServiceEndpoints.networkSelfServiceLoginUri.toString(),
  };

  static final _formContentType = ContentType(
    'application',
    'x-www-form-urlencoded',
    charset: 'utf-8',
  );

  static String _formBody(Map<String, String> fields) => fields.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');

  static Future<_NetworkSelfServiceResponse> _request(
    _NetworkSelfServiceTransaction transaction,
    String method,
    Uri uri, {
    String? body,
    Map<String, String> headers = const {},
    ContentType? contentType,
  }) async {
    final request = await transaction.client
        .openUrl(method, uri)
        .timeout(_connectionTimeout);
    request.followRedirects = false;
    final cookieHeader = transaction.jar.headerFor(uri);
    if (cookieHeader.isNotEmpty) request.headers.set('Cookie', cookieHeader);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.headers.set('User-Agent', _userAgent);
    request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
    if (contentType != null) request.headers.contentType = contentType;
    if (body != null) request.write(body);
    final response = await request.close().timeout(_requestTimeout);
    transaction.jar.collect(uri, response);
    final bytes = await response
        .fold<List<int>>(<int>[], (all, chunk) {
          all.addAll(chunk);
          return all;
        })
        .timeout(_requestTimeout);
    return _NetworkSelfServiceResponse(
      statusCode: response.statusCode,
      bytes: bytes,
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  static String _decode(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  static Map<String, dynamic>? _jsonObject(List<int> bytes) {
    try {
      final decoded = jsonDecode(_decode(bytes));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeLoginHtml(List<int> bytes) {
    final document = html_parser.parse(_decode(bytes));
    return document.querySelector('#loginform-username') != null ||
        _decode(bytes).toLowerCase().contains('site/validate-user');
  }

  static bool _looksLikeInvalidCredential(Object? message) {
    final text = message?.toString().toLowerCase() ?? '';
    return text.contains('password') ||
        text.contains('passwd') ||
        text.contains('账号') ||
        text.contains('密码') ||
        text.contains('用户名');
  }

  static String _encryptPassword(String password, String pem) {
    final key = _RsaPublicKeyParser.parse(pem);
    final engine = PKCS1Encoding(RSAEngine());
    final random = FortunaRandom();
    random.seed(
      KeyParameter(
        Uint8List.fromList(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ),
    );
    engine.init(
      true,
      ParametersWithRandom<PublicKeyParameter<RSAPublicKey>>(
        PublicKeyParameter<RSAPublicKey>(key),
        random,
      ),
    );
    return base64Encode(
      engine.process(Uint8List.fromList(utf8.encode(password))),
    );
  }

  static bool _fenceIsCurrent(SessionRuntimeFence fence) => fence.isCurrent(
    currentAccountKey: fence.accountKey,
    currentSessionRevision: AuthService.sessionRevision,
  );

  static bool _transactionIsCurrent(
    _NetworkSelfServiceTransaction transaction,
  ) => _fenceIsCurrent(transaction.fence);

  static String _newChallengeId() {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  static void _setState(String accountKey, NetworkSelfServiceAuthState state) {
    _states[accountKey] = state;
  }

  static void _setStateForTransaction(
    _NetworkSelfServiceTransaction transaction,
    NetworkSelfServiceAuthState state,
  ) {
    if (identical(_transactions[transaction.accountKey], transaction)) {
      _setState(transaction.accountKey, state);
    }
  }

  static String _activeKey(SessionRuntimeFence fence) => fence.fingerprint;

  static void _discardTransaction(
    String accountKey, [
    _NetworkSelfServiceTransaction? expected,
  ]) {
    final transaction = _transactions.remove(accountKey);
    if (expected != null && !identical(transaction, expected)) {
      expected.client.close(force: true);
      if (transaction != null) _transactions[accountKey] = transaction;
      return;
    }
    transaction?.client.close(force: true);
  }

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.6778.200 Mobile Safari/537.36';
}

class _NetworkSelfServiceTransaction {
  final String accountKey;
  final SessionRuntimeFence fence;
  final String username;
  final HttpClient client;
  final ScopedCookieJar jar = ScopedCookieJar();

  String csrfParam = '_csrf-8800';
  String csrfToken = '';
  String encryptedPassword = '';
  String? challengeId;
  Uint8List? captchaBytes;
  DateTime expiresAt = DateTime.now();
  String? captchaCode;
  String? smsCode;
  String? validatedSmsCode;
  bool userValidated = false;
  bool smsRequired = false;

  _NetworkSelfServiceTransaction({
    required this.accountKey,
    required this.fence,
    required this.username,
    required this.client,
  });
}

class _NetworkSelfServiceResponse {
  final int statusCode;
  final List<int> bytes;
  final String? location;

  const _NetworkSelfServiceResponse({
    required this.statusCode,
    required this.bytes,
    required this.location,
  });
}

class _NetworkSelfServiceRequestException implements Exception {
  final String kind;

  const _NetworkSelfServiceRequestException(this.kind);
}

/// Minimal DER reader for the X.509 SubjectPublicKeyInfo emitted by the
/// portal's `-----BEGIN PUBLIC KEY-----` field. PKCS#1 public-key sequences
/// are accepted as well for compatibility with future page changes.
class _RsaPublicKeyParser {
  _RsaPublicKeyParser._();

  static RSAPublicKey parse(String pem) {
    final body = pem
        .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
        .replaceAll(RegExp(r'-----END [^-]+-----'), '')
        .replaceAll(RegExp(r'\s+'), '');
    final bytes = base64Decode(body);
    final reader = _DerReader(bytes);
    reader.expect(0x30);
    final outer = reader.subReader();
    if (outer.peekTag() == 0x30) {
      outer.expect(0x30);
      outer.skipValue();
      outer.expect(0x03);
      final bitString = outer.readBytes();
      if (bitString.isEmpty) throw const FormatException('RSA 公钥为空');
      return _parseRsaSequence(_DerReader(bitString.sublist(1)));
    }
    return _parseRsaContents(outer);
  }

  static RSAPublicKey _parseRsaSequence(_DerReader reader) {
    reader.expect(0x30);
    return _parseRsaContents(reader.subReader());
  }

  static RSAPublicKey _parseRsaContents(_DerReader sequence) {
    sequence.expect(0x02);
    final modulus = _unsignedBigInt(sequence.readBytes());
    sequence.expect(0x02);
    final exponent = _unsignedBigInt(sequence.readBytes());
    if (modulus == BigInt.zero || exponent == BigInt.zero) {
      throw const FormatException('RSA 公钥参数为空');
    }
    return RSAPublicKey(modulus, exponent);
  }

  static BigInt _unsignedBigInt(List<int> bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }
}

class _DerReader {
  final List<int> bytes;
  int offset = 0;

  _DerReader(this.bytes);

  int peekTag() {
    if (offset >= bytes.length) throw const FormatException('DER 数据不完整');
    return bytes[offset];
  }

  void expect(int tag) {
    if (peekTag() != tag) throw const FormatException('DER 标签不匹配');
    offset++;
  }

  int _length() {
    if (offset >= bytes.length) throw const FormatException('DER 长度缺失');
    final first = bytes[offset++];
    if (first & 0x80 == 0) return first;
    final count = first & 0x7f;
    if (count == 0 || count > 4 || offset + count > bytes.length) {
      throw const FormatException('DER 长度无效');
    }
    var result = 0;
    for (var i = 0; i < count; i++) {
      result = (result << 8) | bytes[offset++];
    }
    return result;
  }

  List<int> readBytes() {
    final length = _length();
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('DER 内容不完整');
    }
    final value = bytes.sublist(offset, offset + length);
    offset += length;
    return value;
  }

  _DerReader subReader() => _DerReader(readBytes());

  void skipValue() {
    readBytes();
  }
}
