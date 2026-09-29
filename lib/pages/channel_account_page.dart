import 'package:flutter/material.dart';

import '../capabilities/channel_account_capability.dart';
import '../capabilities/channel_resources_link_capability.dart';
import '../capabilities/saved_login_credential.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class ChannelAccountPage extends StatefulWidget {
  final ChannelAccountCapability? capability;
  final ChannelResourcesLinkCapability linkCapability;

  const ChannelAccountPage({
    super.key,
    this.capability,
    this.linkCapability = const ChannelResourcesLinkCapability(),
  });

  @override
  State<ChannelAccountPage> createState() => _ChannelAccountPageState();
}

class _ChannelAccountPageState extends State<ChannelAccountPage> {
  late final ChannelAccountCapability _capability;
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _rememberPassword = false;
  bool _loadingRememberedCredential = true;
  bool _busy = false;
  String? _rememberedUsername;
  String? _error;

  @override
  void initState() {
    super.initState();
    _capability = widget.capability ?? ChannelAccountCapability.current;
    _capability.stateListenable.addListener(_handleAccountChanged);
    _restore();
    _loadRememberedCredential();
  }

  @override
  void dispose() {
    _capability.stateListenable.removeListener(_handleAccountChanged);
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _handleAccountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    try {
      await _capability.restore();
    } on Object {
      // The account state contains a user-safe error category for the page.
    }
  }

  Future<void> _loadRememberedCredential() async {
    SavedLoginCredential? credential;
    try {
      credential = await _capability.readRememberedCredential();
    } on Object {
      // A secure-storage read failure must not block a manual login.
    }
    if (!mounted) return;
    setState(() {
      final previousUsername = _rememberedUsername;
      _rememberedUsername = credential?.username;
      _rememberPassword = credential != null;
      _loadingRememberedCredential = false;
      if (credential != null && _username.text.isEmpty) {
        _username.text = credential.username;
        _password.text = credential.password;
      } else if (credential == null && _username.text == previousUsername) {
        _username.clear();
        _password.clear();
      }
    });
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await _capability.login(
        username: _username.text.trim(),
        password: _password.text,
        rememberPassword: _rememberPassword,
      );
      if (!mounted) return;
      if (!state.isAuthenticated) {
        setState(
          () =>
              _error =
                  ChannelAccountException(
                    state.errorType ?? ChannelAccountErrorType.network,
                  ).userMessage,
        );
        return;
      }
      _username.clear();
      _password.clear();
      await _loadRememberedCredential();
    } on ChannelAccountException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = '登录失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgetRememberedPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('删除已保存的密码？'),
            content: const Text('删除后不会影响当前频道账号登录状态。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _capability.clearRememberedCredential();
    if (!mounted) return;
    setState(() {
      _rememberedUsername = null;
      _rememberPassword = false;
      _username.clear();
      _password.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除保存的频道账号密码。')));
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('退出校园频道账号？'),
            content: const Text('这只会退出校园频道账号，不会影响校园统一身份登录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('退出'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _capability.logout();
      await _loadRememberedCredential();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已退出校园频道账号。')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('退出失败，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChannelAccountChangePasswordPage(capability: _capability),
      ),
    );
    if (mounted) await _loadRememberedCredential();
  }

  Future<void> _openRegistrationGuide() async {
    final opened = await widget.linkCapability.open(
      Uri.parse('https://pd.qq.com/s/681lnmczj'),
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 QQ 频道指引。')));
    }
  }

  Widget _loginBody(ChannelAccountState state) {
    final status = state.status;
    final statusMessage = switch (status) {
      ChannelAccountStatus.unavailable =>
        ChannelAccountException(
          state.errorType ?? ChannelAccountErrorType.network,
        ).userMessage,
      _ => null,
    };
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          const Icon(Icons.forum_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            '登录校园频道账号',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '校园频道账号是独立的第三方账号，由校园频道运营。它不是您的校园统一身份或QQ账号。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 20),
            Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          TextFormField(
            controller: _username,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator:
                (value) =>
                    value == null || value.trim().isEmpty ? '请输入用户名。' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _login(),
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.password_outlined),
            ),
            validator:
                (value) =>
                    value == null || value.length < 6 ? '密码至少需要 6 位。' : null,
          ),
          CheckboxListTile(
            value: _rememberPassword,
            onChanged:
                _busy || _loadingRememberedCredential
                    ? null
                    : (value) =>
                        setState(() => _rememberPassword = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('记住密码'),
            subtitle: const Text('账号及密码将以安全方式保存在您的设备上。'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _login,
            child:
                _busy
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('登录'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : _openRegistrationGuide,
            child: const Text('没有账号？查看注册指引'),
          ),
        ],
      ),
    );
  }

  Widget _accountBody(ChannelAccountUser user) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user.nickname),
            subtitle: user.username == null ? null : Text(user.username!),
          ),
        ),
        if (user.isDefaultPassword) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('请尽快修改初始密码'),
              trailing: TextButton(
                onPressed: _busy ? null : _changePassword,
                child: const Text('修改'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_loadingRememberedCredential)
          const ListTile(
            leading: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('正在读取记住密码状态…'),
          )
        else if (_rememberedUsername != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('已记住密码'),
              subtitle: Text('账号：$_rememberedUsername'),
              trailing: TextButton(
                onPressed: _busy ? null : _forgetRememberedPassword,
                child: const Text('删除'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.password_outlined),
          title: const Text('修改密码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _changePassword,
        ),
        ListTile(
          leading: Icon(
            Icons.logout,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '退出登录',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: _busy ? null : _logout,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('频道账号')),
      ),
      body: ValueListenableBuilder<ChannelAccountState>(
        valueListenable: _capability.stateListenable,
        builder: (context, state, _) {
          if (state.status == ChannelAccountStatus.restoring) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.isAuthenticated && state.user != null) {
            return _accountBody(state.user!);
          }
          return _loginBody(state);
        },
      ),
    );
  }
}

class ChannelAccountChangePasswordPage extends StatefulWidget {
  final ChannelAccountCapability capability;

  const ChannelAccountChangePasswordPage({super.key, required this.capability});

  @override
  State<ChannelAccountChangePasswordPage> createState() =>
      _ChannelAccountChangePasswordPageState();
}

class _ChannelAccountChangePasswordPageState
    extends State<ChannelAccountChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _newUsername = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _oldPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _newUsername.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.capability.changePassword(
        oldPassword: _oldPassword.text,
        newPassword: _newPassword.text,
        newUsername: _newUsername.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已修改，请使用新密码重新登录。')));
        Navigator.pop(context);
      }
    } on ChannelAccountException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = '密码修改失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('修改频道账号密码')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _oldPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: '旧密码（初始密码可留空）'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
              validator:
                  (value) =>
                      value == null || value.length < 6 ? '密码至少需要 6 位。' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
              validator:
                  (value) => value != _newPassword.text ? '两次输入的密码不一致。' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newUsername,
              decoration: const InputDecoration(labelText: '新用户名（可选）'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child:
                  _busy
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('保存并重新登录'),
            ),
          ],
        ),
      ),
    );
  }
}
