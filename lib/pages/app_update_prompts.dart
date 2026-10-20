import 'package:flutter/material.dart';

import '../services/updates/app_update_service.dart';
import 'fenfa_dialogs.dart' show presentFenfaUpdateDialog;

bool _forcingUpdate = false;

/// Ordinary updates are shared state, not a startup modal. Only mandatory
/// releases retain the existing non-dismissible system-upgrade prompt.
Future<void> presentAppUpdateCheck(
  BuildContext context, {
  AppUpdateService? service,
  bool manual = false,
}) async {
  final updates = service ?? AppUpdateService.shared;
  await updates.refresh(force: manual);
  if (!context.mounted) return;
  final offer = updates.offer;
  if (offer != null && offer.force) {
    if (_forcingUpdate) return;
    _forcingUpdate = true;
    try {
      await presentFenfaUpdateDialog(
        context,
        release: offer.dialogRelease,
        force: true,
        onUpdate:
            (_, progress) =>
                updates.download(preferDelta: true, onProgress: progress),
      );
    } finally {
      _forcingUpdate = false;
    }
  } else if (manual) {
    final message = switch (updates.state) {
      UpdateCheckState.available => '新版本已显示在“我的”页面，可选择下载更新',
      UpdateCheckState.current => '当前已是最新版本',
      UpdateCheckState.disabled => '应用更新暂不可用，请检查远程服务设置',
      _ => '检查更新失败，请稍后重试',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
