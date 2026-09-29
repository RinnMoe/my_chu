import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'host_platform.dart';

@immutable
class ExactAlarmStatus {
  final bool supported;
  final bool requested;
  final bool authorized;

  const ExactAlarmStatus({
    required this.supported,
    required this.requested,
    required this.authorized,
  });

  const ExactAlarmStatus.unsupported()
    : supported = false,
      requested = false,
      authorized = false;
}

class PlatformCompatibilityService {
  static const _channel = MethodChannel('mychu/platform_compatibility');
  @visibleForTesting
  static Future<Object?> Function(String method)? debugInvoke;

  /// Android-only native compatibility surfaces stay unavailable on Apple,
  /// HarmonyOS, web, and unsupported desktop platforms. A debug method
  /// override represents a simulated Android host in tests.
  @visibleForTesting
  static HostPlatform? hostPlatformOverride;

  static HostPlatform get _hostPlatform {
    if (debugInvoke != null) return HostPlatform.android;
    return hostPlatformOverride ?? HostPlatform.current;
  }

  static bool get isAndroid => _hostPlatform == HostPlatform.android;

  static bool get isApple => _hostPlatform == HostPlatform.apple;

  static bool get isHarmony => _hostPlatform == HostPlatform.harmony;

  static Future<ExactAlarmStatus> exactAlarmStatus() async {
    if (!isAndroid) return const ExactAlarmStatus.unsupported();
    try {
      final raw =
          await (debugInvoke?.call('exactAlarmStatus') ??
              _channel.invokeMethod<Object?>('exactAlarmStatus'));
      final values = raw is Map ? raw : const {};
      return ExactAlarmStatus(
        supported: values['exactAlarmSupported'] == true,
        requested: values['exactAlarmRequested'] == true,
        authorized: values['exactAlarmAuthorized'] == true,
      );
    } catch (_) {
      return const ExactAlarmStatus.unsupported();
    }
  }

  static Future<int?> androidSdkInt() async {
    if (!isAndroid) return null;
    try {
      final value =
          await (debugInvoke?.call('androidSdkInt') ??
              _channel.invokeMethod<Object?>('androidSdkInt'));
      return value is int && value > 0 ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setExactAlarmRequested(bool requested) async {
    if (!isAndroid) return;
    await (debugInvoke?.call('setExactAlarmRequested') ??
        _channel.invokeMethod<void>('setExactAlarmRequested', {
          'requested': requested,
        }));
    if (requested) {
      await (debugInvoke?.call('openExactAlarmSettings') ??
          _channel.invokeMethod<void>('openExactAlarmSettings'));
    }
  }
}
