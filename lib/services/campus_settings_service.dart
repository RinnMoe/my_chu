import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capabilities/campus_places/campus_places.dart';
import 'teaching_schedule_service.dart';

/// 账号级校区偏好，复用现有 `SharedPreferences` + `accountKey` + `revision`
/// 模式，与 `AcademicScheduleDisplayPreferences`/`HomeLayoutService` 一致。
///
/// 键格式为 `campus.settings.v1.<accountKey>`，退出登录不清除；账号替换后
/// 旧键成为无害孤儿键。天气、课表时间、地图初始校区及未来内置应用也从这里读取校区设置。
class CampusSettingsService {
  static const defaultCampusId = 'weishui';
  static const _keyPrefix = 'campus.settings.v1.';

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

  static String _key(String accountKey) => '$_keyPrefix$accountKey';

  /// 读取当前账号校区；缺失、未知或未启用时回退渭水校区。
  Future<String> read(String accountKey) async {
    return await readStored(accountKey) ?? defaultCampusId;
  }

  /// Reads an explicitly persisted, currently enabled campus without applying
  /// the user-facing default. This lets selection UIs distinguish a real
  /// preference from the implicit 渭水 fallback.
  Future<String?> readStored(String accountKey) async {
    final stored = (await _prefs()).getString(_key(accountKey));
    if (stored == null || stored.isEmpty) return null;
    final campus = (await _registryData()).byId(stored);
    if (campus == null || !campus.enabled) return null;
    return stored;
  }

  /// 写入当前账号校区并通知监听方。
  ///
  /// `SharedPreferences` can report a failed write without throwing. Only a
  /// confirmed write advances [revision], so dependent pages never refresh
  /// from a preference that was not persisted.
  Future<bool> set(String accountKey, String campusId) async {
    final campus = (await _registryData()).byId(campusId);
    if (campus == null || !campus.enabled) {
      throw ArgumentError.value(campusId, 'campusId', 'unknown campus');
    }
    try {
      final saved =
          _setStringOverride == null
              ? await (await _prefs()).setString(_key(accountKey), campusId)
              : await _setStringOverride(_key(accountKey), campusId);
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

  /// 当前账号选中的校区条目。
  Future<CampusEntry?> selectedCampus(String accountKey) async {
    final campusId = await read(accountKey);
    return campusFor(campusId);
  }

  /// 当前账号校区对应的节次时间表模式。
  Future<TeachingScheduleMode> scheduleModeFor(String accountKey) async {
    return scheduleModeForCampusId(await read(accountKey));
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
