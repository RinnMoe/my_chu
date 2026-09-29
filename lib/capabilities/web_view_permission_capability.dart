import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../services/service_endpoints.dart';

typedef WebViewPermissionRequester =
    Future<ph.PermissionStatus> Function(ph.Permission permission);

/// Host-side permission gate for built-in campus WebViews.
///
/// WebView permission requests are checked against the request origin before
/// touching an Android runtime permission.
class WebViewPermissionCapability {
  final WebViewPermissionRequester _requestPermission;

  WebViewPermissionCapability({WebViewPermissionRequester? requestPermission})
    : _requestPermission = requestPermission ?? _requestPermissionByHandler;

  static Future<ph.PermissionStatus> _requestPermissionByHandler(
    ph.Permission permission,
  ) => permission.request();

  /// `chd.edu.cn` and all of its subdomains are allowlisted.
  ///
  /// Both HTTP and HTTPS are accepted by the host policy because existing
  /// campus services include HTTP endpoints. The WebView engine may still
  /// apply its own secure-context rules to individual browser APIs.
  static bool isAllowedOrigin(Object? origin) {
    final uri = Uri.tryParse(origin?.toString() ?? '');
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    return CampusServiceEndpoints.isChdHost(uri.host);
  }

  Future<PermissionResponse> handlePermissionRequest(
    PermissionRequest request,
  ) async {
    final resources = request.resources;
    if (!await requestMediaPermissions(request.origin, resources)) {
      return _deny(resources);
    }

    return _grant(resources);
  }

  /// Requests the native permissions represented by a WebView media request.
  ///
  /// This method is separate from the plugin callback so the origin and
  /// permission decisions can be tested without constructing a platform
  /// WebView controller.
  Future<bool> requestMediaPermissions(
    Object? origin,
    List<PermissionResourceType> resources,
  ) async {
    if (!isAllowedOrigin(origin) ||
        !_containsOnlySupportedResources(resources)) {
      return false;
    }

    final requiredPermissions = <ph.Permission>[
      if (resources.contains(PermissionResourceType.CAMERA))
        ph.Permission.camera,
      if (resources.contains(PermissionResourceType.MICROPHONE))
        ph.Permission.microphone,
    ];
    if (requiredPermissions.isEmpty) return false;

    for (final permission in requiredPermissions) {
      final status = await _requestPermission(permission);
      if (!status.isGranted) return false;
    }

    return true;
  }

  Future<GeolocationPermissionShowPromptResponse>
  handleGeolocationPermissionsShowPrompt(String origin) async {
    final granted = await requestGeolocationPermission(origin);
    return GeolocationPermissionShowPromptResponse(
      origin: origin,
      allow: granted,
      // Re-check the origin on every prompt instead of retaining a WebView
      // grant across navigations.
      retain: false,
    );
  }

  /// Requests the native foreground location permission for a WebView origin.
  Future<bool> requestGeolocationPermission(String origin) async {
    if (!isAllowedOrigin(origin)) return false;
    return (await _requestPermission(
      ph.Permission.locationWhenInUse,
    )).isGranted;
  }

  static bool _containsOnlySupportedResources(
    List<PermissionResourceType> resources,
  ) =>
      resources.isNotEmpty &&
      resources.every(
        (resource) =>
            resource == PermissionResourceType.CAMERA ||
            resource == PermissionResourceType.MICROPHONE,
      );

  static PermissionResponse _grant(List<PermissionResourceType> resources) =>
      PermissionResponse(
        resources: resources,
        action: PermissionResponseAction.GRANT,
      );

  static PermissionResponse _deny(List<PermissionResourceType> resources) =>
      PermissionResponse(
        resources: resources,
        action: PermissionResponseAction.DENY,
      );
}
