import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capabilities/campus_places/campus_places.dart';
import 'teaching_schedule_service.dart';

/// 设备全局校区偏好，与账号、会话和登出独立。
class CampusSettingsService {
  static const defaultCampusId = 'weishui';

  /// Bumped whenever a stored campus preference changes so pages can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Future<SharedPreferences> Function() _prefs;
  final MapReleaseCoordinator _releaseCoordinator;
  final Future<bool> Function(String key, String value)? _setStringOverride;

  CampusRegistry? _registry;
  String? _registryReleaseId;

  CampusSettingsService({
    Future<SharedPreferences> Function()? prefs,
    MapReleaseCoordinator? releaseCoordinator,
    Future<bool> Function(String key, String value)? setString,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _releaseCoordinator = releaseCoordinator ?? MapReleaseCoordinator.shared,
       _setStringOverride = setString;

  static String _key() => 'preferences.v1.campus';

  /// 读取设备校区；缺失、未知或未启用时回退渭水校区。
  Future<String> read() async {
    return await readStored() ?? defaultCampusId;
  }

  /// Reads an explicitly persisted, currently enabled campus without applying
  /// the user-facing default. This lets selection UIs distinguish a real
  /// preference from the implicit 渭水 fallback.
  Future<String?> readStored() async {
    final stored = (await _prefs()).getString(_key());
    if (stored == null || stored.isEmpty) return null;
    final campus = (await _registryData()).byId(stored);
    if (campus == null || !campus.enabled) return null;
    return stored;
  }

  /// 写入设备校区并通知监听方。
  ///
  /// `SharedPreferences` can report a failed write without throwing. Only a
  /// confirmed write advances [revision], so dependent pages never refresh
  /// from a preference that was not persisted.
  Future<bool> set(String campusId) async {
    final campus = (await _registryData()).byId(campusId);
    if (campus == null || !campus.enabled) {
      throw ArgumentError.value(campusId, 'campusId', 'unknown campus');
    }
    try {
      final saved =
          _setStringOverride == null
              ? await (await _prefs()).setString(_key(), campusId)
              : await _setStringOverride(_key(), campusId);
      if (!saved) return false;
    } catch (_) {
      return false;
    }
    revision.value++;
    return true;
  }

  /// 获取已启用校区信息；内置应用可通过此方法获取展示名、坐标等资料。
  Future<CampusEntry?> campusFor(String campusId) async {
    final campus = (await _registryData()).byId(campusId);
    return campus?.enabled == true ? campus : null;
  }

  /// 全部启用校区，按注册表排序。
  Future<List<CampusEntry>> enabledCampuses() async {
    return (await _registryData()).enabledCampuses;
  }

  /// 设备选中的校区条目。
  Future<CampusEntry?> selectedCampus() async {
    final campusId = await read();
    return campusFor(campusId);
  }

  /// 设备校区对应的节次时间表模式。
  Future<TeachingScheduleMode> scheduleModeFor() async {
    return scheduleModeForCampusId(await read());
  }

  Future<CampusRegistry> _registryData() async {
    final cached = _registry;
    final snapshot = await _releaseCoordinator.currentSnapshot();
    if (cached != null && _registryReleaseId == snapshot.manifest.releaseId) {
      return cached;
    }
    _registry = snapshot.registry;
    _registryReleaseId = snapshot.manifest.releaseId;
    // Keep the registry fast on cold start, then let the shared coordinator
    // stage a newer release for the next map entry.
    unawaited(_releaseCoordinator.refresh().catchError((_) => false));
    return snapshot.registry;
  }
}

/// 渭水校区单独一套时间表，其余三个校区共用南校区时间表。
TeachingScheduleMode scheduleModeForCampusId(String campusId) {
  return campusId == CampusSettingsService.defaultCampusId
      ? TeachingScheduleMode.weishui
      : TeachingScheduleMode.southCampus;
}

/// 全局校区偏好服务实例。
final campusSettingsService = CampusSettingsService(
  releaseCoordinator: MapReleaseCoordinator.shared,
);
