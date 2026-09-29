import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'platform_compatibility_service.dart';
import 'host_platform.dart';

typedef HostPermissionRequester =
    Future<PermissionStatus> Function(Permission permission);
typedef HostPermissionStatusChecker =
    Future<PermissionStatus> Function(Permission permission);
typedef AndroidSdkIntProvider = Future<int?> Function();

class HostPermissionPurpose {
  final Permission permission;
  final String title;
  final String message;

  const HostPermissionPurpose({
    required this.permission,
    required this.title,
    required this.message,
  });
}

/// Handle returned by the in-app permission purpose overlay.
///
/// The overlay stays visible while the operating system permission dialog is
/// open, then the coordinator dismisses it before moving to the next request.
class HostPermissionPromptHandle {
  final void Function() _dismissCallback;
  bool _dismissed = false;

  HostPermissionPromptHandle(this._dismissCallback);

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _dismissCallback();
  }
}

typedef HostPermissionPurposePresenter =
    Future<HostPermissionPromptHandle?> Function(HostPermissionPurpose purpose);

class HostPermissionFeatureResult {
  final bool supported;
  final bool granted;
  final bool permanentlyDenied;

  const HostPermissionFeatureResult({
    required this.supported,
    required this.granted,
    required this.permanentlyDenied,
  });

  static const unsupported = HostPermissionFeatureResult(
    supported: false,
    granted: false,
    permanentlyDenied: false,
  );
}

/// Coordinates permissions that belong to host-provided built-in features.
///
/// Runtime permission requests are coordinated only for host-provided
/// built-in features.
class HostPermissionService {
  static const HostPermissionPurpose notificationPurpose =
      HostPermissionPurpose(
        permission: Permission.notification,
        title: '通知权限申请',
        message: '用于在成绩、待办等重要信息更新时发送系统提醒。',
      );

  static const List<HostPermissionPurpose> initialHomePurposes = [
    notificationPurpose,
    locationPurpose,
    HostPermissionPurpose(
      permission: Permission.microphone,
      title: '麦克风权限申请',
      message: '用于校园网页中的音频或视频功能，不会在后台录音。',
    ),
  ];

  static const HostPermissionPurpose locationPurpose = HostPermissionPurpose(
    permission: Permission.locationWhenInUse,
    title: '定位权限申请',
    message: '用于地图中的当前位置定位，仅在你主动使用定位功能时访问。',
  );

  static List<Permission> get initialHomePermissions => [
    for (final purpose in initialHomePurposes) purpose.permission,
  ];

  static const HostPermissionPurpose qrScannerPurpose = HostPermissionPurpose(
    permission: Permission.camera,
    title: '相机权限申请',
    message: '用于扫描二维码，仅在你主动使用扫码功能时访问。',
  );

  static const HostPermissionPurpose _nearbyScanPurpose = HostPermissionPurpose(
    permission: Permission.bluetoothScan,
    title: '附近设备权限申请',
    message: '用于在你主动测试时查找二维码对应的 BLE 设备。',
  );

  static const HostPermissionPurpose _nearbyConnectPurpose =
      HostPermissionPurpose(
        permission: Permission.bluetoothConnect,
        title: '附近设备权限申请',
        message: '用于在你确认测试后连接并向目标 BLE 设备发送协议指令。',
      );

  static const HostPermissionPurpose harmonyBleCentralPurpose =
      HostPermissionPurpose(
        permission: Permission.bluetoothScan,
        title: '附近设备权限申请',
        message: '仅在你主动测试时扫描附近 BLE 设备，并连接二维码对应的设备。',
      );

  static const List<HostPermissionPurpose> bleCentralPurposes = [
    _nearbyScanPurpose,
    _nearbyConnectPurpose,
  ];

  static const HostPermissionPurpose _legacyBleLocationPurpose =
      HostPermissionPurpose(
        permission: Permission.locationWhenInUse,
        title: '定位权限申请',
        message: '旧版 Android 扫描附近 BLE 设备时需要定位权限。',
      );

  static const int androidLegacyBleLocationMaxSdk = 30;

  static List<HostPermissionPurpose> bleCentralPurposesForSdk(int? sdkInt) => [
    ...bleCentralPurposes,
    if (sdkInt != null && sdkInt <= androidLegacyBleLocationMaxSdk)
      _legacyBleLocationPurpose,
  ];

  final HostPermissionRequester _requestPermission;
  final HostPermissionStatusChecker _checkPermission;
  final AndroidSdkIntProvider _androidSdkIntProvider;
  final HostPlatform _hostPlatform;
  Future<void>? _inFlight;
  Future<void> _permissionTail = Future<void>.value();
  bool _requestedThisProcess = false;

  static const MethodChannel _harmonyLocationChannel = MethodChannel(
    'moe.rinn.mychu/harmony_location',
  );
  static const MethodChannel _harmonyBlePermissionChannel = MethodChannel(
    'moe.rinn.mychu/harmony_ble_permission',
  );

  @visibleForTesting
  static Future<Object?> Function(String method)?
  debugHarmonyLocationPermissionInvoke;
  @visibleForTesting
  static Future<Object?> Function(String method)?
  debugHarmonyBlePermissionInvoke;
  HostPermissionService({
    HostPermissionRequester? requestPermission,
    HostPermissionStatusChecker? checkPermission,
    AndroidSdkIntProvider? androidSdkIntProvider,
    TargetPlatform? platform,
    HostPlatform? hostPlatformOverride,
  }) : _requestPermission = requestPermission ?? _requestWithHandler,
       _checkPermission = checkPermission ?? _checkWithHandler,
       _androidSdkIntProvider =
           androidSdkIntProvider ?? PlatformCompatibilityService.androidSdkInt,
       _hostPlatform =
           hostPlatformOverride ??
           HostPlatform.resolve(
             platformName: (platform ?? defaultTargetPlatform).name,
             isWeb: kIsWeb,
           );

  static Future<PermissionStatus> _checkWithHandler(Permission permission) =>
      permission.status;

  static Future<PermissionStatus> _requestWithHandler(Permission permission) =>
      permission.request();

  /// Requests host permissions once after the first home entry in a process.
  ///
  /// Requests are serialized so Android never receives overlapping permission
  /// dialogs. A denied permission or a platform error is isolated to that
  /// permission and does not prevent the remaining permissions from being
  /// attempted.
  Future<void> requestInitialHomePermissions({
    HostPermissionPurposePresenter? presentPurpose,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (_requestedThisProcess) return Future<void>.value();
    return _inFlight ??= _serialize(() => _requestAll(presentPurpose));
  }

  Future<HostPermissionFeatureResult> requestNotificationPermission({
    HostPermissionPurposePresenter? presentPurpose,
  }) {
    if (kIsWeb || _hostPlatform != HostPlatform.android) {
      return Future.value(HostPermissionFeatureResult.unsupported);
    }
    return _serialize(
      () => _requestFeatureLocked(
        [notificationPurpose],
        presentPurpose: presentPurpose,
      ),
    );
  }

  Future<bool> isNotificationPermissionGranted() async {
    if (kIsWeb || _hostPlatform != HostPlatform.android) return false;
    try {
      return (await _checkPermission(Permission.notification)).isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<HostPermissionFeatureResult> requestQrScannerPermissions({
    HostPermissionPurposePresenter? presentPurpose,
  }) {
    // QR scanning is a host capability on both supported mobile platforms.
    // Keep web unsupported because mobile_scanner cannot access a camera there
    // in the embedded app shell.
    if (_hostPlatform != HostPlatform.android &&
        _hostPlatform != HostPlatform.apple) {
      return Future.value(HostPermissionFeatureResult.unsupported);
    }
    return _serialize(
      () => _requestFeatureLocked([
        qrScannerPurpose,
      ], presentPurpose: presentPurpose),
    );
  }

  /// Requests foreground location only after the user opens the map's
  /// location action. Harmony uses the native permission manager because
  /// permission_handler has no registered OpenHarmony plugin in this app.
  Future<HostPermissionFeatureResult> requestHarmonyLocationPermission({
    HostPermissionPurposePresenter? presentPurpose,
  }) {
    if (_hostPlatform != HostPlatform.harmony) {
      return Future.value(HostPermissionFeatureResult.unsupported);
    }
    return _serialize(() async {
      try {
        final alreadyGranted =
            await _invokeHarmonyLocationPermission('checkPermission') == true;
        if (alreadyGranted) {
          return const HostPermissionFeatureResult(
            supported: true,
            granted: true,
            permanentlyDenied: false,
          );
        }
      } catch (_) {
        return const HostPermissionFeatureResult(
          supported: true,
          granted: false,
          permanentlyDenied: false,
        );
      }

      HostPermissionPromptHandle? prompt;
      try {
        prompt = await presentPurpose?.call(locationPurpose);
      } catch (_) {
        // Keep the native request available if the explanatory UI fails.
      }
      var granted = false;
      try {
        granted =
            await _invokeHarmonyLocationPermission('requestPermission') == true;
      } catch (_) {
        granted = false;
      } finally {
        prompt?.dismiss();
      }
      return HostPermissionFeatureResult(
        supported: true,
        granted: granted,
        permanentlyDenied: false,
      );
    });
  }

  Future<Object?> _invokeHarmonyLocationPermission(String method) =>
      debugHarmonyLocationPermissionInvoke?.call(method) ??
      _harmonyLocationChannel.invokeMethod<Object?>(method);

  Future<HostPermissionFeatureResult> requestBleCentralPermissions({
    HostPermissionPurposePresenter? presentPurpose,
  }) {
    if (_hostPlatform == HostPlatform.harmony) {
      return _serialize(
        () =>
            _requestHarmonyBleCentralPermission(presentPurpose: presentPurpose),
      );
    }
    if (_hostPlatform != HostPlatform.android) {
      return Future.value(HostPermissionFeatureResult.unsupported);
    }
    return _serialize(() async {
      int? sdkInt;
      try {
        sdkInt = await _androidSdkIntProvider();
      } catch (_) {
        // If the host cannot report its API level, avoid blocking modern
        // Android on a legacy location permission.
      }
      return _requestFeatureLocked(
        bleCentralPurposesForSdk(sdkInt),
        presentPurpose: presentPurpose,
      );
    });
  }

  Future<HostPermissionFeatureResult> _requestHarmonyBleCentralPermission({
    HostPermissionPurposePresenter? presentPurpose,
  }) async {
    bool alreadyGranted;
    try {
      alreadyGranted =
          await _invokeHarmonyBlePermission('checkPermission') == true;
    } catch (_) {
      return HostPermissionFeatureResult.unsupported;
    }
    if (alreadyGranted) {
      return const HostPermissionFeatureResult(
        supported: true,
        granted: true,
        permanentlyDenied: false,
      );
    }

    HostPermissionPromptHandle? prompt;
    try {
      prompt = await presentPurpose?.call(harmonyBleCentralPurpose);
    } catch (_) {
      // Permission requests still proceed when the explanatory UI fails.
    }
    try {
      final granted =
          await _invokeHarmonyBlePermission('requestPermission') == true;
      return HostPermissionFeatureResult(
        supported: true,
        granted: granted,
        permanentlyDenied: false,
      );
    } catch (_) {
      return const HostPermissionFeatureResult(
        supported: true,
        granted: false,
        permanentlyDenied: false,
      );
    } finally {
      prompt?.dismiss();
    }
  }

  Future<Object?> _invokeHarmonyBlePermission(String method) =>
      debugHarmonyBlePermissionInvoke?.call(method) ??
      _harmonyBlePermissionChannel.invokeMethod<Object?>(method);

  Future<bool> openApplicationSettings() => openAppSettings();

  Future<void> _requestAll(
    HostPermissionPurposePresenter? presentPurpose,
  ) async {
    _requestedThisProcess = true;
    try {
      if (_hostPlatform != HostPlatform.android) return;

      for (final purpose in initialHomePurposes) {
        PermissionStatus status;
        try {
          status = await _checkPermission(purpose.permission);
        } catch (_) {
          status = PermissionStatus.denied;
        }
        if (status.isGranted ||
            status.isPermanentlyDenied ||
            status.isRestricted) {
          continue;
        }

        HostPermissionPromptHandle? prompt;
        try {
          prompt = await presentPurpose?.call(purpose);
        } catch (_) {
          // A presentation failure must not block the native permission flow.
        }
        try {
          await _requestPermission(purpose.permission);
        } catch (_) {
          // One unavailable or failed permission must not block the rest.
        } finally {
          prompt?.dismiss();
        }
      }
    } finally {
      _inFlight = null;
    }
  }

  Future<HostPermissionFeatureResult> _requestFeatureLocked(
    List<HostPermissionPurpose> purposes, {
    HostPermissionPurposePresenter? presentPurpose,
  }) async {
    var granted = true;
    var permanentlyDenied = false;
    for (final purpose in purposes) {
      PermissionStatus status;
      try {
        status = await _checkPermission(purpose.permission);
      } catch (_) {
        status = PermissionStatus.denied;
      }
      if (status.isGranted) continue;
      if (status.isPermanentlyDenied || status.isRestricted) {
        granted = false;
        permanentlyDenied = true;
        continue;
      }

      HostPermissionPromptHandle? prompt;
      try {
        prompt = await presentPurpose?.call(purpose);
      } catch (_) {
        // Permission requests still proceed when the explanatory UI fails.
      }
      try {
        status = await _requestPermission(purpose.permission);
        if (!status.isGranted) {
          granted = false;
          permanentlyDenied =
              permanentlyDenied ||
              status.isPermanentlyDenied ||
              status.isRestricted;
        }
      } catch (_) {
        granted = false;
      } finally {
        prompt?.dismiss();
      }
    }
    return HostPermissionFeatureResult(
      supported: true,
      granted: granted,
      permanentlyDenied: permanentlyDenied,
    );
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _permissionTail.then((_) => operation());
    _permissionTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

final hostPermissionService = HostPermissionService();
