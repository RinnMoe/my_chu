import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_compatibility_service.dart';

/// The only Dart-to-native boundary used by the vivo SuperX demo.
class VivoSuperXDemoPlatform {
  static const MethodChannel _channel = MethodChannel('mychu/vivo_superx_demo');

  @visibleForTesting
  static Future<Object?> Function(String method, Object? arguments)?
  debugInvoke;

  static Future<Object?> _invoke(String method, [Object? arguments]) {
    final override = debugInvoke;
    if (override != null) return override(method, arguments);
    if (!PlatformCompatibilityService.isAndroid) {
      return Future<Object?>.value(null);
    }
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  static Future<void> post(VivoSuperXDemoPayload payload) =>
      _invoke('post', {'payload': jsonEncode(payload.toJson())}).then((_) {});

  static Future<void> cancel() => _invoke('cancel').then((_) {});

  static Future<VivoSuperXDemoStatus> status() async {
    final raw = await _invoke('status');
    if (raw is Map) {
      return VivoSuperXDemoStatus.fromJson(Map<String, Object?>.from(raw));
    }
    return const VivoSuperXDemoStatus();
  }
}

/// A bounded local payload for creating or updating a vivo SuperX
/// notification. The native side owns the `notification.superx.*` mapping.
class VivoSuperXDemoPayload {
  final int operation;
  final String title;
  final String content;
  final String shortText;
  final int progressPercent;
  final int changedRecord;
  final int keepDuration;

  const VivoSuperXDemoPayload({
    required this.operation,
    required this.title,
    required this.content,
    required this.shortText,
    required this.progressPercent,
    required this.changedRecord,
    this.keepDuration = 0,
  });

  Map<String, Object> toJson() => {
    'operation': operation,
    'title': title,
    'content': content,
    'shortText': shortText,
    'progressPercent': progressPercent,
    'changedRecord': changedRecord,
    'keepDuration': keepDuration,
  };
}

/// Best-effort device/scene status returned by the native side.
class VivoSuperXDemoStatus {
  final bool supportCustomFun;
  final bool sceneEnabled;

  const VivoSuperXDemoStatus({
    this.supportCustomFun = false,
    this.sceneEnabled = false,
  });

  factory VivoSuperXDemoStatus.fromJson(Map<String, Object?> json) {
    return VivoSuperXDemoStatus(
      supportCustomFun: json['supportCustomFun'] == true,
      sceneEnabled: json['sceneEnabled'] == true,
    );
  }
}

/// Host-side facade used by the demo page.
class VivoSuperXDemoService {
  static bool get isSupported =>
      PlatformCompatibilityService.isAndroid ||
      VivoSuperXDemoPlatform.debugInvoke != null;

  static Future<void> post(VivoSuperXDemoPayload payload) =>
      VivoSuperXDemoPlatform.post(payload);

  static Future<void> cancel() => VivoSuperXDemoPlatform.cancel();

  static Future<VivoSuperXDemoStatus> status() =>
      VivoSuperXDemoPlatform.status();
}
