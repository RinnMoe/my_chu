import 'dart:async';

import 'package:flutter/material.dart';

import '../services/updates/app_update_service.dart';
import '../services/updates/update_offer.dart';
import 'fenfa_dialogs.dart' show FenfaUpdateDialog;

bool _forcingUpdate = false;

/// Ordinary updates are shared state, not a startup modal. Only mandatory
/// releases retain the existing non-dismissible system-upgrade prompt.
Future<void> presentAppUpdateCheck(
  BuildContext context, {
  AppUpdateService? service,
  bool manual = false,
  bool forceRefresh = false,
  Future<void> Function()? onUpdateAvailable,
}) async {
  final updates = service ?? AppUpdateService.shared;
  await updates.refresh(force: manual || forceRefresh);
  if (!context.mounted) return;
  final offer = updates.offer;
  if (offer != null && onUpdateAvailable != null) {
    await onUpdateAvailable();
    if (!context.mounted) return;
  }
  if (offer != null && offer.force) {
    if (_forcingUpdate) return;
    _forcingUpdate = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MandatoryUpdateDialog(updates: updates, offer: offer),
      );
    } finally {
      _forcingUpdate = false;
    }
  } else if (manual && (offer == null || onUpdateAvailable == null)) {
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

/// Observe policy only while the mandatory dialog is on screen.
class _MandatoryUpdateDialog extends StatefulWidget {
  const _MandatoryUpdateDialog({required this.updates, required this.offer});

  final AppUpdateService updates;
  final UpdateOffer offer;

  @override
  State<_MandatoryUpdateDialog> createState() => _MandatoryUpdateDialogState();
}

class _MandatoryUpdateDialogState extends State<_MandatoryUpdateDialog>
    with WidgetsBindingObserver {
  late UpdateOffer _offer;
  bool _wasBackgrounded = false;

  bool get _canDismiss => switch (widget.updates.state) {
    UpdateCheckState.current || UpdateCheckState.disabled => true,
    UpdateCheckState.available => widget.updates.offer?.force == false,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _offer = widget.offer;
    widget.updates.addListener(_onUpdateChanged);
    WidgetsBinding.instance.addObserver(this);
    // The result may have changed between requesting and mounting the dialog.
    _onUpdateChanged();
  }

  void _onUpdateChanged() {
    final offer = widget.updates.offer;
    setState(() {
      if (offer != null && offer.force) _offer = offer;
    });
    if (!_canDismiss) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_canDismiss) return;
      // Remove this dialog specifically, even if another route is above it.
      final route = ModalRoute.of(context)!;
      route.navigator?.removeRoute(route);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      unawaited(widget.updates.refresh(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.updates.removeListener(_onUpdateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FenfaUpdateDialog(
    release: _offer.dialogRelease,
    force: true,
    onUpdate:
        (_, progress) =>
            widget.updates.download(preferDelta: true, onProgress: progress),
  );
}
