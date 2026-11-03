import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// 首次打开地图时才注册 Mapbox 原生插件。
///
/// Mapbox SDK 在插件 attach 时初始化，冷启动阶段并不需要它；延后注册可以让
/// 每次冷启动少约 300 ms 的原生初始化。调用是幂等的，失败后允许下次重试。
class MapboxLazyLoader {
  MapboxLazyLoader._();

  static const MethodChannel _channel = MethodChannel("mychu/mapbox_lazy");
  static Future<void>? _pending;

  static Future<void> ensureLoaded() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<void>.value();
    }
    return _pending ??= _ensure();
  }

  static Future<void> _ensure() async {
    try {
      await _channel.invokeMethod<bool>("ensure");
    } on MissingPluginException {
      // 单元测试或未注册该通道的宿主：保持与未懒加载时一致的空实现。
    } catch (error) {
      // 失败后清掉单飞，允许用户下次打开地图时重试。
      _pending = null;
      rethrow;
    }
  }
}
