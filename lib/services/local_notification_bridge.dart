import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'host_permission_service.dart';
import 'platform_compatibility_service.dart';

/// Host-side bridge for system notifications.
///
/// Only the host may touch this bridge. Features publish application-internal
/// events through [InAppNotificationService]; the host maps a published,
/// deduplicated notification to a system banner here. App code never calls
/// this directly.
class LocalNotificationBridge {
  static const MethodChannel _harmonyChannel = MethodChannel(
    'moe.rinn.mychu/harmony_notifications',
  );

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Test hook: replaces the plugin's display call; set
  /// [debugNotificationPermission] to false to simulate denial.
  @visibleForTesting
  static void Function({required int id, required String title, String? body})?
  debugShowOverride;

  /// Test hook: when true, all platform calls (initialize/request/show) are
  /// skipped so widget tests never hit missing plugin channels.
  @visibleForTesting
  static bool debugSkipSystemCalls = false;

  /// Test hook: when set, [show] uses this value for the notification
  /// permission check instead of touching the platform channel.
  @visibleForTesting
  static bool? debugNotificationPermission;

  /// Test hook for the user-initiated Apple notification permission flow.
  @visibleForTesting
  static Future<bool> Function()? debugPermissionRequestOverride;

  /// Test hook for the HarmonyOS host notification channel.
  @visibleForTesting
  static Future<Object?> Function(
    String method,
    Map<String, Object?>? arguments,
  )?
  debugHarmonyInvoke;

  static Future<Object?> _invokeHarmony(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final override = debugHarmonyInvoke;
    if (override != null) return override(method, arguments);
    return _harmonyChannel.invokeMethod<Object?>(method, arguments);
  }

  static Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (PlatformCompatibilityService.isHarmony) return;
    try {
      if (PlatformCompatibilityService.isApple) {
        const settings = DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
        await _plugin.initialize(
          settings: const InitializationSettings(iOS: settings),
        );
      } else {
        const settings = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _plugin.initialize(
          settings: const InitializationSettings(android: settings),
        );
      }
    } catch (_) {
      // Initialization is best-effort; in-app notifications still work.
    }
  }

  /// Requests Apple notification permission only after an explicit user
  /// action, such as enabling a system-banner subscription in Settings.
  /// Background publication never opens a system permission prompt.
  static Future<bool> requestPermission() async {
    final override = debugPermissionRequestOverride;
    if (override != null) return override();
    if (debugSkipSystemCalls) return false;
    if (PlatformCompatibilityService.isHarmony) {
      try {
        return await _invokeHarmony('requestPermission') == true;
      } catch (_) {
        return false;
      }
    }
    if (!PlatformCompatibilityService.isApple) {
      return false;
    }
    try {
      await _initialize();
      final plugin =
          _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
      return await plugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Shows a system banner when notification permission is granted.
  ///
  /// The host pre-requests Android 13+ `POST_NOTIFICATIONS` after the first
  /// home entry. Publishing only checks the current permission state so a
  /// background notification never opens a system permission dialog.
  static Future<void> show({
    required int id,
    required String title,
    String? body,
  }) async {
    final override = debugShowOverride;
    if (override != null) {
      if (debugNotificationPermission == false) return;
      override(id: id, title: title, body: body);
      return;
    }
    if (debugSkipSystemCalls) return;
    if (PlatformCompatibilityService.isHarmony) {
      try {
        if (!await _notificationPermissionGranted()) return;
        await _invokeHarmony('show', {'id': id, 'title': title, 'body': body});
      } catch (_) {
        // System banners are best-effort and never break the in-app path.
      }
      return;
    }
    if (!PlatformCompatibilityService.isAndroid &&
        !PlatformCompatibilityService.isApple) {
      return;
    }
    try {
      await _initialize();
      if (!await _notificationPermissionGranted()) {
        return;
      }
      const android = AndroidNotificationDetails(
        'in_app_changes',
        '应用内提醒',
        channelDescription: '成绩更新、教务数据变化等应用内提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const apple = DarwinNotificationDetails(
        threadIdentifier: 'in_app_changes',
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: android,
          iOS: apple,
        ),
      );
    } catch (_) {
      // System banners are best-effort and never break the in-app path.
    }
  }

  static Future<bool> _notificationPermissionGranted() async {
    final override = debugNotificationPermission;
    if (override != null) return override;
    if (PlatformCompatibilityService.isHarmony) {
      try {
        return await _invokeHarmony('isNotificationEnabled') == true;
      } catch (_) {
        return false;
      }
    }
    if (PlatformCompatibilityService.isAndroid) {
      return hostPermissionService.isNotificationPermissionGranted();
    }
    if (PlatformCompatibilityService.isApple) {
      try {
        final permissions =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions();
        return permissions?.isEnabled ?? false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }
}
