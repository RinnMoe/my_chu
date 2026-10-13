import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 常用应用排序模式。
enum QuickAppsSortMode { recent, manual }

/// 首页常用应用的设备全局唯一状态源。
///
/// [initialized] 只用于区分“从未生成过配置”与“用户已清空选择”：
/// 前者由 `AppService` 按注册表默认值生成一次，后者不再补默认值。
class QuickAppsConfig {
  final bool enabled;
  final List<String> selectedAppIds;
  final List<String> manualOrder;
  final QuickAppsSortMode sortMode;
  final bool initialized;

  const QuickAppsConfig({
    this.enabled = true,
    this.selectedAppIds = const [],
    this.manualOrder = const [],
    this.sortMode = QuickAppsSortMode.recent,
    this.initialized = false,
  });

  QuickAppsConfig copyWith({
    bool? enabled,
    List<String>? selectedAppIds,
    List<String>? manualOrder,
    QuickAppsSortMode? sortMode,
    bool? initialized,
  }) {
    return QuickAppsConfig(
      enabled: enabled ?? this.enabled,
      selectedAppIds: selectedAppIds ?? this.selectedAppIds,
      manualOrder: manualOrder ?? this.manualOrder,
      sortMode: sortMode ?? this.sortMode,
      initialized: initialized ?? this.initialized,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'selectedAppIds': selectedAppIds,
    'manualOrder': manualOrder,
    'sortMode': sortMode.name,
    'initialized': initialized,
  };

  factory QuickAppsConfig.fromJson(Map<String, dynamic> json) {
    final rawSelected = json['selectedAppIds'];
    final rawOrder = json['manualOrder'];
    return QuickAppsConfig(
      enabled: json['enabled'] as bool? ?? true,
      selectedAppIds:
          rawSelected is List
              ? rawSelected.whereType<String>().toList()
              : const [],
      manualOrder:
          rawOrder is List ? rawOrder.whereType<String>().toList() : const [],
      sortMode:
          QuickAppsSortMode.values.asNameMap()[json['sortMode']] ??
          QuickAppsSortMode.recent,
      initialized: json['initialized'] == true,
    );
  }
}

/// 常用应用配置的设备全局持久化状态。
class HomeLayoutService {
  /// 显式 Quick Apps 配置变化时递增，供依赖该配置的页面重载。
  /// 首次读取时自动生成 defaultPinned 初始值不会递增。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _quickAppsKey() => 'preferences.v1.quick_apps';

  static Future<QuickAppsConfig> readQuickApps() async {
    final prefs = await SharedPreferences.getInstance();
    return _readQuickApps(prefs);
  }

  static QuickAppsConfig _readQuickApps(SharedPreferences prefs) {
    final raw = prefs.getString(_quickAppsKey());
    if (raw == null || raw.isEmpty) return const QuickAppsConfig();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const QuickAppsConfig();
    return QuickAppsConfig.fromJson(decoded);
  }

  /// Persists generated defaults only if preferences have not been initialized.
  /// This is a first-read materialization, not an explicit user configuration
  /// change, so it does not notify [revision].
  static Future<QuickAppsConfig> initializeQuickAppsIfNeeded(
    QuickAppsConfig defaults,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final current = _readQuickApps(prefs);
    if (current.initialized) return current;

    final initialized = defaults.copyWith(initialized: true);
    await prefs.setString(_quickAppsKey(), jsonEncode(initialized.toJson()));
    return initialized;
  }

  static Future<void> saveQuickApps(QuickAppsConfig config) async {
    await _writeQuickApps(config.copyWith(initialized: true));
  }

  static Future<void> setQuickAppsEnabled(bool enabled) async {
    final config = await readQuickApps();
    await saveQuickApps(config.copyWith(enabled: enabled));
  }

  static Future<void> addQuickApp(String appId) async {
    final config = await readQuickApps();
    if (config.selectedAppIds.contains(appId)) return;
    await saveQuickApps(
      config.copyWith(
        selectedAppIds: [...config.selectedAppIds, appId],
        manualOrder: [...config.manualOrder, appId],
      ),
    );
  }

  static Future<void> removeQuickApp(String appId) async {
    final config = await readQuickApps();
    await saveQuickApps(
      config.copyWith(
        selectedAppIds: config.selectedAppIds
            .where((id) => id != appId)
            .toList(growable: false),
        manualOrder: config.manualOrder
            .where((id) => id != appId)
            .toList(growable: false),
      ),
    );
  }

  static Future<void> setQuickAppsOrder(List<String> order) async {
    final config = await readQuickApps();
    await saveQuickApps(
      config.copyWith(manualOrder: order, sortMode: QuickAppsSortMode.manual),
    );
  }

  static Future<void> setQuickAppsSortMode(QuickAppsSortMode sortMode) async {
    final config = await readQuickApps();
    await saveQuickApps(config.copyWith(sortMode: sortMode));
  }

  static Future<void> _writeQuickApps(QuickAppsConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quickAppsKey(), jsonEncode(config.toJson()));
    revision.value++;
  }
}
