import '../widgets/adaptive_confirmation_dialog.dart';
import '../services/time_reminder_service.dart';
import '../services/course_live_activity_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_remote_services_service.dart';
import '../services/logging/logger.dart';
import '../services/privacy_agreement_service.dart';
import '../capabilities/academic_schedule/recent_schedule_repository.dart';
import '../capabilities/desktop_widgets/desktop_widget_bridge.dart';
import '../services/usage_analytics_service.dart';
import 'privacy_policy_page.dart';

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
    } catch (error, diagnosticStack) {
      AppLogger.error(
        error,
        stackTrace: diagnosticStack,
        context: '应用远程服务设置读取失败 (${error.runtimeType})',
      );
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
    } catch (error, diagnosticStack) {
      AppLogger.error(
        error,
        stackTrace: diagnosticStack,
        context: '应用远程服务设置保存失败 (${error.runtimeType})',
      );
      try {
        _remoteServicesEnabled = await AppRemoteServicesService.isEnabled();
      } catch (diagnosticError, diagnosticStack) {
        AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
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
    return await showAdaptiveConfirmationDialog(
          context,
          title: '撤回用户协议同意？',
          message: '撤回后应用会退出，下次打开时需要重新确认。',
          confirmLabel: '撤回并退出',
          destructive: true,
        ) ??
        false;
  }

  Future<void> _withdrawAgreement() async {
    if (_withdrawing || !await _confirmWithdrawal()) return;
    setState(() => _withdrawing = true);
    try {
      try {
        await AppRemoteServicesService.setEnabled(false);
      } catch (error, diagnosticStack) {
        AppLogger.error(
          error,
          stackTrace: diagnosticStack,
          context: '应用远程服务关闭失败 (${error.runtimeType})',
        );
      }
      try {
        await UsageAnalyticsService.disableAndClear();
      } catch (error, diagnosticStack) {
        AppLogger.error(
          error,
          stackTrace: diagnosticStack,
          context: '匿名统计队列清理失败 (${error.runtimeType})',
        );
      }
      for (final clear in <Future<void> Function()>[
        PrivacyAgreementService.clear,
        RecentScheduleRepository.instance.clear,
        DesktopWidgetSyncService.clearSchedule,
        TimeReminderService.clearAll,
        CourseLiveActivityService.clearAll,
      ]) {
        try {
          await clear();
        } catch (error, diagnosticStack) {
          AppLogger.error(
            error,
            stackTrace: diagnosticStack,
            context: 'Privacy cleanup failed (${error.runtimeType})',
          );
        }
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
      appBar: AppBar(title: const Text('用户协议')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('app-remote-services-switch'),
            title: const Text('在线功能'),
            subtitle: const Text('关闭后公告、反馈、匿名统计与检查更新不可用；必要的协议获取和安全策略同步仍可联网'),
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
