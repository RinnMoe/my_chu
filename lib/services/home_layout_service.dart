import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 常用应用排序模式。
enum QuickAppsSortMode { recent, manual }

/// 首页常用应用的账号作用域唯一状态源。
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

/// 常用应用配置的账号作用域持久化状态。
class HomeLayoutService {
  static const _quickAppsKeyPrefix = 'home.v2.quick_apps.';

  /// 显式 Quick Apps 配置变化时递增，供依赖该配置的页面重载。
  /// 首次读取时自动生成 defaultPinned 初始值不会递增。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _quickAppsKey(String accountKey) =>
      '$_quickAppsKeyPrefix$accountKey';

  static Future<QuickAppsConfig> readQuickApps(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return _readQuickApps(prefs, accountKey);
  }

  static QuickAppsConfig _readQuickApps(
    SharedPreferences prefs,
    String accountKey,
  ) {
    final raw = prefs.getString(_quickAppsKey(accountKey));
    if (raw == null || raw.isEmpty) return const QuickAppsConfig();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const QuickAppsConfig();
    return QuickAppsConfig.fromJson(decoded);
  }

  /// Persists generated defaults only if the account has not been initialized.
  /// This is a first-read materialization, not an explicit user configuration
  /// change, so it does not notify [revision].
  static Future<QuickAppsConfig> initializeQuickAppsIfNeeded(
    String accountKey,
    QuickAppsConfig defaults,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final current = _readQuickApps(prefs, accountKey);
    if (current.initialized) return current;

    final initialized = defaults.copyWith(initialized: true);
    await prefs.setString(
      _quickAppsKey(accountKey),
      jsonEncode(initialized.toJson()),
    );
    return initialized;
  }

  static Future<void> saveQuickApps(
    String accountKey,
    QuickAppsConfig config,
  ) async {
    await _writeQuickApps(accountKey, config.copyWith(initialized: true));
  }

  static Future<void> setQuickAppsEnabled(
    String accountKey,
    bool enabled,
  ) async {
    final config = await readQuickApps(accountKey);
    await saveQuickApps(accountKey, config.copyWith(enabled: enabled));
  }

  static Future<void> addQuickApp(String accountKey, String appId) async {
    final config = await readQuickApps(accountKey);
    if (config.selectedAppIds.contains(appId)) return;
    await saveQuickApps(
      accountKey,
      config.copyWith(
        selectedAppIds: [...config.selectedAppIds, appId],
        manualOrder: [...config.manualOrder, appId],
      ),
    );
  }

  static Future<void> removeQuickApp(String accountKey, String appId) async {
    final config = await readQuickApps(accountKey);
    await saveQuickApps(
      accountKey,
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

  static Future<void> setQuickAppsOrder(
    String accountKey,
    List<String> order,
  ) async {
    final config = await readQuickApps(accountKey);
    await saveQuickApps(
      accountKey,
      config.copyWith(manualOrder: order, sortMode: QuickAppsSortMode.manual),
    );
  }

  static Future<void> setQuickAppsSortMode(
    String accountKey,
    QuickAppsSortMode sortMode,
  ) async {
    final config = await readQuickApps(accountKey);
    await saveQuickApps(accountKey, config.copyWith(sortMode: sortMode));
  }

  static Future<void> _writeQuickApps(
    String accountKey,
    QuickAppsConfig config,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _quickAppsKey(accountKey),
      jsonEncode(config.toJson()),
    );
    revision.value++;
  }
}
