import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../capabilities/qr_scanner_capability.dart';
import '../../pages/host_permission_purpose_overlay.dart';
import '../../services/host_permission_service.dart';
import 'smart_socket_protocol.dart';
import 'smart_socket_protocol_service.dart';

import '../../services/logging/logger.dart';

enum _SmartSocketView {
  ready,
  scanning,
  review,
  opening,
  success,
  error,
  unsupported,
}

class SmartSocketYundarenPage extends StatefulWidget {
  final bool? platformSupportedOverride;
  final BleQrInfo? initialQrForTesting;
  final SmartSocketProtocolService? serviceForTesting;
  final QrScannerCapability? scannerForTesting;
  final HostPermissionService? permissionServiceForTesting;

  const SmartSocketYundarenPage({
    super.key,
    this.platformSupportedOverride,
    this.initialQrForTesting,
    this.serviceForTesting,
    this.scannerForTesting,
    this.permissionServiceForTesting,
  });

  @override
  State<SmartSocketYundarenPage> createState() =>
      _SmartSocketYundarenPageState();
}

class _SmartSocketYundarenPageState extends State<SmartSocketYundarenPage>
    with WidgetsBindingObserver {
  late final SmartSocketProtocolService _service;
  late final QrScannerCapability _scanner;
  late final HostPermissionService _permissionService;
  _SmartSocketView _view = _SmartSocketView.ready;
  BleQrInfo? _qr;
  String? _failure;
  String? _failureHint;
  bool _permanentlyDenied = false;
  bool _requestingPermission = false;
  String _openingMessage = '正在准备开启';

  // HarmonyOS entry stays gated until BLE MAC virtualization on OHOS is resolved.
  bool get _platformSupported =>
      widget.platformSupportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.serviceForTesting ?? SmartSocketProtocolService();
    _scanner = widget.scannerForTesting ?? qrScannerCapability;
    _permissionService =
        widget.permissionServiceForTesting ?? hostPermissionService;
    if (!_platformSupported) {
      _view = _SmartSocketView.unsupported;
    } else if (widget.initialQrForTesting case final initialQr?) {
      _qr = initialQr;
      _view = _SmartSocketView.review;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Android pairing dialog can make the app inactive temporarily.
    if ((state == AppLifecycleState.inactive && _qr?.usesBle == true) ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_disconnectForBackground());
    }
  }

  Future<void> _prepareScanner() async {
    if (!mounted || !_platformSupported) return;
    setState(() {
      _view = _SmartSocketView.scanning;
      _failure = null;
      _failureHint = null;
      _permanentlyDenied = false;
    });
    BleQrInfo? qr;
    try {
      qr = await _scanner.scan<BleQrInfo>(
        context,
        QrScanRequest<BleQrInfo>(
          title: '扫描设备码',
          prompt: '对准插座上的二维码',
          decoder: (symbol) {
            try {
              return QrDecodeResult.success(BleQrInfo.parse(symbol.rawValue));
            } catch (diagnosticError, diagnosticStack) {
              AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
              return const QrDecodeResult.failure('不支持的设备');
            }
          },
        ),
      );
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (!mounted) return;
      setState(() {
        _failure = '扫码失败';
        _failureHint = '请重新扫描设备码';
        _view = _SmartSocketView.error;
      });
      return;
    }
    if (!mounted) return;
    if (qr == null) {
      setState(() {
        _failure = null;
        _failureHint = null;
        _view = _SmartSocketView.ready;
      });
      return;
    }
    setState(() {
      _qr = qr;
      _view = _SmartSocketView.review;
    });
  }

  Future<void> _openSocket() async {
    final qr = _qr;
    if (qr == null ||
        _view != _SmartSocketView.review ||
        _requestingPermission) {
      return;
    }
    final requestPermissions =
        qr.usesBle
            ? _permissionService.requestBleCentralPermissions
            : _permissionService.requestClassicBluetoothPermissions;
    _requestingPermission = true;
    final HostPermissionFeatureResult permission;
    try {
      permission = await requestPermissions(
        presentPurpose:
            (purpose) => presentHostPermissionPurpose(
              context,
              HostPermissionPurpose(
                permission: purpose.permission,
                title: '允许启动插座',
                message: '需要蓝牙权限来连接并启动插座。',
              ),
            ),
      );
    } finally {
      _requestingPermission = false;
    }
    if (!mounted) return;
    if (!permission.granted) {
      setState(() {
        _permanentlyDenied = permission.permanentlyDenied;
        _failure = '需要蓝牙权限';
        _failureHint = '请允许蓝牙权限后重试';
        _view = _SmartSocketView.error;
      });
      return;
    }

    setState(() {
      _failure = null;
      _failureHint = null;
      _permanentlyDenied = false;
      _openingMessage = '正在准备蓝牙连接';
      _view = _SmartSocketView.opening;
    });
    try {
      await _service.run(
        qr,
        onUpdate: (phase) {
          if (!mounted) return;
          final message = switch (phase) {
            SmartSocketPhase.scanning => '正在准备蓝牙连接',
            SmartSocketPhase.connecting ||
            SmartSocketPhase.discovering => '正在连接插座',
            SmartSocketPhase.sendingStart => '正在开启插座',
            SmartSocketPhase.running => '开启成功',
            _ => '正在准备开启',
          };
          if (_openingMessage != message) {
            setState(() => _openingMessage = message);
          }
        },
      );
      if (!mounted || !identical(_qr, qr)) return;
      await _service.disconnect();
      if (!mounted || !identical(_qr, qr)) return;
      setState(() {
        _openingMessage = '开启成功';
        _view = _SmartSocketView.success;
      });
    } on SmartSocketFailure catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      if (!mounted || !identical(_qr, qr)) return;
      final failure =
          error.uncertainDeviceState
              ? '插座状态待确认'
              : error.userMessage ?? '开启插座失败';
      setState(() {
        _failure = failure;
        _failureHint = _failureHintFor(error, failure);
        _view = _SmartSocketView.error;
      });
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (!mounted || !identical(_qr, qr)) return;
      setState(() {
        _failure = '开启插座失败';
        _failureHint = '请检查手机蓝牙和设备状态后重试';
        _view = _SmartSocketView.error;
      });
    }
  }

  String? _failureHintFor(SmartSocketFailure error, String failure) {
    if (error.uncertainDeviceState) {
      return '请先确认插座当前状态，再决定是否重试';
    }
    return switch (failure) {
      '蓝牙未开启' => '请开启手机蓝牙后重试',
      '配对失败' || '配对超时' => '请在系统弹出配对请求时点击确认后重试',
      '此手机无法连接该插座' || '无法识别此插座' => null,
      _ => '请检查手机蓝牙和设备状态后重试',
    };
  }

  Future<void> _disconnectForBackground() async {
    if (_view != _SmartSocketView.opening) return;
    await _service.disconnect();
    if (!mounted || _view != _SmartSocketView.opening) return;
    setState(() {
      _failure = '连接中断';
      _failureHint = '请检查手机蓝牙和设备状态后重试';
      _view = _SmartSocketView.error;
    });
  }

  Future<void> _scanAgain() async {
    await _service.disconnect();
    _qr = null;
    await _prepareScanner();
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      _qr = null;
      _failure = null;
      _failureHint = null;
      _permanentlyDenied = false;
      _openingMessage = '正在准备开启';
      _view = _SmartSocketView.ready;
    });
  }

  Future<void> _retryAfterSettings() async {
    if (_qr == null) {
      await _prepareScanner();
      return;
    }
    if (!mounted) return;
    setState(() {
      _permanentlyDenied = false;
      _failure = null;
      _failureHint = null;
      _view = _SmartSocketView.review;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云达人')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _buildBody(context),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) => switch (_view) {
    _SmartSocketView.ready => _buildReady(context),
    _SmartSocketView.scanning => const _SmartSocketState(
      key: ValueKey('scanning'),
      icon: Icons.qr_code_scanner,
      title: '正在准备扫码',
      loading: true,
    ),
    _SmartSocketView.review => _buildReview(context),
    _SmartSocketView.opening => _buildOpening(context),
    _SmartSocketView.success => _buildSuccess(context),
    _SmartSocketView.error => _buildError(context),
    _SmartSocketView.unsupported => const _SmartSocketState(
      key: ValueKey('unsupported'),
      icon: Icons.phone_android_outlined,
      title: '此设备暂不支持',
      message: '仅支持在 Android 手机上使用',
    ),
  };

  Widget _buildReady(BuildContext context) => ListView(
    key: const ValueKey('ready'),
    padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
    children: [
      const _SmartSocketState(icon: Icons.power_outlined, title: '扫码启动插座'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _prepareScanner,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('扫描设备码'),
      ),
      const SizedBox(height: 32),
      Text(
        '仅支持下图这种扫码插座',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 12),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/yundaren_socket.jpg',
            height: 260,
            fit: BoxFit.contain,
            semanticLabel: '支持的凯路创新扫码用电插座',
          ),
        ),
      ),
    ],
  );

  Widget _buildReview(BuildContext context) => ListView(
    key: const ValueKey('review'),
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
    children: [
      const _SmartSocketState(
        icon: Icons.power_outlined,
        title: '识别成功',
        message: '开启时长：5 分钟',
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _openSocket,
        icon: const Icon(Icons.power_settings_new),
        label: const Text('开启插座'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _scanAgain,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('重新扫描'),
      ),
    ],
  );

  Widget _buildOpening(BuildContext context) => _SmartSocketState(
    key: const ValueKey('opening'),
    icon: Icons.sync,
    title: _openingMessage,
    message: '请将手机靠近插座',
    loading: true,
  );

  Widget _buildSuccess(BuildContext context) => ListView(
    key: const ValueKey('success'),
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
    children: [
      const _SmartSocketState(
        icon: Icons.check_circle_outline,
        title: '开启成功',
        message: null,
      ),
      const SizedBox(height: 20),
      FilledButton.tonalIcon(
        onPressed: _finish,
        icon: const Icon(Icons.done),
        label: const Text('完成'),
      ),
    ],
  );

  Widget _buildError(BuildContext context) {
    final failure = _failure ?? '开启插座失败';
    return ListView(
      key: const ValueKey('error'),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        _SmartSocketState(
          icon: Icons.error_outline,
          title: failure,
          message: _failureHint,
          error: true,
        ),
        const SizedBox(height: 20),
        if (_permanentlyDenied) ...[
          FilledButton.icon(
            onPressed: _permissionService.openApplicationSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('打开应用设置'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _retryAfterSettings,
            icon: const Icon(Icons.refresh),
            label: const Text('已允许权限，重试'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _scanAgain,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.dispose());
    super.dispose();
  }
}

class _SmartSocketState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final bool loading;
  final bool error;

  const _SmartSocketState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.loading = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: error ? colors.error : colors.primary,
                ),
              )
            else
              Icon(
                icon,
                size: 56,
                color: error ? colors.error : colors.primary,
              ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            if (message?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
