import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../pages/host_permission_purpose_overlay.dart';
import '../services/host_permission_service.dart';
import '../services/host_platform.dart';
import 'qr_image_decoder.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// Formats understood by the host QR scanner.
///
/// The enum is intentionally owned by the host. Applications should validate
/// their own payload after receiving a [QrDecodedSymbol].
enum QrSymbolFormat { qr }

/// Compatibility aliases for callers that use the more explicit names.
typedef QrCodeFormat = QrSymbolFormat;
typedef QrPayloadFormat = QrSymbolFormat;
typedef QrFormat = QrSymbolFormat;

enum QrScanSource { camera, gallery }

class QrDecodedSymbol {
  final String rawValue;
  final QrSymbolFormat format;
  final QrScanSource source;

  const QrDecodedSymbol({
    required this.rawValue,
    required this.format,
    required this.source,
  });

  String get raw => rawValue;

  String get content => rawValue;

  String get rawContent => rawValue;
}

class QrDecodeResult<T> {
  final T? value;
  final String? errorMessage;

  const QrDecodeResult._({this.value, this.errorMessage});

  const QrDecodeResult.success(T value) : this._(value: value);

  const QrDecodeResult.failure(String message) : this._(errorMessage: message);

  /// Alias for [success] that reads naturally at a call site.
  const QrDecodeResult.valid(T value) : this._(value: value);

  /// Alias for [failure] for payload validators.
  const QrDecodeResult.invalid(String message) : this._(errorMessage: message);

  bool get isSuccess => errorMessage == null;

  bool get isValid => isSuccess;

  bool get isFailure => !isSuccess;

  String? get message => errorMessage;

  String? get error => errorMessage;

  T? get decoded => value;
}

typedef QrPayloadDecoder<T> =
    QrDecodeResult<T> Function(QrDecodedSymbol symbol);

class QrScanRequest<T> {
  final String title;
  final String prompt;
  final List<QrSymbolFormat> formats;
  final QrPayloadDecoder<T> decoder;

  QrScanRequest({
    this.title = '扫一扫',
    this.prompt = '将二维码放入框内即可自动识别',
    Iterable<QrSymbolFormat>? formats,
    Iterable<QrSymbolFormat>? allowedFormats,
    required this.decoder,
  }) : formats = List.unmodifiable(
         allowedFormats ?? formats ?? const [QrSymbolFormat.qr],
       );

  String get hint => prompt;

  String get instruction => prompt;

  List<QrSymbolFormat> get allowedFormats => formats;
}

/// Shared host capability for camera and gallery QR recognition.
///
/// The capability owns all camera resources. A feature supplies only a
/// decoder for its own typed payload and receives a single value, or `null`
/// when the user cancels the scanner.
class QrScannerCapability {
  static const MethodChannel _harmonyChannel = MethodChannel(
    'moe.rinn.mychu/harmony_qr_scanner',
  );

  final HostPermissionService permissionService;
  final TargetPlatform? platformOverride;
  final HostPlatform? hostPlatformOverride;
  final Future<Object?> Function(String method)? harmonyInvoker;

  QrScannerCapability({
    HostPermissionService? permissionService,
    @visibleForTesting TargetPlatform? platform,
    @visibleForTesting HostPlatform? hostPlatform,
    @visibleForTesting this.harmonyInvoker,
  }) : permissionService = permissionService ?? hostPermissionService,
       platformOverride = platform,
       hostPlatformOverride = hostPlatform;

  TargetPlatform get _platform => platformOverride ?? defaultTargetPlatform;

  HostPlatform get _hostPlatform =>
      hostPlatformOverride ??
      (platformOverride == null
          ? HostPlatform.current
          : HostPlatform.resolve(
            platformName: platformOverride!.name,
            isWeb: kIsWeb,
          ));

  Future<T?> scan<T>(BuildContext context, QrScanRequest<T> request) async {
    if (kIsWeb) {
      _showMessage(context, '当前平台暂不支持相机扫码。');
      return null;
    }
    if (_hostPlatform == HostPlatform.harmony) {
      if (!context.mounted) return null;
      return Navigator.of(context).push<T>(
        MaterialPageRoute<T>(
          fullscreenDialog: true,
          builder:
              (_) => _HarmonyQrScannerPage<T>(
                request: request,
                invokeScanner: _invokeHarmonyScanner,
              ),
        ),
      );
    }
    if (_hostPlatform != HostPlatform.android &&
        _hostPlatform != HostPlatform.apple) {
      _showMessage(context, '当前平台暂不支持相机扫码。');
      return null;
    }
    final permission = await permissionService.requestQrScannerPermissions(
      presentPurpose:
          (purpose) => presentHostPermissionPurpose(context, purpose),
    );
    if (!permission.granted) {
      if (context.mounted) {
        await _showPermissionFailure(context, permission.permanentlyDenied);
      }
      return null;
    }
    if (!context.mounted) return null;
    Widget pageBuilder(BuildContext _) =>
        _QrScannerPage<T>(request: request, platform: _platform);
    final route = MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: pageBuilder,
    );
    return Navigator.of(context).push<T>(route);
  }

  Future<void> _showPermissionFailure(
    BuildContext context,
    bool permanentlyDenied,
  ) async {
    final openSettings =
        permanentlyDenied
            ? await showDialog<bool>(
              context: context,
              builder:
                  (dialogContext) => AlertDialog(
                    title: const Text('需要相机权限'),
                    content: const Text('请在系统设置中允许 MyCHU 使用相机后再扫码。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('打开设置'),
                      ),
                    ],
                  ),
            )
            : false;
    if (openSettings == true) {
      await permissionService.openApplicationSettings();
      return;
    }
    if (!permanentlyDenied && context.mounted) {
      _showMessage(context, '需要相机权限才能扫码。');
    }
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Object?> _invokeHarmonyScanner() =>
      harmonyInvoker?.call('scan') ??
      _harmonyChannel.invokeMethod<Object?>('scan');
}

final qrScannerCapability = QrScannerCapability();

class _HarmonyQrScannerPage<T> extends StatefulWidget {
  final QrScanRequest<T> request;
  final Future<Object?> Function() invokeScanner;

  const _HarmonyQrScannerPage({
    required this.request,
    required this.invokeScanner,
  });

  @override
  State<_HarmonyQrScannerPage<T>> createState() =>
      _HarmonyQrScannerPageState<T>();
}

class _HarmonyQrScannerPageState<T> extends State<_HarmonyQrScannerPage<T>> {
  static const int _maxImageBytes = 20 * 1024 * 1024;

  bool _working = false;
  String? _message;

  Future<void> _scanWithSystemUi() async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final result = await widget.invokeScanner();
      if (!mounted || result == null) return;
      if (result is! Map) {
        setState(() => _message = '扫码结果无效，请重试或从图片选择。');
        return;
      }
      final rawValue = result['rawValue'];
      if (rawValue is! String || rawValue.trim().isEmpty) {
        setState(() => _message = '没有读取到二维码内容，请重试或从图片选择。');
        return;
      }
      final source =
          result['source'] == 'gallery'
              ? QrScanSource.gallery
              : QrScanSource.camera;
      await _deliver(rawValue, source);
    } on MissingPluginException {
      if (mounted) {
        setState(() => _message = '系统扫码器暂不可用，可以改为从图片选择二维码。');
      }
    } on PlatformException {
      if (mounted) {
        setState(() => _message = '系统扫码器暂不可用，可以改为从图片选择二维码。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '扫码失败，可以改为从图片选择二维码。');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '二维码图片',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
          ),
        ],
        confirmButtonText: '选择',
      );
      if (!mounted || selected == null) return;
      final bytes = await selected.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        setState(() => _message = '图片过大，请选择小于 20 MB 的二维码图片。');
        return;
      }
      final rawValue = await compute(decodeQrImageBytes, bytes);
      if (rawValue == null || rawValue.trim().isEmpty) {
        setState(() => _message = '图片中未找到二维码，请选择清晰的二维码图片。');
        return;
      }
      await _deliver(rawValue, QrScanSource.gallery);
    } on MissingPluginException {
      if (mounted) setState(() => _message = '当前系统无法打开图片选择器。');
    } on PlatformException {
      if (mounted) setState(() => _message = '图片读取失败，请重新选择。');
    } catch (_) {
      if (mounted) setState(() => _message = '图片解析失败，请选择清晰的二维码图片。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deliver(String rawValue, QrScanSource source) async {
    QrDecodeResult<T> decoded;
    try {
      decoded = widget.request.decoder(
        QrDecodedSymbol(
          rawValue: rawValue.trim(),
          format: QrSymbolFormat.qr,
          source: source,
        ),
      );
    } catch (_) {
      decoded = const QrDecodeResult.failure('二维码内容无法识别，请重试。');
    }
    if (decoded.isSuccess && decoded.value != null) {
      await HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop<T>(context, decoded.value);
      return;
    }
    if (mounted) {
      setState(() => _message = decoded.errorMessage ?? '二维码内容无法识别，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: Text(widget.request.title),
          leading: IconButton(
            tooltip: '关闭',
            onPressed: _working ? null : () => Navigator.pop<T>(context),
            icon: const Icon(Icons.close),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, size: 56, color: colors.primary),
                  const SizedBox(height: 20),
                  Text(
                    widget.request.prompt,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _working ? null : _scanWithSystemUi,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('使用系统扫码器'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('从图片选择二维码'),
                    ),
                  ),
                  if (_working) ...[
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(),
                  ],
                  if (_message case final message?) ...[
                    const SizedBox(height: 18),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrScannerPage<T> extends StatefulWidget {
  final QrScanRequest<T> request;
  final TargetPlatform platform;

  const _QrScannerPage({required this.request, required this.platform});

  @override
  State<_QrScannerPage<T>> createState() => _QrScannerPageState<T>();
}

class _QrScannerPageState<T> extends State<_QrScannerPage<T>>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  String? _message;
  String? _lastRaw;
  DateTime? _lastSeenAt;
  bool _delivering = false;
  bool _starting = false;
  bool _backgrounded = false;
  QrScanSource _source = QrScanSource.camera;
  double _zoomStartScale = 0.0;
  double? _pendingZoomScale;
  bool _zoomUpdateInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
      autoZoom: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgrounded = true;
        unawaited(_controller.stop());
      case AppLifecycleState.resumed:
        if (_backgrounded) {
          _backgrounded = false;
          unawaited(_startCamera());
        }
    }
  }

  Future<void> _startCamera({bool clearMessage = true}) async {
    if (!mounted || _delivering || _starting) return;
    _starting = true;
    try {
      await _controller.start();
      if (!mounted) return;
      if (_controller.value.error != null) {
        setState(() => _message = '相机启动失败，请检查权限后重试。');
        return;
      }
      if (clearMessage) setState(() => _message = null);
    } catch (_) {
      if (mounted) setState(() => _message = '相机启动失败，请检查权限后重试。');
    } finally {
      _starting = false;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_delivering || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null ||
          raw.isEmpty ||
          barcode.format != BarcodeFormat.qrCode) {
        continue;
      }
      final now = DateTime.now();
      if (_lastRaw == raw &&
          _lastSeenAt != null &&
          now.difference(_lastSeenAt!) < const Duration(seconds: 2)) {
        continue;
      }
      _lastRaw = raw;
      _lastSeenAt = now;
      await _decode(
        QrDecodedSymbol(
          rawValue: raw,
          format: QrSymbolFormat.qr,
          source: _source,
        ),
      );
      if (_delivering) return;
    }
  }

  Future<void> _decode(QrDecodedSymbol symbol) async {
    QrDecodeResult<T> result;
    try {
      result = widget.request.decoder(symbol);
    } catch (_) {
      result = const QrDecodeResult.failure('二维码内容无法识别，请重试。');
    }
    if (result.isSuccess && result.value != null) {
      _delivering = true;
      _pendingZoomScale = null;
      await HapticFeedback.mediumImpact();
      await _controller.stop();
      if (mounted) Navigator.pop<T>(context, result.value);
      return;
    }
    if (mounted) {
      setState(() => _message = result.errorMessage ?? '二维码内容无法识别，请重试。');
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _zoomStartScale = _controller.value.zoomScale.clamp(0.0, 1.0).toDouble();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_delivering || !_controller.value.isRunning) return;

    // mobile_scanner exposes a normalized linear zoom value. Matching the
    // additive delta used by ai_barcode_scanner keeps pinch motion predictable
    // while allowing the controller to apply platform-specific smoothing.
    final target =
        (_zoomStartScale + (details.scale - 1.0)).clamp(0.0, 1.0).toDouble();
    _pendingZoomScale = target;
    if (_zoomUpdateInFlight) return;
    _zoomUpdateInFlight = true;
    unawaited(_drainZoomScaleUpdates());
  }

  Future<void> _drainZoomScaleUpdates() async {
    try {
      while (mounted && !_delivering) {
        final target = _pendingZoomScale;
        if (target == null) break;
        _pendingZoomScale = null;
        if (!_controller.value.isRunning) continue;
        try {
          await _controller.setZoomScale(target);
        } catch (_) {
          break;
        }
      }
    } finally {
      _zoomUpdateInFlight = false;
      if (mounted && !_delivering && _pendingZoomScale != null) {
        _zoomUpdateInFlight = true;
        unawaited(_drainZoomScaleUpdates());
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_delivering) return;
    await _controller.stop();
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '二维码图片',
          extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
        ),
      ],
      confirmButtonText: '选择',
    );
    if (!mounted || selected == null) {
      if (mounted) unawaited(_startCamera());
      return;
    }
    _source = QrScanSource.gallery;
    try {
      final capture = await _controller.analyzeImage(
        selected.path,
        formats: const [BarcodeFormat.qrCode],
      );
      final barcode = capture?.barcodes.firstWhere(
        (item) =>
            item.format == BarcodeFormat.qrCode &&
            item.rawValue?.trim().isNotEmpty == true,
        orElse: () => const Barcode(rawValue: null),
      );
      final raw = barcode?.rawValue?.trim();
      if (raw == null || raw.isEmpty) {
        if (mounted) setState(() => _message = '图片中未找到二维码，请选择清晰的二维码图片。');
      } else {
        await _decode(
          QrDecodedSymbol(
            rawValue: raw,
            format: QrSymbolFormat.qr,
            source: QrScanSource.gallery,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '图片解析失败，请选择清晰的二维码图片。');
    } finally {
      _source = QrScanSource.camera;
      if (mounted && !_delivering) {
        unawaited(_startCamera(clearMessage: false));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingZoomScale = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.request.title),
          leading: IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.pop<T>(context),
            icon: const Icon(Icons.close),
          ),
        ),
      ),
      body: SafeArea(top: false, child: _buildScannerStack(context)),
    );
  }

  Widget _buildScannerStack(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanWindow = _calculateScanWindow(constraints.biggest);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                scanWindow: scanWindow,
                errorBuilder: (context, _) => _buildCameraError(context),
                placeholderBuilder:
                    (_) => const ColoredBox(color: Colors.black),
                tapToFocus: true,
              ),
              _QrScannerOverlay(scanWindow: scanWindow),
              Positioned(
                left: 24,
                right: 24,
                bottom: 106,
                child: _buildHint(context, colors),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 14, 32, 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ScannerAction(
                          icon: Icons.photo_library_outlined,
                          label: '相册',
                          onPressed: _pickFromGallery,
                        ),
                        ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _controller,
                          builder: (context, state, _) {
                            if (state.torchState == TorchState.unavailable) {
                              return const SizedBox(width: 72);
                            }
                            return _ScannerAction(
                              icon:
                                  state.torchState == TorchState.on
                                      ? Icons.flash_on
                                      : Icons.flash_off,
                              label: '手电筒',
                              onPressed: _controller.toggleTorch,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Rect _calculateScanWindow(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.shortestSide <= 0) {
      return Rect.zero;
    }
    final frameSize = math.min<double>(size.shortestSide * 0.68, 360.0);
    final minCenterY = frameSize / 2 + 24;
    final maxCenterY = math.max<double>(
      minCenterY,
      size.height - frameSize / 2 - 112,
    );
    final centerY =
        (size.height * 0.43).clamp(minCenterY, maxCenterY).toDouble();
    return Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: frameSize,
      height: frameSize,
    );
  }

  Widget _buildHint(BuildContext context, ColorScheme colors) {
    final message = _message ?? widget.request.prompt;
    final isError = _message != null;
    final theme = Theme.of(context);
    final foreground = isError ? colors.onErrorContainer : Colors.white;
    final background =
        isError
            ? colors.errorContainer.withValues(alpha: 0.96)
            : Colors.black.withValues(alpha: 0.58);
    final borderColor =
        isError
            ? colors.onErrorContainer.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.18);
    final maxWidth = math.min<double>(
      420.0,
      math.max<double>(0.0, MediaQuery.sizeOf(context).width - 48),
    );

    return Semantics(
      liveRegion: true,
      label: message,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Align(
          key: ValueKey(message),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isError
                          ? Icons.info_outline_rounded
                          : Icons.qr_code_scanner_rounded,
                      color: foreground,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: (theme.textTheme.labelLarge ?? const TextStyle())
                            .copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraError(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FilledButton.tonalIcon(
          onPressed: _startCamera,
          icon: const Icon(Icons.refresh),
          label: const Text('重试相机'),
        ),
      ),
    );
  }
}

class _ScannerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _ScannerAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 28), const SizedBox(height: 4), Text(label)],
    );
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      child: child,
    );
  }
}

class _QrScannerOverlay extends StatelessWidget {
  final Rect scanWindow;

  const _QrScannerOverlay({required this.scanWindow});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _QrScannerOverlayPainter(scanWindow: scanWindow),
      ),
    );
  }
}

class _QrScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  const _QrScannerOverlayPainter({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final frame = scanWindow;
    if (frame.isEmpty) return;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.38);
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, shade);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(18)),
      clear,
    );
    canvas.restore();

    final marker =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    const markerLength = 30.0;
    const cornerRadius = 10.0;
    final path =
        Path()
          // Top-left.
          ..moveTo(frame.left, frame.top + markerLength)
          ..lineTo(frame.left, frame.top + cornerRadius)
          ..quadraticBezierTo(
            frame.left,
            frame.top,
            frame.left + cornerRadius,
            frame.top,
          )
          ..lineTo(frame.left + markerLength, frame.top)
          // Top-right.
          ..moveTo(frame.right - markerLength, frame.top)
          ..lineTo(frame.right - cornerRadius, frame.top)
          ..quadraticBezierTo(
            frame.right,
            frame.top,
            frame.right,
            frame.top + cornerRadius,
          )
          ..lineTo(frame.right, frame.top + markerLength)
          // Bottom-right.
          ..moveTo(frame.right, frame.bottom - markerLength)
          ..lineTo(frame.right, frame.bottom - cornerRadius)
          ..quadraticBezierTo(
            frame.right,
            frame.bottom,
            frame.right - cornerRadius,
            frame.bottom,
          )
          ..lineTo(frame.right - markerLength, frame.bottom)
          // Bottom-left.
          ..moveTo(frame.left + markerLength, frame.bottom)
          ..lineTo(frame.left + cornerRadius, frame.bottom)
          ..quadraticBezierTo(
            frame.left,
            frame.bottom,
            frame.left,
            frame.bottom - cornerRadius,
          )
          ..lineTo(frame.left, frame.bottom - markerLength);
    canvas.drawPath(path, marker);
  }

  @override
  bool shouldRepaint(covariant _QrScannerOverlayPainter oldDelegate) =>
      oldDelegate.scanWindow != scanWindow;
}
