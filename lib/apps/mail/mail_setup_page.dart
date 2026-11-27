import 'package:flutter/material.dart';

import '../../services/mail/mail_config.dart';
import '../../services/mail/mail_error.dart';
import '../../services/mail/mail_session.dart';
import '../../services/reliability_event.dart';
import '../../services/user_error_message.dart';

class MailSetupPage extends StatelessWidget {
  final MailAccountConfig? initialConfig;
  final MailSession? session;

  const MailSetupPage({super.key, this.initialConfig, this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(initialConfig == null ? '连接校园邮箱' : '修改账号')),
      body: MailSetupView(
        initialConfig: initialConfig,
        allowCancel: true,
        session: session,
        onSaved: () => Navigator.of(context).pop(true),
      ),
    );
  }
}

class MailSetupView extends StatefulWidget {
  final MailAccountConfig? initialConfig;
  final bool allowCancel;
  final VoidCallback? onSaved;
  final MailSession? session;

  const MailSetupView({
    super.key,
    this.initialConfig,
    this.allowCancel = false,
    this.onSaved,
    this.session,
  });

  @override
  State<MailSetupView> createState() => _MailSetupViewState();
}

class _MailSetupViewState extends State<MailSetupView> {
  late final MailSession _session = widget.session ?? MailSession.instance;
  late final TextEditingController _emailController;
  late final TextEditingController _secretController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _smtpHostController;
  late final TextEditingController _smtpPortController;

  late MailSecurity _security;
  late MailSecurity _smtpSecurity;
  late bool _smtpHostAuto;
  bool _syncingSmtpHost = false;
  bool _advanced = false;
  bool _obscureSecret = true;
  bool _busy = false;
  bool _canKeepSecret = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    final imapHost = config?.imapHost ?? MailAccountConfig.defaultImapHost;
    _emailController = TextEditingController(
      text: MailAccountConfig.prefixOf(config?.email),
    );
    _secretController = TextEditingController();
    _hostController = TextEditingController(text: imapHost);
    _portController = TextEditingController(
      text: (config?.imapPort ?? MailAccountConfig.defaultImapPort).toString(),
    );
    _smtpHostController = TextEditingController(
      text: config?.smtpHost ?? MailAccountConfig.deriveSmtpHost(imapHost),
    );
    _smtpPortController = TextEditingController(
      text: (config?.smtpPort ?? MailAccountConfig.defaultSmtpPort).toString(),
    );
    _security = config?.imapSecurity ?? MailSecurity.ssl;
    _smtpSecurity = config?.smtpSecurity ?? MailSecurity.ssl;
    _smtpHostAuto =
        config == null ||
        config.smtpHost == MailAccountConfig.deriveSmtpHost(config.imapHost);
    _canKeepSecret = _matchesInitialEmail;
    _emailController.addListener(_syncSecretHint);
    _hostController.addListener(_syncSmtpHostFromImap);
    _smtpHostController.addListener(_markSmtpHostManual);
  }

  @override
  void dispose() {
    _emailController.removeListener(_syncSecretHint);
    _hostController.removeListener(_syncSmtpHostFromImap);
    _smtpHostController.removeListener(_markSmtpHostManual);
    _emailController.dispose();
    _secretController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    super.dispose();
  }

  String get _prefix => MailAccountConfig.prefixOf(_emailController.text);

  String get _normalizedEmail =>
      MailAccountConfig.emailFromPrefix(_emailController.text);

  bool get _matchesInitialEmail =>
      widget.initialConfig?.email == _normalizedEmail;

  /// 只有邮箱未变时才允许留空密码，提示随输入即时出现或消失。
  void _syncSecretHint() {
    final canKeep = _matchesInitialEmail;
    if (canKeep == _canKeepSecret) return;
    setState(() => _canKeepSecret = canKeep);
  }

  /// 未手动改过发件主机时，跟随收件主机按命名规则推导。
  void _syncSmtpHostFromImap() {
    if (!_smtpHostAuto || _syncingSmtpHost) return;
    final derived = MailAccountConfig.deriveSmtpHost(_hostController.text);
    if (_smtpHostController.text == derived) return;
    _syncingSmtpHost = true;
    _smtpHostController.text = derived;
    _syncingSmtpHost = false;
  }

  void _markSmtpHostManual() {
    if (_syncingSmtpHost) return;
    _smtpHostAuto = false;
  }

  MailAccountConfig get _config => MailAccountConfig(
    email: _normalizedEmail,
    imapHost: _hostController.text.trim(),
    imapPort: int.tryParse(_portController.text.trim()) ?? 0,
    imapSecurity: _security,
    smtpHost: _smtpHostController.text.trim(),
    smtpPort: int.tryParse(_smtpPortController.text.trim()) ?? 0,
    smtpSecurity: _smtpSecurity,
  );

  Future<void> _submit() async {
    if (_busy) return;
    if (_prefix.isEmpty) {
      setState(() => _error = '请输入学号');
      return;
    }
    final config = _config;
    final validation = config.validationError;
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    final secret = _secretController.text.trim();
    final canKeepSecret = _canKeepSecret && secret.isEmpty;
    if (!canKeepSecret && secret.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (canKeepSecret) {
        await _session.updateConfig(config);
      } else {
        await _session.configure(config, secret);
      }
      if (!mounted) return;
      widget.onSaved?.call();
    } on MailException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailConnect,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '保存失败，请稍后重试');
      }
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailConnect,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeSecurity(MailSecurity security) {
    final currentPort = int.tryParse(_portController.text.trim());
    final previousDefault = MailAccountConfig.defaultPortFor(_security);
    setState(() {
      _security = security;
      if (currentPort == null || currentPort == previousDefault) {
        _portController.text =
            MailAccountConfig.defaultPortFor(security).toString();
      }
    });
  }

  void _changeSmtpSecurity(MailSecurity security) {
    final currentPort = int.tryParse(_smtpPortController.text.trim());
    final previousDefault = MailAccountConfig.defaultSmtpPortFor(_smtpSecurity);
    setState(() {
      _smtpSecurity = security;
      if (currentPort == null || currentPort == previousDefault) {
        _smtpPortController.text =
            MailAccountConfig.defaultSmtpPortFor(security).toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '学号',
                    prefixIcon: const Icon(Icons.alternate_email),
                    suffixIcon: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: Align(
                        widthFactor: 1,
                        child: Text(
                          '@${MailAccountConfig.chdDomain}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _secretController,
                  obscureText: _obscureSecret,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: _canKeepSecret ? '留空则不修改' : null,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed:
                          () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                      icon: Icon(
                        _obscureSecret
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _advanced = !_advanced),
                    icon: Icon(
                      _advanced ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: const Text('高级设置'),
                  ),
                ),
                if (_advanced) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _hostController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '收件服务器',
                      prefixIcon: Icon(Icons.download_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '收件端口',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<MailSecurity>(
                    segments: const [
                      ButtonSegment(
                        value: MailSecurity.ssl,
                        label: Text('SSL'),
                      ),
                      ButtonSegment(
                        value: MailSecurity.starttls,
                        label: Text('STARTTLS'),
                      ),
                    ],
                    selected: {_security},
                    onSelectionChanged:
                        (selection) => _changeSecurity(selection.first),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _smtpHostController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '发件服务器',
                      prefixIcon: Icon(Icons.upload_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _smtpPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '发件端口',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<MailSecurity>(
                    segments: const [
                      ButtonSegment(
                        value: MailSecurity.ssl,
                        label: Text('SSL'),
                      ),
                      ButtonSegment(
                        value: MailSecurity.starttls,
                        label: Text('STARTTLS'),
                      ),
                    ],
                    selected: {_smtpSecurity},
                    onSelectionChanged:
                        (selection) => _changeSmtpSecurity(selection.first),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 20,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon:
                      _busy
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.check),
                  label: Text(_busy ? '正在连接…' : '连接'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(const SnackBar(content: Text('开发中')));
                  },
                  child: const Text('注册指引'),
                ),
                if (widget.allowCancel) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('取消'),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  '密码与邮件内容只保存在本机。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
