import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Named Android system/vendor signals available to built-in host features.
///
/// This is intentionally an allowlist rather than a free-form system property
/// or command API. Add a new enum value and an explicit native mapping when a
/// future compatibility feature needs another stable signal.
enum AndroidDeviceCompatibilityFeature {
  hyperOs('hyper_os'),
  hyperOsByChina('hyper_os_by_china'),
  hyperOsByGlobal('hyper_os_by_global'),
  hyperOsOptimization('hyper_os_optimization'),
  miui('miui'),
  miuiByChina('miui_by_china'),
  miuiByGlobal('miui_by_global'),
  miuiOptimization('miui_optimization'),
  realmeUi('realme_ui'),
  colorOs('color_os'),
  originOs('origin_os'),
  funtouchOs('funtouch_os'),
  magicOs('magic_os'),
  harmonyOs('harmony_os'),
  harmonyOsNextAndroidCompatible('harmony_os_next_android_compatible'),
  emui('emui'),
  oneUi('one_ui'),
  oxygenOs('oxygen_os'),
  h2Os('h2_os'),
  flyme('flyme'),
  redMagicOs('red_magic_os'),
  nebulaAiOs('nebula_ai_os'),
  myOs('my_os'),
  mifavorUi('mifavor_ui'),
  smartisanOs('smartisan_os'),
  eui('eui'),
  zuxOs('zux_os'),
  zui('zui'),
  nubiaUi('nubia_ui'),
  obricUi('obric_ui'),
  rogUi('rog_ui'),
  ui360('ui_360');

  const AndroidDeviceCompatibilityFeature(this.id);

  final String id;
}

@immutable
class AndroidDeviceProfile {
  const AndroidDeviceProfile({
    required this.brandName,
    required this.marketName,
    required this.osName,
    required this.osVersionName,
    required this.osMajorVersion,
    required this.androidSdkInt,
  });

  static const unknown = 'unknown';

  final String brandName;
  final String marketName;
  final String osName;
  final String osVersionName;
  final int? osMajorVersion;
  final int androidSdkInt;
}

typedef AndroidDeviceCompatibilityInvoker =
    Future<Object?> Function(String method, Object? arguments);

/// Host-owned, read-only Android device compatibility capability.
///
/// It has no permission, network, persistence, or account dependency. The
/// profile is loaded lazily and cached for the lifetime of this capability.
class AndroidDeviceCompatibilityCapability {
  AndroidDeviceCompatibilityCapability({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('mychu/android_device_compatibility');

  static final shared = AndroidDeviceCompatibilityCapability();

  @visibleForTesting
  static AndroidDeviceCompatibilityInvoker? debugInvoke;

  final MethodChannel _channel;
  Future<AndroidDeviceProfile?>? _profileFuture;
  final Map<AndroidDeviceCompatibilityFeature, Future<bool>> _featureFutures =
      <AndroidDeviceCompatibilityFeature, Future<bool>>{};

  bool get isAndroid {
    if (debugInvoke != null) return true;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<AndroidDeviceProfile?> getProfile() {
    if (!isAndroid) return Future<AndroidDeviceProfile?>.value(null);
    return _profileFuture ??= _loadProfile();
  }

  Future<bool> supports(AndroidDeviceCompatibilityFeature feature) async {
    if (!isAndroid) return false;
    return _featureFutures[feature] ??= _loadFeatureSupport(feature);
  }

  Future<bool> _loadFeatureSupport(
    AndroidDeviceCompatibilityFeature feature,
  ) async {
    try {
      final raw = await _invoke('supportsFeature', {'feature': feature.id});
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  Future<AndroidDeviceProfile?> _loadProfile() async {
    try {
      return _parseProfile(await _invoke('getProfile', null));
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _invoke(String method, Object? arguments) {
    final override = debugInvoke;
    if (override != null) return override(method, arguments);
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  @visibleForTesting
  void reset() {
    _profileFuture = null;
    _featureFutures.clear();
  }
}

AndroidDeviceProfile? _parseProfile(Object? raw) {
  if (raw is! Map) return null;
  return AndroidDeviceProfile(
    brandName: _safeDeviceText(raw['brandName']),
    marketName: _safeDeviceText(raw['marketName']),
    osName: _safeDeviceText(raw['osName']),
    osVersionName: _safeDeviceText(raw['osVersionName']),
    osMajorVersion: _readNonNegativeInt(raw['osMajorVersion']),
    androidSdkInt: _readNonNegativeInt(raw['androidSdkInt']) ?? 0,
  );
}

String _safeDeviceText(Object? raw) {
  if (raw is! String) return AndroidDeviceProfile.unknown;
  final normalized = raw.trim().replaceAll(
    RegExp(r'[\u0000-\u001f\u007f\r\n\t]'),
    ' ',
  );
  if (normalized.isEmpty ||
      RegExp(
        r'https?://|(?:cookie|token|ticket|password|authorization)\s*[:=]',
        caseSensitive: false,
      ).hasMatch(normalized)) {
    return AndroidDeviceProfile.unknown;
  }
  if (normalized.length <= 128) return normalized;
  return '${normalized.substring(0, 127)}…';
}

int? _readNonNegativeInt(Object? raw) {
  if (raw is int) return raw >= 0 ? raw : null;
  if (raw is num && raw.isFinite) {
    final value = raw.toInt();
    if (raw == value && value >= 0) return value;
  }
  return null;
}

final androidDeviceCompatibilityCapability =
    AndroidDeviceCompatibilityCapability.shared;
