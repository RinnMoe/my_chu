/// 图层可见性偏好的持久化。
///
/// 只保存“用户长期设置”的开关状态；业务导航触发的临时显示、定位与选中
/// 不进入这里，避免一次 App → 地图跳转覆盖用户偏好。
library;

import "dart:convert";

import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

class MapLayerPreferenceStore {
  MapLayerPreferenceStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  /// 版本化键名：跨版本稳定，格式变化时换版本号并提供迁移。
  static const String storageKey = "map.layers.visibility.v1";

  final Future<SharedPreferences> Function() _preferences;

  /// 读取已保存的可见性；损坏的数据按“没有偏好”处理，不让地图打不开。
  Future<Map<String, bool>> readVisibility() async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return const <String, bool>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, bool>{};
      final result = <String, bool>{};
      decoded.forEach((key, value) {
        if (key is String && value is bool) result[key] = value;
      });
      return result;
    } catch (_) {
      return const <String, bool>{};
    }
  }

  /// 写入单个图层的可见性；返回是否确认持久化。
  Future<bool> writeVisibility(String layerId, bool visible) async {
    try {
      final prefs = await _preferences();
      final current = Map<String, bool>.of(await readVisibility());
      if (current[layerId] == visible) return true;
      current[layerId] = visible;
      return await prefs.setString(storageKey, jsonEncode(current));
    } catch (error) {
      debugPrint("map layer preference write failed: ${error.runtimeType}");
      return false;
    }
  }

  /// 清除全部图层偏好（仅用于测试与重置）。
  @visibleForTesting
  Future<void> clear() async {
    try {
      final prefs = await _preferences();
      await prefs.remove(storageKey);
    } catch (_) {
      // 偏好清除失败不影响地图可用性。
    }
  }
}
