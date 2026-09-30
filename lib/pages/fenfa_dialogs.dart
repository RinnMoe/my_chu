import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/in_app_download/in_app_download.dart';
import '../services/app_remote_services_service.dart';
import '../services/fenfa/fenfa_models.dart';
import '../services/fenfa/fenfa_service.dart';

/// 更新弹窗用户选择。
enum FenfaUpdateChoice { updateNow, later }

typedef FenfaUpdateAction =
    Future<bool> Function(
      FenfaRelease release,
      ValueChanged<InAppDownloadProgress> onProgress,
    );

/// 展示更新弹窗。
///
/// [force] 为 true 时不可关闭（barrierDismissible=false + PopScope 禁返回），
/// 只允许「立即更新」；打开下载后弹窗保持，阻止继续使用旧版本。
/// 普通更新返回用户选择；强制更新模式下弹窗持续存在，不返回。
Future<FenfaUpdateChoice?> presentFenfaUpdateDialog(
  BuildContext context, {
  required FenfaRelease release,
  required bool force,
  required FenfaUpdateAction onUpdate,
}) {
  final dialog = FenfaUpdateDialog(
    release: release,
    force: force,
    onUpdate: onUpdate,
  );

  return showDialog<FenfaUpdateChoice>(
    context: context,
    barrierDismissible: !force,
    builder: (_) => dialog,
  );
}

/// 更新弹窗内容。
class FenfaUpdateDialog extends StatefulWidget {
  final FenfaRelease release;
  final bool force;
  final FenfaUpdateAction onUpdate;

  const FenfaUpdateDialog({
    super.key,
    required this.release,
    required this.force,
    required this.onUpdate,
  });

  @override
  State<FenfaUpdateDialog> createState() => _FenfaUpdateDialogState();
}

class _FenfaUpdateDialogState extends State<FenfaUpdateDialog> {
  bool _running = false;
  InAppDownloadProgress? _progress;

  Future<void> _handleUpdate() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = null;
    });
    try {
      final ok = await widget.onUpdate(widget.release, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      if (ok) {
        if (!widget.force) {
          Navigator.of(context).pop(FenfaUpdateChoice.updateNow);
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

  String _progressText() {
    final progress = _progress;
    if (progress == null) return '正在准备下载…';
    final fraction = progress.fraction;
    if (fraction != null && fraction >= 1) {
      return '下载完成，正在唤起系统安装程序…';
    }
    if (fraction != null) {
      return '正在下载安装包 ${(fraction * 100).floor()}%';
    }
    return '已下载 ${_formatBytes(progress.receivedBytes)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: !widget.force,
      child: AlertDialog(
        title: Text(widget.force ? '发现新版本（强制更新）' : '发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v${widget.release.version}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.release.changelog.isNotEmpty)
                Text(
                  widget.release.changelog,
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
                '安装包将在应用内下载，完成后由系统安装程序确认安装。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (widget.force) ...[
                const SizedBox(height: 12),
                Text(
                  '本次为强制更新，请立即完成升级。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.error,
                  ),
                ),
              ],
              if (_running) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress?.fraction),
                const SizedBox(height: 8),
                Text(_progressText(), style: theme.textTheme.bodySmall),
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
                      : () =>
                          Navigator.of(context).pop(FenfaUpdateChoice.later),
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

/// 启动检查是否已在本进程执行（每次进入主界面只自动检查一次）。
bool _startupCheckRan = false;

@visibleForTesting
void resetFenfaStartupCheckForTest() {
  _startupCheckRan = false;
}

/// 进入主界面后的异步启动更新检查；公告由首页 Focus 加载。
///
/// 所有失败均静默降级，不影响 App 正常启动；未登录时不会调用本方法。
Future<void> presentFenfaStartupCheck(
  BuildContext context, {
  FenfaService? service,
}) async {
  if (_startupCheckRan) return;
  _startupCheckRan = true;
  final fenfa = service ?? FenfaService.shared;

  final result = await fenfa.checkForUpdate(manual: false);
  if (!context.mounted) return;

  switch (result.outcome) {
    case FenfaCheckOutcome.forceUpdate:
      await presentFenfaUpdateDialog(
        context,
        release: result.release!,
        force: true,
        onUpdate:
            (release, onProgress) =>
                fenfa.downloadAndInstall(release, onProgress: onProgress),
      );
      return;
    case FenfaCheckOutcome.normalUpdate:
      final choice = await presentFenfaUpdateDialog(
        context,
        release: result.release!,
        force: false,
        onUpdate:
            (release, onProgress) =>
                fenfa.downloadAndInstall(release, onProgress: onProgress),
      );
      if (choice == FenfaUpdateChoice.later) {
        await fenfa.rememberLater(result.release!.build);
      }
      return;
    case FenfaCheckOutcome.none:
    case FenfaCheckOutcome.unavailable:
      return;
    case FenfaCheckOutcome.disabled:
      return;
  }
}

/// 手动检查更新（关于页“版本号”）：绕过“稍后”抑制，只处理更新。
Future<void> presentFenfaManualCheck(
  BuildContext context, {
  FenfaService? service,
}) async {
  final fenfa = service ?? FenfaService.shared;
  final result = await fenfa.checkForUpdate(manual: true);
  if (!context.mounted) return;

  switch (result.outcome) {
    case FenfaCheckOutcome.forceUpdate:
      await presentFenfaUpdateDialog(
        context,
        release: result.release!,
        force: true,
        onUpdate:
            (release, onProgress) =>
                fenfa.downloadAndInstall(release, onProgress: onProgress),
      );
      break;
    case FenfaCheckOutcome.normalUpdate:
      final choice = await presentFenfaUpdateDialog(
        context,
        release: result.release!,
        force: false,
        onUpdate:
            (release, onProgress) =>
                fenfa.downloadAndInstall(release, onProgress: onProgress),
      );
      if (choice == FenfaUpdateChoice.later) {
        await fenfa.rememberLater(result.release!.build);
      }
      break;
    case FenfaCheckOutcome.none:
      _showSnack(context, '当前已是最新版本');
      break;
    case FenfaCheckOutcome.unavailable:
      _showSnack(context, '检查更新失败，请稍后重试');
      break;
    case FenfaCheckOutcome.disabled:
      showAppRemoteServicesDisabledMessage(context);
      break;
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
