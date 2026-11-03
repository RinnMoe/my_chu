import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/in_app_download/in_app_download.dart';
import '../services/app_remote_services_service.dart';
import 'app_update_progress.dart';

/// 更新弹窗用户选择。
enum AppUpdateChoice { updateNow, later }

typedef AppUpdateAction =
    Future<bool> Function(ValueChanged<InAppDownloadProgress> onProgress);

/// 更新弹窗内容。
///
/// [force] 为 true 时不可关闭（PopScope 禁返回），只允许「立即更新」；打开
/// 下载后弹窗保持，阻止继续使用旧版本。
class AppUpdateDialog extends StatefulWidget {
  final String version;
  final String notes;
  final bool force;
  final AppUpdateAction onUpdate;

  const AppUpdateDialog({
    super.key,
    required this.version,
    required this.notes,
    required this.force,
    required this.onUpdate,
  });

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _running = false;
  InAppDownloadProgress? _progress;

  Future<void> _handleUpdate() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = null;
    });
    try {
      final ok = await widget.onUpdate((progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      if (ok) {
        if (!widget.force) {
          Navigator.of(context).pop(AppUpdateChoice.updateNow);
        }
        // 强制更新：系统安装程序打开后弹窗保持，阻止继续使用旧版本。
        return;
      }
      await _showFailure('无法唤起系统安装程序，请稍后重试');
    } on AppRemoteServicesDisabledException {
      if (!mounted) return;
      await _showFailure(AppRemoteServicesDisabledException.userMessage);
    } catch (_) {
      if (!mounted) return;
      await _showFailure('下载安装包失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
    return Future<void>.value();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: !widget.force,
      child: AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v${widget.version}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.notes.isNotEmpty)
                Text(
                  widget.notes,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  '请更新到最新版本以继续使用。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '下载完成后，请按系统提示完成安装。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (widget.force) ...[
                const SizedBox(height: 12),
                Text(
                  '此版本需要更新后才能继续使用。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.error,
                  ),
                ),
              ],
              if (_running) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress?.fraction),
                const SizedBox(height: 8),
                Text(
                  updateProgressLabel(_progress),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!widget.force)
            TextButton(
              onPressed:
                  _running
                      ? null
                      : () => Navigator.of(context).pop(AppUpdateChoice.later),
              child: const Text('稍后'),
            ),
          FilledButton(
            onPressed: _running ? null : _handleUpdate,
            child: Text(_running ? '下载中' : '立即更新'),
          ),
        ],
      ),
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showAppRemoteServicesDisabledMessage(BuildContext context) {
  _showSnack(context, AppRemoteServicesDisabledException.userMessage);
}
