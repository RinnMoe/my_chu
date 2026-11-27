import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/mail/mail_cache.dart';
import '../../services/mail/mail_preferences.dart';
import '../../services/mail/mail_session.dart';
import '../../widgets/adaptive_confirmation_dialog.dart';
import '../../widgets/adaptive_settings.dart';
import 'mail_account.dart';
import 'mail_setup_page.dart';

class MailSettingsPage extends StatefulWidget {
  final MailSession? session;

  const MailSettingsPage({super.key, this.session});

  @override
  State<MailSettingsPage> createState() => _MailSettingsPageState();
}

class _MailSettingsPageState extends State<MailSettingsPage> {
  late final MailSession _session = widget.session ?? MailSession.instance;
  final MailPreferences _preferences = MailPreferences();

  late MailSessionState _state = _session.state.value;
  bool _showRemoteImages = false;
  MailCacheStats _stats = MailCacheStats.empty;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _session.state.addListener(_onStateChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _session.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() => _state = _session.state.value);
  }

  Future<void> _load() async {
    final showRemoteImages = await _preferences.showRemoteImages();
    final stats = await _session.cacheStats();
    if (!mounted) return;
    setState(() {
      _showRemoteImages = showRemoteImages;
      _stats = stats;
    });
  }

  Future<void> _editAccount() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) =>
                MailSetupPage(initialConfig: _state.config, session: _session),
      ),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _toggleRemoteImages(bool value) async {
    setState(() => _showRemoteImages = value);
    await _preferences.setShowRemoteImages(value);
  }

  Future<void> _clearCache() async {
    setState(() => _busy = true);
    await _session.clearCache();
    final stats = await _session.cacheStats();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _busy = false;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('缓存已清理')));
  }

  Future<void> _signOut() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '退出邮箱',
      message: MailAccountProvider.logoutConfirmationMessage,
      confirmLabel: '退出',
      destructive: true,
      barrierDismissible: false,
    );
    if (confirmed != true) return;
    await _session.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final config = _state.config;
    return Scaffold(
      appBar: AppBar(title: const Text('邮箱设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AdaptiveSettingsSection(
            title: '账号',
            children: [
              AdaptiveSettingsRow(
                icon: Icons.alternate_email,
                title: '邮箱地址',
                trailingValue: config?.email ?? '未设置',
                showChevron: false,
              ),
              AdaptiveSettingsRow(
                icon: Icons.tune,
                title: '修改账号',
                onTap: _editAccount,
              ),
            ],
          ),
          const SizedBox(height: 18),
          AdaptiveSettingsSection(
            title: '阅读',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.image_outlined),
                title: const Text('自动显示图片'),
                subtitle: const Text('对所有邮件生效'),
                value: _showRemoteImages,
                onChanged: _toggleRemoteImages,
              ),
            ],
          ),
          const SizedBox(height: 18),
          AdaptiveSettingsSection(
            title: '存储',
            children: [
              AdaptiveSettingsRow(
                icon: Icons.storage_outlined,
                title: '本地缓存',
                trailingValue:
                    _stats.files == 0
                        ? '0 MB'
                        : '${(_stats.bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                showChevron: false,
              ),
              AdaptiveSettingsRow(
                icon: Icons.cleaning_services_outlined,
                title: '清理缓存',
                onTap: _busy ? null : _clearCache,
              ),
            ],
          ),
          const SizedBox(height: 18),
          AdaptiveSettingsSection(
            children: [
              AdaptiveSettingsRow(
                icon: Icons.logout,
                title: '退出邮箱',
                onTap: _signOut,
                showChevron: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
