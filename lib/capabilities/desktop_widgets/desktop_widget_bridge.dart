import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/logger_service.dart';
import 'desktop_widget_models.dart';
import 'desktop_widget_projection.dart';

class DesktopWidgetBridge {
  static const _channel = MethodChannel('mychu/desktop_widgets');

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform.name == 'ohos');

  static Future<void> publish(DesktopWidgetSnapshotV1 snapshot) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('publishSnapshot', {
      'snapshot': snapshot.encode(),
    });
  }
}

/// Keeps native home-screen widgets in step with cached host data.
///
/// This never performs a campus request. Native widgets render the resulting
/// V1 value without starting Flutter in the widget process.
class DesktopWidgetSyncService {
  static bool _refreshing = false;
  static bool _refreshAgain = false;
  static int _generation = 0;
  static int _clearingSchedule = 0;

  @visibleForTesting
  static Future<DesktopWidgetSnapshotV1> Function()? debugBuildSnapshot;

  @visibleForTesting
  static void debugReset() {
    _refreshing = false;
    _refreshAgain = false;
    _generation = 0;
    _clearingSchedule = 0;
    debugBuildSnapshot = null;
  }

  static Future<void> refresh() async {
    if (!DesktopWidgetBridge.isSupported) return;
    if (_clearingSchedule > 0) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final generation = _generation;
        try {
          final snapshot =
              await (debugBuildSnapshot?.call() ??
                  DesktopWidgetProjectionService.forHost().build());
          if (generation != _generation) {
            continue;
          }
          await DesktopWidgetBridge.publish(snapshot);
        } on Object catch (error) {
          AppLogger.warn('桌面课表小组件同步失败 (${error.runtimeType})');
        }
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  /// Replaces visible course data on logout.
  static Future<void> clearSchedule() async {
    if (!DesktopWidgetBridge.isSupported) return;
    _generation++;
    _refreshAgain = false;
    _clearingSchedule++;
    try {
      await DesktopWidgetBridge.publish(
        DesktopWidgetSnapshotV1(
          generatedAt: DateTime.now().toUtc(),
          schedule: DesktopWidgetScheduleV1(
            status: DesktopWidgetScheduleStatus.signedOut,
          ),
        ),
      );
    } on Object catch (error) {
      AppLogger.warn('退出登录时清除桌面课表小组件失败 (${error.runtimeType})');
    } finally {
      _clearingSchedule--;
    }
  }
}
