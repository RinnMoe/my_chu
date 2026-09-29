import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppLaunchService {
  static const MethodChannel _channel = MethodChannel('mychu/app_launch');
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static String? _pendingTargetId;
  static String? _pendingWidgetLaunchRequest;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform.name != 'ohos')) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openWidgetTarget') {
        _receiveWidgetRequest(call.arguments);
      } else if (call.method == 'openTarget' || call.method == 'launch') {
        _receive(call.arguments);
      }
    });
    try {
      _receive(await _channel.invokeMethod<Object?>('consume'));
    } catch (_) {
      // The host launch channel is available only in the regular app engine.
    }
  }

  static String? takePendingTarget() {
    final target = _pendingTargetId;
    _pendingTargetId = null;
    return target;
  }

  static String? takePendingWidgetLaunchRequest() {
    final request = _pendingWidgetLaunchRequest;
    _pendingWidgetLaunchRequest = null;
    return request;
  }

  static void _receive(Object? value) {
    if (value is Map && value['source'] == 'desktopWidget') {
      _receiveWidgetRequest(value['request']);
      return;
    }
    final target = switch (value) {
      final String raw => raw.trim(),
      final Map raw when raw['targetAppId'] is String =>
        (raw['targetAppId'] as String).trim(),
      _ => '',
    };
    if (target.isEmpty) return;
    _pendingTargetId = target;
    revision.value++;
  }

  static void _receiveWidgetRequest(Object? value) {
    final request = value is String ? value.trim() : '';
    if (request.isEmpty) return;
    _pendingWidgetLaunchRequest = request;
    revision.value++;
  }
}
