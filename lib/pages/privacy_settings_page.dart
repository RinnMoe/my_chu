import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_remote_services_service.dart';
import '../services/logger_service.dart';
import '../services/privacy_agreement_service.dart';
import '../services/usage_analytics_service.dart';
import 'privacy_policy_page.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key, this.onExit});

  final Future<void> Function()? onExit;

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool? _remoteServicesEnabled;
  bool _loading = true;
  bool _saving = false;
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRemoteServicesPreference());
  }

  Future<void> _loadRemoteServicesPreference() async {
    try {
      final enabled = await AppRemoteServicesService.isEnabled();
      if (!mounted) return;
      setState(() {
        _remoteServicesEnabled = enabled;
        _loading = false;
      });
    } catch (error) {
      AppLogger.warn('应用远程服务设置读取失败 (${error.runtimeType})');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setRemoteServicesEnabled(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _remoteServicesEnabled = enabled;
    });
    try {
      await AppRemoteServicesService.setEnabled(enabled);
      if (enabled) {
        await UsageAnalyticsService.initializeIfEnabled();
      } else {
        await UsageAnalyticsService.disableAndClear();
      }
    } catch (error) {
      AppLogger.warn('应用远程服务设置保存失败 (${error.runtimeType})');
      try {
        _remoteServicesEnabled = await AppRemoteServicesService.isEnabled();
      } catch (_) {
        _remoteServicesEnabled = null;
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('无法保存设置，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pushPage(Widget page) {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(builder: (_) => page);
    unawaited(navigator.push<void>(route));
  }

  Future<bool> _confirmWithdrawal() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('撤回用户协议同意？'),
                content: const Text('撤回后应用会退出，下次打开时需要重新确认。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('撤回并退出'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _withdrawAgreement() async {
    if (_withdrawing || !await _confirmWithdrawal()) return;
    setState(() => _withdrawing = true);
    try {
      try {
        await AppRemoteServicesService.setEnabled(false);
      } catch (error) {
        AppLogger.warn('应用远程服务关闭失败 (${error.runtimeType})');
      }
      try {
        await UsageAnalyticsService.disableAndClear();
      } catch (error) {
        AppLogger.warn('匿名统计队列清理失败 (${error.runtimeType})');
      }
      try {
        await PrivacyAgreementService.clear();
      } catch (error) {
        AppLogger.warn('用户协议状态清理失败 (${error.runtimeType})');
      }
    } finally {
      final exit = widget.onExit;
      if (exit == null) {
        await SystemNavigator.pop();
      } else {
        await exit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _remoteServicesEnabled ?? true;
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('用户协议与服务端设置')),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text('服务端功能设置', style: theme.textTheme.titleSmall),
          ),
          SwitchListTile(
            key: const ValueKey('app-remote-services-switch'),
            title: const Text('服务端功能'),
            subtitle: const Text('关闭后匿名统计、更新检测等依赖服务端的功能不可用'),
            value: enabled,
            onChanged:
                _loading || _saving || _remoteServicesEnabled == null
                    ? null
                    : _setRemoteServicesEnabled,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
            child: Text('相关信息', style: theme.textTheme.titleSmall),
          ),
          ListTile(
            title: const Text('用户协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pushPage(const PrivacyPolicyPage()),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _withdrawing ? null : _withdrawAgreement,
              child: const Text('撤回用户协议同意'),
            ),
          ),
        ],
      ),
    );
  }
}
