import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../services/auth_lifecycle_service.dart';
import '../services/platform_compatibility_service.dart';
import '../services/cookie_service.dart';
import '../services/logger_service.dart';
import '../services/saved_login_credential_service.dart';
import '../services/scoped_cookie_jar.dart';
import '../services/service_endpoints.dart';
import '../services/user_error_message.dart';
import '../services/development_mode_service.dart';
import '../services/identity_silent_login_service.dart';
import '../capabilities/dev_visibility.dart';
import '../capabilities/web_view_permission_capability.dart';
import '../capabilities/web_view_error_view.dart';
import '../capabilities/web_view_rendering_policy.dart';
import 'log_page.dart';
import '../widgets/adaptive_login_scaffold.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @visibleForTesting
  static String get debugLoginCaptureScript =>
      _LoginPageState.loginCaptureScript;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// 登录提示正文 + “不再显示”勾选的统一样式。
class _LoginHintContent extends StatelessWidget {
  const _LoginHintContent({
    required this.dontShowAgain,
    required this.onDontShowAgainChanged,
  });

  final bool dontShowAgain;
  final ValueChanged<bool> onDontShowAgainChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '请在页面中完成统一身份登录，完成后将会自动继续。为了避免异常，建议使用校园网完成登录。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: dontShowAgain,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => onDontShowAgainChanged(v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onDontShowAgainChanged(!dontShowAgain),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('不再显示', style: theme.textTheme.bodyMedium),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 无待同意项时的独立登录提示弹窗。
class _LoginHintDialog extends StatefulWidget {
  const _LoginHintDialog({
    required this.title,
    required this.dontShowAgain,
    required this.onDontShowAgainChanged,
    required this.onAcknowledged,
  });

  final Widget title;
  final bool dontShowAgain;
  final ValueChanged<bool> onDontShowAgainChanged;
  final Future<void> Function() onAcknowledged;

  @override
  State<_LoginHintDialog> createState() => _LoginHintDialogState();
}

class _LoginHintDialogState extends State<_LoginHintDialog> {
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.onAcknowledged();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = '暂时无法保存选择，请重试。');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: widget.title,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LoginHintContent(
            dontShowAgain: widget.dontShowAgain,
            onDontShowAgainChanged: widget.onDontShowAgainChanged,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : _finish,
          child: const Text('我知道了'),
        ),
      ],
    );
  }
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  static const _loginOnboardingDismissedKey = 'login_onboarding_v3_dismissed';
  final _webViewPermissions = WebViewPermissionCapability();
  InAppWebViewController? _controller;
  String _lastLoadedUrl = '';
  Timer? _autoConfirmTimer;
  bool _isLoading = true;
  double _loadProgress = 0;
  Future<void> _renderingUpdate = Future<void>.value();
  bool _hintShown = false;
  bool _hintLoading = false;
  bool _isConfirmingLogin = false;
  bool _loginCompleted = false;
  bool _webViewVisible = true;
  String? _webViewError;

  /// 账号密码只在登录表单提交时短暂捕获，并在身份确认成功后保存。
  ({String username, String password})? _capturedLogin;
  bool _credentialNoticeAcknowledged = false;
  bool _captureHandlerRegistered = false;

  /// 在用户读完登录告知后注入的捕获脚本。只在表单提交或登录按钮点击时
  /// 读取表单，不监听 input，也不在用户输入过程中接触原始密码。
  static const loginCaptureScript = '''
(function() {
  if (window.__mychuLoginCaptureInstalled) { return; }
  window.__mychuLoginCaptureInstalled = true;
  function capture() {
    try {
      var usernameInput =
        document.querySelector('.login-main .pwd_login #username') ||
        document.querySelector('#pwdFromId #username');
      var passwordInput =
        document.querySelector('.login-main .pwd_login #password') ||
        document.querySelector('#pwdFromId #password');
      var username = usernameInput ? usernameInput.value : '';
      var password = passwordInput ? passwordInput.value : '';
      if (!username || !password) { return; }
      var payload = JSON.stringify({ username: username, password: password });
      window.__mychuLoginCapture = payload;
      if (window.flutter_inappwebview &&
          window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('mychuCaptureLogin', payload);
      }
    } catch (e) {}
  }
  function clearCapture() {
    document.removeEventListener('submit', capture, true);
    document.removeEventListener('click', clickCapture, true);
    window.__mychuLoginCapture = null;
    window.__mychuLoginCaptureInstalled = false;
  }
  function clickCapture(event) {
    if (event.target && event.target.id === 'login_submit') { capture(); }
  }
  document.addEventListener('submit', capture, true);
  document.addEventListener('click', clickCapture, true);
  window.__mychuClearLoginCapture = clearCapture;
})();
''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 不依赖 WebView 首次加载成功才展示登录提示，避免网络或页面异常延迟安全选择。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureLoginHint());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoConfirmTimer?.cancel();
    unawaited(_clearLoginCapture());
    _capturedLogin = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateWebViewRendering();
  }

  void _updateWebViewRendering() {
    if (!PlatformCompatibilityService.isHarmony &&
        !PlatformCompatibilityService.isAndroid) {
      return;
    }
    // Serialize native calls so a rapid background/foreground transition
    // cannot leave the WebView paused after the app has resumed.
    _renderingUpdate = _renderingUpdate.then((_) async {
      final controller = _controller;
      if (!mounted || controller == null || !_webViewVisible) return;
      try {
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == null || state == AppLifecycleState.resumed) {
          await controller.resume();
        } else {
          await controller.pause();
        }
      } catch (error) {
        AppLogger.warn('登录页面渲染状态更新失败 (${error.runtimeType})');
      }
    });
  }

  void _beginCredentialExchange() {
    void update() => _isConfirmingLogin = true;

    if (mounted) {
      setState(update);
    } else {
      update();
    }
  }

  Future<void> _loadInitialPage() async {
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://ids.chd.edu.cn')),
    );
    AppLogger.info('正在加载统一身份认证页面');
  }

  Future<void> _ensureLoginHint() async {
    if (!mounted || _hintShown || _hintLoading) return;
    _hintShown = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (prefs.getBool(_loginOnboardingDismissedKey) != true) {
        await _showCredentialDisclosure();
        if (!mounted) return;
        await _showLoginHint(prefs);
        if (!mounted) return;
      }
      _credentialNoticeAcknowledged = true;
      final controller = _controller;
      if (controller != null) {
        _registerLoginCaptureHandler(controller);
        await _installLoginCapture(_lastLoadedUrl);
      }
    } catch (error) {
      _hintShown = false;
      AppLogger.warn('登录告知加载失败 (${error.runtimeType})');
      _showLoginHintRetry();
    }
  }

  Future<void> _showCredentialDisclosure() async {
    if (!mounted) return;
    final next = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('提示'),
            content: _credentialDisclosureText(
              Theme.of(context).textTheme.bodyMedium,
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('下一页'),
              ),
            ],
          ),
    );
    if (next != true && mounted) {
      throw StateError('登录告知尚未确认');
    }
  }

  Widget _credentialDisclosureText(TextStyle? style) => Text.rich(
    TextSpan(
      style: style,
      children: const [
        TextSpan(text: '为了实现自动恢复登录功能，当您在 MyCHU 中完成登录后，'),
        TextSpan(
          text: '账号及密码将以安全方式保存在您的设备本地。',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Future<void> _showLoginHint(SharedPreferences prefs) async {
    if (_hintLoading) return;
    _hintLoading = true;
    try {
      if (!mounted) return;
      await _showStandaloneLoginHint(prefs);
    } finally {
      _hintLoading = false;
    }
  }

  Future<void> _showStandaloneLoginHint(SharedPreferences prefs) async {
    if (prefs.getBool(_loginOnboardingDismissedKey) == true || !mounted) return;

    bool dontShowAgain = false;
    final dialog = StatefulBuilder(
      builder:
          (context, setDialogState) => _LoginHintDialog(
            title: const Text('提示'),
            dontShowAgain: dontShowAgain,
            onDontShowAgainChanged:
                (value) => setDialogState(() => dontShowAgain = value),
            onAcknowledged: () async {
              if (dontShowAgain) {
                final saved = await prefs.setBool(
                  _loginOnboardingDismissedKey,
                  true,
                );
                if (!saved) {
                  throw StateError('无法保存登录提示设置');
                }
              }
            },
          ),
    );
    {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => dialog,
      );
    }
  }

  void _showLoginHintRetry() {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('登录提示加载失败，请稍后重试。'),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => unawaited(_ensureLoginHint()),
        ),
      ),
    );
  }

  void _showLoginPageRetry() {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('统一身份认证页面加载失败，请重试。'),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => unawaited(_retryInitialPage()),
        ),
      ),
    );
  }

  void _showWebViewError(Object error) {
    logUserFacingError(UserErrorContext.webView, error, operation: 'login');
    if (!mounted) return;
    setState(() {
      _webViewError = userFacingError(UserErrorContext.webView, error);
      _isLoading = false;
    });
  }

  Future<void> _retryInitialPage() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _webViewError = null;
    });
    try {
      await _loadInitialPage();
    } catch (error) {
      AppLogger.warn('重新加载统一身份认证页面失败 (${error.runtimeType})');
      _showWebViewError(error);
    }
  }

  Future<void> _manualConfirm() async {
    await _confirmLogin(automatic: false);
  }

  void _scheduleAutoConfirm(String url) {
    if (_loginCompleted || _isConfirmingLogin) return;
    if (!_isLikelyLoginProgressUrl(url)) return;

    _autoConfirmTimer?.cancel();
    _autoConfirmTimer = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted || _loginCompleted || _isConfirmingLogin) return;
      if (!await _hasLikelyAuthenticatedCookies(url)) return;
      await _confirmLogin(automatic: true);
    });
  }

  bool _isLikelyLoginProgressUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.endsWith('chd.edu.cn') &&
        (uri.host == 'ids.chd.edu.cn' ||
            uri.host == 'gwwzxy.chd.edu.cn' ||
            uri.path.contains('/authserver') ||
            uri.path.contains('/casLogin'));
  }

  Future<bool> _hasLikelyAuthenticatedCookies(String currentUrl) async {
    final jar = <String, String>{};
    await _collectNativeCookies(jar, [
      currentUrl,
      'https://ids.chd.edu.cn',
      'https://ids.chd.edu.cn/authserver',
      'https://ids.chd.edu.cn/authserver/login',
    ]);
    return _hasLikelyAuthenticatedCookieNames(currentUrl, jar.keys);
  }

  bool _hasLikelyAuthenticatedCookieNames(
    String currentUrl,
    Iterable<String> cookieNames,
  ) {
    final hasCasTicketGrantingCookie = cookieNames.any(
      (key) => key.toUpperCase().contains('CASTGC'),
    );
    if (hasCasTicketGrantingCookie) return true;

    final uri = Uri.tryParse(currentUrl);
    final looksPastLoginForm =
        uri != null &&
        uri.host == 'ids.chd.edu.cn' &&
        !uri.path.contains('/authserver/login');
    final hasIdsSession = cookieNames.any(
      (key) => key.toUpperCase().contains('JSESSIONID'),
    );
    return hasIdsSession && looksPastLoginForm;
  }

  Future<void> _confirmLogin({required bool automatic}) async {
    if (_loginCompleted || _isConfirmingLogin) return;

    _autoConfirmTimer?.cancel();
    _beginCredentialExchange();

    try {
      // 1. 获取 WebView 当前 URL，确定 cookie 的作用域
      final currentUrl = (await _controller?.getUrl())?.toString();
      AppLogger.info('${automatic ? '自动' : '手动'}确认登录，读取 WebView 会话');

      // 2. 从多个 CAS URL 合并 cookies（含 HttpOnly）。
      //    Android CookieManager 按 URL path 匹配，Path=/authserver 的
      //    JSESSIONID/CASTGC 不会出现在 https://ids.chd.edu.cn/ 的结果里。
      final cookieJar = <String, String>{};
      await _collectNativeCookies(cookieJar, [
        if (currentUrl != null) currentUrl,
        'https://ids.chd.edu.cn',
        'https://ids.chd.edu.cn/authserver',
        'https://ids.chd.edu.cn/authserver/login',
        'https://identity.chd.edu.cn',
        'https://identity.chd.edu.cn/auth/realms/chd/protocol/cas/login',
      ]);

      // 3. 补充 JS document.cookie（不含 HttpOnly，但可作参考）
      final jsResult = await _controller?.evaluateJavascript(
        source: 'document.cookie',
      );
      final jsCookies = _normalizeJavaScriptCookieResult(jsResult);
      if (jsCookies.isNotEmpty) {
        AppLogger.info('JS document.cookie → ${jsCookies.length} 字符');
        _mergeCookies(cookieJar, jsCookies);
      }

      final bestCookies = _formatCookieHeader(cookieJar);
      if (bestCookies.isEmpty) {
        await _discardCapturedLogin();
        if (!automatic) {
          _showLoginError('未获取到登录 Cookie，请确认已完成统一身份认证。');
        }
        return;
      }
      if (!_hasLikelyAuthenticatedCookieNames(
        currentUrl ?? '',
        cookieJar.keys,
      )) {
        await _discardCapturedLogin();
        if (!automatic) {
          _showLoginError('统一身份认证尚未完成，请完成登录后再试。');
        }
        return;
      }

      final casCookieJar = <String, String>{};
      await _collectNativeCookies(casCookieJar, [
        'https://ids.chd.edu.cn/authserver',
        'https://ids.chd.edu.cn/authserver/login',
        CampusServiceEndpoints.idsLoginForCampusUri.toString(),
        'https://identity.chd.edu.cn',
        'https://identity.chd.edu.cn/auth/realms/chd/protocol/cas/login',
        // Keep the current identity page last so a path-scoped
        // `/personalInfo/` session is not overwritten by the authserver
        // JSESSIONID with the same cookie name.
        if (_isIdentityHost(currentUrl)) currentUrl!,
      ]);
      final authCookies =
          casCookieJar.isNotEmpty
              ? _formatCookieHeader(casCookieJar)
              : bestCookies;

      final identityProbe = await IdentitySilentLoginService.probeCookies(
        authCookies,
      );
      if (identityProbe != IdentityProbeStatus.authenticated) {
        await _discardCapturedLogin();
        if (!automatic) {
          _showLoginError(
            identityProbe == IdentityProbeStatus.unauthenticated
                ? '统一身份认证尚未生效，请完成登录后再试。'
                : '暂时无法确认统一身份登录状态，请检查网络后重试。',
          );
        }
        return;
      }

      // 4. 只提交已经通过统一身份探针的根凭证；校园服务凭证由宿主后台预热。
      AppLogger.info('统一身份会话已确认，准备进入主界面');
      final account = Account(
        id: Account.createAccountKey(),
        name: 'CHUer',
        loginTime: DateTime.now(),
      );
      await AuthLifecycleService.installInteractiveAccount(
        account,
        rootIdentityCookies: authCookies,
      );
      AppLogger.info('基础登录态已保存，核心校园服务开始后台预热');
      _loginCompleted = true;
      // 仅在登录前明确选择允许保存时，写入本次已验证成功的凭据。
      await _saveCapturedLoginIfAllowed();
      if (mounted) {
        // 先让登录 WebView 离开 Flutter 合成树并完成拆除，再切换到主界面：
        // 全屏平台视图若在渲染进程销毁期间仍被合成，会残留为黑屏。
        setState(() => _webViewVisible = false);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (mounted) widget.onLoginSuccess();
    } catch (error) {
      await _discardCapturedLogin();
      AppLogger.event(
        level: 'ERROR',
        code: 'identity.login.confirm_failed',
        message: '统一身份认证确认失败',
        domain: 'identity',
        exceptionType: error.runtimeType.toString(),
        fields: {'automatic': automatic},
      );
      if (!automatic) {
        _showLoginError(userFacingError(UserErrorContext.webView, error));
      }
    } finally {
      if (mounted) {
        setState(() => _isConfirmingLogin = false);
      } else {
        _isConfirmingLogin = false;
      }
    }
  }

  /// 仅在用户确认新的登录告知后，才注册 JS 桥并安装捕获脚本。
  void _registerLoginCaptureHandler(InAppWebViewController controller) {
    if (!_credentialNoticeAcknowledged || _captureHandlerRegistered) return;
    _captureHandlerRegistered = true;
    controller.addJavaScriptHandler(
      handlerName: 'mychuCaptureLogin',
      callback: (args) {
        final raw = args.isNotEmpty ? (args.first?.toString() ?? '') : '';
        final captured = _parseCapturedLogin(raw);
        if (captured != null) _capturedLogin = captured;
        return null;
      },
    );
  }

  Future<void> _installLoginCapture(String url) async {
    if (!_credentialNoticeAcknowledged || !_captureHandlerRegistered) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'ids.chd.edu.cn') return;
    if (!uri.path.contains('/authserver')) return;
    try {
      await _controller?.evaluateJavascript(source: loginCaptureScript);
    } catch (error) {
      AppLogger.warn('登录表单捕获脚本安装失败 (${error.runtimeType})');
    }
  }

  ({String username, String password})? _parseCapturedLogin(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final username = (decoded['username'] ?? '').toString().trim();
      final password = (decoded['password'] ?? '').toString();
      if (username.isEmpty || password.isEmpty) return null;
      return (username: username, password: password);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearLoginCapture() async {
    try {
      await _controller?.evaluateJavascript(
        source:
            'if (window.__mychuClearLoginCapture) { '
            'window.__mychuClearLoginCapture(); '
            '} else { window.__mychuLoginCapture = null; }',
      );
    } catch (_) {
      // 页面已离开登录页时清理失败可忽略；Dart 内存仍会在 finally 清空。
    }
  }

  Future<void> _discardCapturedLogin() async {
    await _clearLoginCapture();
    _capturedLogin = null;
    if (mounted && _credentialNoticeAcknowledged) {
      await _installLoginCapture(_lastLoadedUrl);
    }
  }

  /// 只保存提交时捕获且已通过统一身份探针确认的凭据。
  Future<void> _saveCapturedLoginIfAllowed() async {
    final captured = _capturedLogin;
    try {
      if (!_credentialNoticeAcknowledged || captured == null) return;
      await SavedLoginCredentialService.save(
        captured.username,
        captured.password,
      );
      AppLogger.info('已保存账号密码用于自动重新登录');
    } catch (error) {
      AppLogger.warn('保存登录信息流程异常 (${error.runtimeType})');
    } finally {
      await _clearLoginCapture();
      _capturedLogin = null;
    }
  }

  Future<void> _collectNativeCookies(
    Map<String, String> jar,
    List<String> urls,
  ) async {
    final seen = <String>{};
    for (final url in urls) {
      if (!seen.add(url)) continue;
      final cookies = await CookieService.getCookies(url);
      if (cookies != null && cookies.isNotEmpty) {
        AppLogger.info('原生 CookieManager 已读取 ${cookies.length} 字符');
        _mergeCookies(jar, cookies);
      } else {
        AppLogger.info('原生 CookieManager 未读取到 cookies');
      }
    }
  }

  bool _isIdentityHost(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    return uri?.host == 'ids.chd.edu.cn' || uri?.host == 'identity.chd.edu.cn';
  }

  void _mergeCookies(Map<String, String> jar, String cookies) {
    jar.addAll(ScopedCookieJar.parseCookieHeader(cookies));
  }

  String _formatCookieHeader(Map<String, String> jar) =>
      jar.entries.map((e) => '${e.key}=${e.value}').join('; ');

  String _normalizeJavaScriptCookieResult(Object? result) {
    if (result == null) return '';
    final text = result.toString();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (_) {
        // Fall back to the raw value below.
      }
    }
    return text;
  }

  void _showLoginError(String message) {
    AppLogger.event(
      level: 'WARN',
      code: 'identity.login.user_error',
      message: message,
      domain: 'identity',
    );
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openLogPage() {
    if (!DevelopmentModeService.isDev) return;

    final route = MaterialPageRoute<void>(builder: (_) => const LogPage());
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (kIsWeb) {
      return _buildWebFallback(theme);
    }

    return _buildWebView(theme);
  }

  Widget _buildWebFallback(ThemeData theme) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('登录'),
          centerTitle: true,
          actions: [
            DevOnly(
              child: IconButton(
                icon: const Icon(Icons.article_outlined),
                tooltip: '查看日志',
                onPressed: _openLogPage,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('统一身份认证登录', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text(
                '请在 Android 真机或模拟器上运行以使用 WebView 登录。\n当前为 Chrome 预览模式。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView(ThemeData theme) {
    final body = _buildWebViewBody(theme);
    return AdaptiveLoginScaffold(
      onOpenLog: _openLogPage,
      onConfirm: _manualConfirm,
      isConfirming: _isConfirmingLogin,
      child: body,
    );
  }

  Widget _buildWebViewBody(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_webViewVisible)
          InAppWebView(
            initialSettings: WebViewRenderingPolicy.visible(
              InAppWebViewSettings(
                javaScriptEnabled: true,
                geolocationEnabled: true,
              ),
            ),
            onWebViewCreated: (controller) async {
              _controller = controller;
              _updateWebViewRendering();
              try {
                await _loadInitialPage();
              } catch (error) {
                AppLogger.warn('统一身份认证页面加载失败 (${error.runtimeType})');
                _showWebViewError(error);
              }
            },
            onPermissionRequest:
                (controller, request) =>
                    _webViewPermissions.handlePermissionRequest(request),
            onGeolocationPermissionsShowPrompt:
                (controller, origin) => _webViewPermissions
                    .handleGeolocationPermissionsShowPrompt(origin),
            onLoadStart: (controller, url) {
              _lastLoadedUrl = url?.toString() ?? '';
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _loadProgress = 0;
                  _webViewError = null;
                });
              }
            },
            onLoadStop: (controller, url) async {
              _lastLoadedUrl = url?.toString() ?? _lastLoadedUrl;
              if (mounted) setState(() => _isLoading = false);
              try {
                await _ensureLoginHint();
                if (_credentialNoticeAcknowledged) {
                  _registerLoginCaptureHandler(controller);
                }
                await _installLoginCapture(_lastLoadedUrl);
              } catch (error) {
                AppLogger.warn('登录页面准备失败 (${error.runtimeType})');
                if (mounted) _showLoginPageRetry();
              }
              _scheduleAutoConfirm(url?.toString() ?? '');
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() => _loadProgress = progress.clamp(0, 100) / 100);
            },
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame != true) return;
              _showWebViewError(error);
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              final statusCode = errorResponse.statusCode;
              if (request.isForMainFrame != true ||
                  statusCode == null ||
                  statusCode < 400) {
                return;
              }
              _showWebViewError(errorResponse);
            },
          )
        else
          const SizedBox.expand(),
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // A stalled load must not keep scheduling indeterminate frames
            // over an otherwise static authentication page.
            child: LinearProgressIndicator(value: _loadProgress),
          ),
        if (_webViewError case final error?)
          Positioned.fill(
            child: WebViewErrorView(
              message: error,
              onRetry: () => unawaited(_retryInitialPage()),
            ),
          ),
        if (_isConfirmingLogin) _buildCredentialExchangeOverlay(theme),
      ],
    );
  }

  Widget _buildCredentialExchangeOverlay(ThemeData theme) {
    final colors = theme.colorScheme;

    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Semantics(
                  liveRegion: true,
                  label: '正在完成登录',
                  child: Material(
                    color: colors.surface,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '正在完成登录',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '请稍候…',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
