import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/accounts/account_provider.dart';
import '../capabilities/accounts/account_registry.dart';
import '../services/logging/logger.dart';
import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_settings.dart';

/// Unified management page for host and built-in feature account providers.
class AccountManagementPage extends StatelessWidget {
  const AccountManagementPage({super.key, this.providers});

  final List<AccountProvider>? providers;

  @override
  Widget build(BuildContext context) {
    final items = providers ?? AccountRegistry.providers;
    return Scaffold(
      appBar: AppBar(title: const Text('账号管理')),
      body:
          items.isEmpty
              ? const AdaptiveStatusState(
                icon: Icons.manage_accounts_outlined,
                message: '暂无可管理账号',
              )
              : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  AdaptiveSettingsSection(
                    children: [
                      for (final provider in items)
                        _AccountProviderRow(
                          key: ValueKey<String>(provider.id),
                          provider: provider,
                        ),
                    ],
                  ),
                ],
              ),
    );
  }
}

class _AccountProviderRow extends StatefulWidget {
  const _AccountProviderRow({super.key, required this.provider});

  final AccountProvider provider;

  @override
  State<_AccountProviderRow> createState() => _AccountProviderRowState();
}

class _AccountProviderRowState extends State<_AccountProviderRow> {
  AccountSummary? _summary;
  bool _readFailed = false;
  bool _busy = false;
  bool _logoutDialogOpen = false;
  int _readVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.provider.changes.addListener(_onProviderChanged);
    unawaited(_read());
    unawaited(_restore());
  }

  @override
  void didUpdateWidget(covariant _AccountProviderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider)) {
      oldWidget.provider.changes.removeListener(_onProviderChanged);
      widget.provider.changes.addListener(_onProviderChanged);
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    widget.provider.changes.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) unawaited(_read());
  }

  Future<void> _restore() async {
    try {
      await widget.provider.restore();
    } catch (error, stackTrace) {
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: '账号状态刷新失败 (${widget.provider.id})',
      );
    } finally {
      if (mounted) await _read();
    }
  }

  Future<void> _read() async {
    final version = ++_readVersion;
    try {
      final summary = await widget.provider.read();
      if (!mounted || version != _readVersion) return;
      setState(() {
        _summary = summary;
        _readFailed = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: '读取账号状态失败 (${widget.provider.id})',
      );
      if (!mounted || version != _readVersion) return;
      setState(() => _readFailed = true);
    }
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.provider.open(context);
    } catch (error, stackTrace) {
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: '打开账号页面失败 (${widget.provider.id})',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _read();
      }
    }
  }

  Future<void> _confirmLogout() async {
    if (_busy || _logoutDialogOpen) return;
    _logoutDialogOpen = true;
    final bool? confirmed;
    try {
      confirmed = await showAdaptiveConfirmationDialog(
        context,
        title: '退出${widget.provider.name}',
        message: widget.provider.logoutMessage,
        confirmLabel: '退出登录',
        destructive: true,
        barrierDismissible: false,
      );
    } finally {
      _logoutDialogOpen = false;
    }
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.provider.logout();
    } catch (error, stackTrace) {
      AppLogger.error(
        error,
        stackTrace: stackTrace,
        context: '退出账号失败 (${widget.provider.id})',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('退出登录失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _read();
      }
    }
  }

  String? _subtitleText() {
    if (_readFailed) return '不可用';
    final summary = _summary;
    if (summary == null) return null;
    final name = summary.displayName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return switch (summary.status) {
      AccountStatus.signedOut => '未登录',
      AccountStatus.available => hasName ? name : '已登录',
      AccountStatus.unavailable => hasName ? '$name · 不可用' : '不可用',
    };
  }

  Widget? _buildTrailing(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_summary?.hasIdentity == true) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _confirmLogout,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('退出登录'),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsRow(
      icon: widget.provider.icon,
      title: widget.provider.name,
      subtitle: _subtitleText(),
      trailing: _buildTrailing(context),
      onTap: _busy ? null : _open,
    );
  }
}
