import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../capabilities/network_self_service_auth_capability.dart';
import '../../services/network_self_service_auth_service.dart';
import '../../services/logger_service.dart';
import '../../services/user_error_message.dart';
import '../../services/service_endpoints.dart';
import 'network_self_service_dashboard.dart';
import 'network_self_service_models.dart';
import 'network_self_service_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class NetworkSelfServicePage extends StatefulWidget {
  final NetworkSelfServiceService? service;

  const NetworkSelfServicePage({super.key, this.service});

  @override
  State<NetworkSelfServicePage> createState() => _NetworkSelfServicePageState();
}

class _LoadingCard extends StatelessWidget {
  final double height;

  const _LoadingCard({required this.height});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FractionallySizedBox(
              widthFactor: .42,
              child: Container(height: 16, color: color),
            ),
            const SizedBox(height: 14),
            Container(height: height - 46, color: color),
          ],
        ),
      ),
    );
  }
}

class _NetworkSelfServicePageState extends State<NetworkSelfServicePage> {
  late final NetworkSelfServiceService _service;
  NetworkSelfServiceOverview? _overview;
  NetworkSelfServiceAuthState? _authState;
  String? _error;
  bool _loading = true;
  bool _requestActive = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NetworkSelfServiceService();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_requestActive) return;
    _requestActive = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var authenticated = await _ensureAuthentication();
      if (!authenticated || !mounted) return;
      try {
        final overview = await _service.loadOverview();
        if (!mounted) return;
        setState(() {
          _overview = overview;
          _authState = const NetworkSelfServiceAuthState(
            NetworkSelfServiceAuthStatus.ready,
          );
          _error = null;
        });
      } on NetworkSelfServiceAuthenticationRequiredException {
        authenticated = await _ensureAuthentication();
        if (!authenticated || !mounted) return;
        final overview = await _service.loadOverview();
        if (!mounted) return;
        setState(() {
          _overview = overview;
          _error = null;
        });
      }
    } on NetworkSelfServiceParseException catch (error) {
      if (mounted) {
        logUserFacingError(
          UserErrorContext.network,
          error,
          operationId: UserOperationId.networkSelfService,
        );
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) {
        logUserFacingError(
          UserErrorContext.network,
          error,
          operationId: UserOperationId.networkSelfService,
        );
        setState(() => _error = '网络自服暂时无法加载，请稍后重试。');
      }
    } finally {
      _requestActive = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ensureAuthentication() async {
    var state = await NetworkSelfServiceAuthCapability.prepare();
    while (mounted) {
      if (state.isReady) {
        if (mounted) setState(() => _authState = state);
        return true;
      }
      setState(() => _authState = state);
      switch (state.status) {
        case NetworkSelfServiceAuthStatus.captchaInputRequired:
          final challengeId = state.challengeId;
          final bytes = state.captchaBytes;
          if (challengeId == null || bytes == null) return false;
          final code = await _showCaptchaDialog(state);
          if (code == null) return false;
          state = await NetworkSelfServiceAuthCapability.submitCaptcha(
            challengeId,
            code,
          );
        case NetworkSelfServiceAuthStatus.smsInputRequired:
          final challengeId = state.challengeId;
          if (challengeId == null) return false;
          final code = await _showSmsDialog(state);
          if (code == null) return false;
          state = await NetworkSelfServiceAuthCapability.submitSms(
            challengeId,
            code,
          );
        case NetworkSelfServiceAuthStatus.missingCredential:
        case NetworkSelfServiceAuthStatus.invalidCredential:
        case NetworkSelfServiceAuthStatus.networkError:
        case NetworkSelfServiceAuthStatus.coolingDown:
          return false;
        case NetworkSelfServiceAuthStatus.ready:
          return true;
      }
    }
    return false;
  }

  Future<String?> _showCaptchaDialog(NetworkSelfServiceAuthState state) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => _NetworkSelfServiceCaptchaDialog(
            state: state,
            onRefresh: NetworkSelfServiceAuthCapability.refreshCaptcha,
          ),
    );
  }

  Future<String?> _showSmsDialog(NetworkSelfServiceAuthState state) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NetworkSelfServiceSmsDialog(state: state),
    );
  }

  Future<void> _openWebHome() async {
    if (!await _ensureAuthentication() || !mounted) return;
    final url =
        Uri.parse(
          CampusServiceEndpoints.networkSelfServiceBase,
        ).resolve('/home').toString();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => AuthenticatedWebViewCapability.pageForService(
              title: '网络自服',
              url: url,
              serviceId: CampusServices.networkSelfService,
              showBottomBar: true,
            ),
      ),
    );
  }

  String? _overviewError(NetworkSelfServiceAuthState? authState) {
    final error = _error;
    if (error != null) return error;
    if (authState == null ||
        authState.status == NetworkSelfServiceAuthStatus.ready) {
      return null;
    }
    return authState.message ?? '网络自服登录状态已失效，请重试。';
  }

  @override
  Widget build(BuildContext context) {
    final authState = _authState;
    final overview = _overview;
    final overviewError = _overviewError(authState);
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('网络自服'),
          actions: [
            IconButton(
              tooltip: '打开网页版',
              onPressed: _loading ? null : _openWebHome,
              icon: const Icon(Icons.open_in_browser_outlined),
            ),
          ],
        ),
      ),
      body:
          overview == null
              ? AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child:
                    _loading
                        ? _buildLoadingState(context)
                        : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: [
                            if (_error == null &&
                                authState?.status ==
                                    NetworkSelfServiceAuthStatus
                                        .missingCredential)
                              _buildMissingCredential(context),
                            if (_error == null &&
                                authState != null &&
                                authState.status !=
                                    NetworkSelfServiceAuthStatus.ready &&
                                authState.status !=
                                    NetworkSelfServiceAuthStatus
                                        .missingCredential)
                              _buildAuthError(context, authState),
                            if (_error != null) _buildError(context, _error!),
                          ],
                        ),
              )
              : NetworkSelfServiceDashboard(
                overview: overview,
                overviewLoading: _loading,
                overviewError: overviewError,
                onRefreshOverview: _load,
              ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return ListView(
      key: const ValueKey('network-self-service-loading'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('套餐信息', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const _LoadingCard(height: 126),
        const SizedBox(height: 18),
        Text('在线设备', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const _LoadingCard(height: 88),
      ],
    );
  }

  Widget _buildMissingCredential(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline),
          const SizedBox(height: 12),
          Text('需要重新登录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '网络自服使用与统一身份相同的账号密码。请退出 MyCHU 后重新登录；登录成功后，账号凭据会自动安全保存在设备上。',
          ),
        ],
      ),
    ),
  );

  Widget _buildAuthError(
    BuildContext context,
    NetworkSelfServiceAuthState state,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined),
          const SizedBox(height: 12),
          Text(
            state.message ?? '网络自服登录暂时失败。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    ),
  );

  Widget _buildError(BuildContext context, String error) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(height: 12),
          Text(error),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class _NetworkSelfServiceCaptchaDialog extends StatefulWidget {
  final NetworkSelfServiceAuthState state;
  final Future<NetworkSelfServiceAuthState> Function(String challengeId)
  onRefresh;

  const _NetworkSelfServiceCaptchaDialog({
    required this.state,
    required this.onRefresh,
  });

  @override
  State<_NetworkSelfServiceCaptchaDialog> createState() =>
      _NetworkSelfServiceCaptchaDialogState();
}

class _NetworkSelfServiceCaptchaDialogState
    extends State<_NetworkSelfServiceCaptchaDialog> {
  late final TextEditingController _controller;
  late NetworkSelfServiceAuthState _current;
  var _refreshing = false;
  var _closed = false;
  var _refreshRequest = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _current = widget.state;
  }

  @override
  void dispose() {
    _closed = true;
    _refreshRequest++;
    _controller.dispose();
    super.dispose();
  }

  void _close([String? code]) {
    if (_closed || !mounted) return;
    _closed = true;
    _refreshRequest++;
    Navigator.of(context).pop(code);
  }

  Future<void> _refresh() async {
    if (_closed || !mounted || _refreshing) return;
    final challengeId = _current.challengeId;
    if (challengeId == null) return;
    final request = ++_refreshRequest;
    setState(() => _refreshing = true);
    try {
      final refreshed = await widget.onRefresh(challengeId);
      if (!mounted || _closed || request != _refreshRequest) return;
      setState(() {
        _current = refreshed;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted || _closed || request != _refreshRequest) return;
      setState(() => _refreshing = false);
    }
  }

  void _submit() {
    final code = _controller.text.trim();
    if (RegExp(r'^\d{4}$').hasMatch(code)) _close(code);
  }

  @override
  Widget build(BuildContext context) {
    final captchaBytes = _current.captchaBytes;
    return AlertDialog(
      title: const Text('输入图形验证码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (captchaBytes != null)
            InkWell(
              onTap: _refreshing ? null : _refresh,
              child: Image.memory(
                captchaBytes,
                height: 54,
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _current.message ?? '验证码已自动识别失败，请输入图片中的四位数字。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '验证码',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text('取消')),
        TextButton(
          onPressed: _refreshing ? null : _refresh,
          child: const Text('换一张'),
        ),
        FilledButton(onPressed: _submit, child: const Text('继续')),
      ],
    );
  }
}

class _NetworkSelfServiceSmsDialog extends StatefulWidget {
  final NetworkSelfServiceAuthState state;

  const _NetworkSelfServiceSmsDialog({required this.state});

  @override
  State<_NetworkSelfServiceSmsDialog> createState() =>
      _NetworkSelfServiceSmsDialogState();
}

class _NetworkSelfServiceSmsDialogState
    extends State<_NetworkSelfServiceSmsDialog> {
  late final TextEditingController _controller;
  var _closed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _closed = true;
    _controller.dispose();
    super.dispose();
  }

  void _close([String? code]) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(code);
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isNotEmpty) _close(code);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('输入短信验证码'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: '短信验证码',
        helperText: widget.state.message,
      ),
    ),
    actions: [
      TextButton(onPressed: () => _close(), child: const Text('取消')),
      FilledButton(onPressed: _submit, child: const Text('继续')),
    ],
  );
}
