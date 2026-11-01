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

/// Shown when a decoded payload is not a valid symbol for the requesting app.
const String _unrecognizedQrMessage = '二维码内容无法识别，请重试。';

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

/// Suppresses repeat captures of an identical payload for a short window.
///
/// The platform keeps reporting the same code while it stays in the viewfinder,
/// so the page decodes each distinct payload at most once per [window]. The
/// window is measured from the last capture that was allowed through, so a code
/// that never leaves the view becomes eligible again instead of being
/// suppressed forever.
@visibleForTesting
class QrCaptureDeduplicator {
  QrCaptureDeduplicator({this.window = const Duration(seconds: 2)});

  final Duration window;

  String? _rawValue;
  DateTime? _acceptedAt;

  bool shouldSuppress(String rawValue, DateTime now) {
    final lastValue = _rawValue;
    final lastAt = _acceptedAt;
    final suppressed =
        lastValue == rawValue &&
        lastAt != null &&
        now.difference(lastAt) < window;
    if (!suppressed) {
      _rawValue = rawValue;
      _acceptedAt = now;
    }
    return suppressed;
  }

  void reset() {
    _rawValue = null;
    _acceptedAt = null;
  }
}

/// What a queued camera request needs the session to do when it gets the turn.
enum QrCameraIntent {
  /// Bring the camera up if it is not running.
  start,

  /// Release the camera and leave it released, e.g. while a system picker owns
  /// the foreground.
  pause,

  /// Recreate the session: release, then start again.
  restart,
}

/// Whether the scanner page may have the camera running right now.
///
/// The same predicate gates a queued request and re-checks after an
/// asynchronous `start()`: a platform start can win the race against the
/// `stop()` issued when the app moves to the background, and in that case the
/// camera has to be released once the start returns.
@visibleForTesting
bool qrScannerCameraMayRun({
  required bool mounted,
  required bool delivering,
  required bool backgrounded,
  required bool galleryActive,
}) => mounted && !delivering && !backgrounded && !galleryActive;

/// One queued camera operation together with the future its caller awaits.
class _QrCameraRequest {
  _QrCameraRequest(this.operation, this.intent);

  final Future<void> Function() operation;
  final QrCameraIntent intent;
  final Completer<void> done = Completer<void>();
}

/// Serialises camera operations for one scanner page.
///
/// A request that arrives while an operation runs is queued with its own
/// closure, and its future completes only once that closure ran or was dropped,
/// so awaiting a queued pause really waits for the camera to be released. A
/// queued [QrCameraIntent.pause] keeps precedence over a later restart, and a
/// queued restart keeps precedence over a later start; between a pause and a
/// start the latest request wins, so a `resumed` start still brings the camera
/// back. [canStart] is re-evaluated before every gated run; pauses always run,
/// because the camera must be released regardless. A failing operation only
/// fails that request; the coordinator stays usable.
@visibleForTesting
class QrCameraSessionCoordinator {
  QrCameraSessionCoordinator({bool Function()? canStart})
    : _canStart = canStart ?? _alwaysAllow;

  static bool _alwaysAllow() => true;

  final bool Function() _canStart;
  bool _busy = false;
  _QrCameraRequest? _pending;

  bool get isBusy => _busy;

  Future<void> request(
    Future<void> Function() operation, {
    QrCameraIntent intent = QrCameraIntent.start,
  }) async {
    final request = _QrCameraRequest(operation, intent);
    if (_busy) {
      final pending = _pending;
      if (pending != null && pending.intent == intent) {
        // Same intent: both callers wait for the queued operation, and one
        // execution satisfies them (one stop, one start, one restart).
        return pending.done.future;
      }
      _enqueue(request);
      return request.done.future;
    }

    _busy = true;
    try {
      var current = request;
      while (true) {
        await _run(current);
        final next = _pending;
        _pending = null;
        if (next == null) break;
        current = next;
      }
    } finally {
      _busy = false;
      final dropped = _pending;
      _pending = null;
      _complete(dropped);
    }
  }

  Future<void> _run(_QrCameraRequest request) async {
    try {
      if (request.intent == QrCameraIntent.pause || _canStart()) {
        await request.operation();
      }
    } finally {
      _complete(request);
    }
  }

  void _enqueue(_QrCameraRequest request) {
    final pending = _pending;
    if (pending != null) {
      // A queued release must not be dropped for a restart, and a queued
      // recovery must not be dropped for a plain start; a request that cannot
      // run right now (gated off) must not displace one that can.
      final releaseBeforeRestart =
          pending.intent == QrCameraIntent.pause &&
          request.intent == QrCameraIntent.restart;
      final recoveryBeforeStart =
          pending.intent == QrCameraIntent.restart &&
          request.intent == QrCameraIntent.start;
      final cannotRunNow =
          request.intent != QrCameraIntent.pause && !_canStart();
      if (releaseBeforeRestart || recoveryBeforeStart || cannotRunNow) {
        _complete(request);
        return;
      }
      _complete(pending);
    }
    _pending = request;
  }

  void _complete(_QrCameraRequest? request) {
    if (request == null || request.done.isCompleted) return;
    request.done.complete();
  }
}

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
      if (mounted) setState(() => _message = '无法打开图片选择器，可以继续用相机扫码。');
    } on PlatformException {
      if (mounted) setState(() => _message = '图片无法识别，请重新选择。');
    } catch (_) {
      if (mounted) setState(() => _message = '图片无法识别，请重新选择。');
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
      decoded = const QrDecodeResult.failure(_unrecognizedQrMessage);
    }
    if (decoded.isSuccess && decoded.value != null) {
      await HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop<T>(context, decoded.value);
      return;
    }
    if (mounted) {
      setState(() => _message = decoded.errorMessage ?? _unrecognizedQrMessage);
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
  final QrCaptureDeduplicator _dedupe = QrCaptureDeduplicator();
  late final QrCameraSessionCoordinator _cameraSession =
      QrCameraSessionCoordinator(canStart: _cameraMayRun);
  String? _message;
  DateTime? _lastDetectErrorAt;
  bool _delivering = false;
  bool _backgrounded = false;
  bool _galleryActive = false;
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
      // Android records the last reported payload before it applies the scan
      // window and only clears it on start()/release when `noDuplicates` is
      // used. A code that was decoded but filtered out once was therefore never
      // reported again while the page stayed open. `normal` plus the page-level
      // dedupe below keeps one delivery per payload without that latch.
      detectionSpeed: DetectionSpeed.normal,
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
        unawaited(_pauseCamera());
      case AppLifecycleState.resumed:
        if (_backgrounded) {
          _backgrounded = false;
          unawaited(_startCamera());
        }
    }
  }

  bool _cameraMayRun() => qrScannerCameraMayRun(
    mounted: mounted,
    delivering: _delivering,
    backgrounded: _backgrounded,
    galleryActive: _galleryActive,
  );

  Future<void> _startCamera({bool preserveMessage = false}) async {
    if (!mounted || _delivering) return;
    // The flag travels with this request: a start that the queue drops as
    // unrunnable must not leave the next, unrelated start preserving an old
    // error message.
    await _cameraSession.request(
      () => _performCameraStart(preserveMessage: preserveMessage),
    );
  }

  Future<void> _performCameraStart({bool preserveMessage = false}) async {
    if (!mounted) return;
    try {
      await _controller.start();
      if (!mounted) return;
      // A platform start can win the race against the stop issued when the app
      // moved to the background, so release the camera again when it is no
      // longer allowed to run.
      if (!_cameraMayRun()) {
        await _stopCameraQuietly();
        return;
      }
      if (_controller.value.error != null) {
        setState(() => _message = '相机启动失败，请检查权限后重试。');
        return;
      }
      _dedupe.reset();
      if (!preserveMessage) setState(() => _message = null);
    } catch (_) {
      if (mounted) setState(() => _message = '相机启动失败，请检查权限后重试。');
    }
  }

  Future<void> _stopCameraQuietly() async {
    try {
      await _controller.stop();
    } catch (_) {
      // Nothing left to release.
    }
  }

  /// Releases the camera through the session queue.
  ///
  /// Routing the stop through the queue keeps it from racing a start that is
  /// still in flight: the pause runs after that start and wins, so the camera is
  /// off when the page is backgrounded or a picker owns the foreground.
  Future<void> _pauseCamera() =>
      _cameraSession.request(_stopCameraQuietly, intent: QrCameraIntent.pause);

  /// Recreates the camera session after a platform-side scanner error.
  ///
  /// Errors reported by the plugin never reach `controller.value.error`, so the
  /// `errorBuilder` retry path stays invisible; this is the only recovery for a
  /// camera that is still "running" but no longer producing results. The
  /// teardown runs in the same queue as the starts so it cannot race one.
  Future<void> _recoverCamera() async {
    if (!mounted || _delivering) return;
    await _cameraSession.request(
      _restartCameraSession,
      intent: QrCameraIntent.restart,
    );
  }

  Future<void> _restartCameraSession() async {
    await _stopCameraQuietly();
    await _performCameraStart();
  }

  void _onDetectError(Object error, StackTrace stackTrace) {
    if (!mounted || _delivering) return;
    final now = DateTime.now();
    final lastAt = _lastDetectErrorAt;
    if (lastAt != null && now.difference(lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastDetectErrorAt = now;
    setState(() => _message = '扫码暂时不可用，正在重试…');
    unawaited(_recoverCamera());
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_delivering || !mounted) return;
    final now = DateTime.now();
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null ||
          raw.isEmpty ||
          barcode.format != BarcodeFormat.qrCode) {
        continue;
      }
      if (_dedupe.shouldSuppress(raw, now)) continue;
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
      result = const QrDecodeResult.failure(_unrecognizedQrMessage);
    }
    if (result.isSuccess && result.value != null) {
      _delivering = true;
      _pendingZoomScale = null;
      // Haptics and camera teardown are best effort: neither may keep the page
      // open with a latched `_delivering` that disables every later detection.
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {
        // A missing haptics channel is not a scan failure.
      }
      try {
        await _controller.stop();
      } catch (_) {
        // The route is popped below, which releases the session anyway.
      }
      if (mounted) Navigator.pop<T>(context, result.value);
      return;
    }
    final message = result.errorMessage ?? _unrecognizedQrMessage;
    if (mounted && _message != message) {
      setState(() => _message = message);
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
    // The picker owns the camera while it is open: starts, recoveries and the
    // post-start check all consult this flag.
    _galleryActive = true;
    try {
      // Awaiting the queued pause blocks until the camera is actually released,
      // so the picker never opens while a start is still bringing it up.
      await _pauseCamera();
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '二维码图片',
            extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
          ),
        ],
        confirmButtonText: '选择',
      );
      if (mounted && selected != null) {
        _source = QrScanSource.gallery;
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
      }
    } on MissingPluginException {
      if (mounted) setState(() => _message = '无法打开图片选择器，可以继续用相机扫码。');
    } on PlatformException {
      if (mounted) setState(() => _message = '图片无法识别，请重新选择。');
    } catch (_) {
      if (mounted) setState(() => _message = '图片无法识别，请重新选择。');
    } finally {
      _galleryActive = false;
      _source = QrScanSource.camera;
      // The camera is restarted from the same branch that stopped it, so a
      // failed or cancelled picker can never leave the page without a camera.
      if (mounted && !_delivering) {
        unawaited(_startCamera(preserveMessage: true));
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
                onDetectError: _onDetectError,
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
