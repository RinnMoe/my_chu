import "package:flutter/foundation.dart" show visibleForTesting;
import "package:flutter/services.dart";
import "package:geolocator/geolocator.dart";

import "../campus_places/campus_places.dart";
import "../../services/host_permission_service.dart";
import "../../services/host_platform.dart";

/// 用户定位获取结果状态。
enum CampusUserLocationStatus { located, denied, serviceUnavailable }

/// 一次用户定位获取结果（WGS84 坐标）。
class CampusUserLocationResult {
  final CampusUserLocationStatus status;
  final CampusCoordinate? coordinate;

  const CampusUserLocationResult(this.status, [this.coordinate]);
}

/// SDK 无关的用户定位能力：权限请求 + 获取 WGS84 当前位置。
///
/// 仅由地图页在用户主动点击定位时调用，不启动后台定位。
class CampusUserLocationService {
  static const MethodChannel _harmonyChannel = MethodChannel(
    "moe.rinn.mychu/harmony_location",
  );

  final Future<LocationPermission> Function() checkPermission;
  final Future<LocationPermission> Function() requestPermission;
  final Future<Position> Function() getPosition;
  final HostPermissionService _permissionService;
  final HostPlatform _hostPlatform;
  final Future<Object?> Function(String method)? _harmonyInvoker;

  CampusUserLocationService({
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? getPosition,
    HostPermissionService? permissionService,
    @visibleForTesting HostPlatform? hostPlatformOverride,
    @visibleForTesting Future<Object?> Function(String method)? harmonyInvoker,
  }) : checkPermission = checkPermission ?? Geolocator.checkPermission,
       requestPermission = requestPermission ?? Geolocator.requestPermission,
       getPosition = getPosition ?? _defaultGetPosition,
       _permissionService = permissionService ?? hostPermissionService,
       _hostPlatform = hostPlatformOverride ?? HostPlatform.current,
       _harmonyInvoker = harmonyInvoker;

  static Future<Position> _defaultGetPosition() =>
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

  Future<CampusUserLocationResult> acquire({
    HostPermissionPurposePresenter? presentPurpose,
  }) async {
    try {
      if (_hostPlatform == HostPlatform.harmony) {
        return await _acquireHarmony(presentPurpose: presentPurpose);
      }
      var permission = await checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return const CampusUserLocationResult(CampusUserLocationStatus.denied);
      }
      final position = await getPosition();
      final coordinate = CampusCoordinate(
        longitude: position.longitude,
        latitude: position.latitude,
      );
      if (!coordinate.isValidWgs84 || coordinate.isOrigin) {
        return const CampusUserLocationResult(
          CampusUserLocationStatus.serviceUnavailable,
        );
      }
      return CampusUserLocationResult(
        CampusUserLocationStatus.located,
        coordinate,
      );
    } catch (_) {
      return const CampusUserLocationResult(
        CampusUserLocationStatus.serviceUnavailable,
      );
    }
  }

  Future<CampusUserLocationResult> _acquireHarmony({
    HostPermissionPurposePresenter? presentPurpose,
  }) async {
    final permission = await _permissionService
        .requestHarmonyLocationPermission(presentPurpose: presentPurpose);
    if (!permission.granted) {
      return const CampusUserLocationResult(CampusUserLocationStatus.denied);
    }
    final raw =
        await (_harmonyInvoker?.call("getCurrentLocation") ??
            _harmonyChannel.invokeMethod<Object?>("getCurrentLocation"));
    if (raw is! Map) {
      return const CampusUserLocationResult(
        CampusUserLocationStatus.serviceUnavailable,
      );
    }
    final latitude = raw["latitude"];
    final longitude = raw["longitude"];
    if (latitude is! num || longitude is! num) {
      return const CampusUserLocationResult(
        CampusUserLocationStatus.serviceUnavailable,
      );
    }
    final coordinate = CampusCoordinate(
      longitude: longitude.toDouble(),
      latitude: latitude.toDouble(),
    );
    if (!coordinate.isValidWgs84 || coordinate.isOrigin) {
      return const CampusUserLocationResult(
        CampusUserLocationStatus.serviceUnavailable,
      );
    }
    return CampusUserLocationResult(
      CampusUserLocationStatus.located,
      coordinate,
    );
  }
}
