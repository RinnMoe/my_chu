import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/home_layout_service.dart';
import '../services/demo_data_service.dart';
import '../services/development_mode_service.dart';
import 'app.dart';
import 'app_registry.dart';

final appCatalogNotifier = ValueNotifier<int>(0);

/// A snapshot of the non-core managed plugin catalog plus per-plugin runtime
/// state, loaded once for pages that render the catalog.
class AppCatalogSnapshot {
  final List<AppDefinition> plugins;
  final Map<String, AppRuntimeState> states;

  const AppCatalogSnapshot({required this.plugins, required this.states});

  int get installedCount =>
      states.values.where((state) => state.installed).length;
}

/// A single read of the data needed to render Quick Apps.
class QuickAppsProjection {
  final List<AppDefinition> candidates;
  final QuickAppsConfig config;
  final List<String> recentIds;

  const QuickAppsProjection({
    required this.candidates,
    required this.config,
    required this.recentIds,
  });
}

class AppService {
  /// 持久化键保持稳定（历史版本写入）。
  static const _statesKey = 'plugins.v1.states';
  static const _recentKey = 'plugins.v1.recent';
  static const _recentKeyPrefix = 'plugins.v1.recent.';
  static String _recentKeyFor(String accountKey) =>
      '$_recentKeyPrefix$accountKey';

  /// Returns recently used app ids, most recent first.
  static Future<List<String>> getRecentAppIds(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKeyFor(accountKey)) ?? const [];
  }

  /// Records a successful launch so 首页/应用 can order recent apps.
  static Future<void> recordUsage(
    String id, {
    required String accountKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_recentKeyFor(accountKey)) ?? const [];
    final next = <String>[id, ...current.where((item) => item != id)];
    await prefs.setStringList(
      _recentKeyFor(accountKey),
      next.take(12).toList(),
    );
    _notifyChanged();
  }

  /// 清空旧版全局最近使用与全部账号作用域最近使用。
  static Future<void> clearAllRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs
            .getKeys()
            .where(
              (key) => key == _recentKey || key.startsWith(_recentKeyPrefix),
            )
            .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (keys.isNotEmpty) _notifyChanged();
  }

  /// Orders [plugins] by [recentIds] (most recent first), appending the rest
  /// in their original order, and caps the result at [limit].
  static List<AppDefinition> orderByRecent(
    List<AppDefinition> plugins,
    List<String> recentIds, {
    int? limit,
  }) {
    final byId = <String, AppDefinition>{
      for (final plugin in plugins) plugin.metadata.id: plugin,
    };
    final ordered = <AppDefinition>[];
    for (final id in recentIds) {
      final plugin = byId.remove(id);
      if (plugin != null) ordered.add(plugin);
    }
    ordered.addAll(byId.values);
    if (limit != null && ordered.length > limit) {
      return ordered.sublist(0, limit);
    }
    return ordered;
  }

  /// Orders the selected quick apps: recent-first or the persisted manual
  /// order. Only IDs in `config.selectedAppIds` participate.
  static List<AppDefinition> orderQuickApps(
    List<AppDefinition> plugins,
    List<String> recentIds,
    QuickAppsConfig config, {
    int limit = 8,
  }) {
    final byId = <String, AppDefinition>{
      for (final plugin in plugins) plugin.metadata.id: plugin,
    };
    final selectedIds = config.selectedAppIds
        .where(byId.containsKey)
        .take(limit)
        .toList(growable: false);
    if (selectedIds.isEmpty) return const [];

    if (config.sortMode == QuickAppsSortMode.recent) {
      final selected = <AppDefinition>[for (final id in selectedIds) byId[id]!];
      return orderByRecent(selected, recentIds, limit: limit);
    }
    final ordered = <AppDefinition>[];
    for (final id in config.manualOrder) {
      if (!selectedIds.contains(id)) continue;
      final plugin = byId.remove(id);
      if (plugin != null) ordered.add(plugin);
    }
    for (final id in selectedIds) {
      final plugin = byId.remove(id);
      if (plugin != null) ordered.add(plugin);
    }
    if (ordered.length > limit) return ordered.sublist(0, limit);
    return ordered;
  }

  /// 所有可加入常用应用的已安装非 core 应用。
  static Future<List<AppDefinition>> getQuickAppCandidates() async {
    final catalog = await loadCatalog();
    return _installedCandidates(catalog);
  }

  /// 读取常用应用配置；首次读取时按注册表 `defaultPinned` 生成默认选择。
  static Future<QuickAppsConfig> getQuickAppsConfig(String accountKey) async {
    final demo = DemoDataService.instance;
    if (demo.enabled) {
      final candidates = await getQuickAppCandidates();
      return _defaultQuickAppsConfig(
        const QuickAppsConfig(enabled: true, initialized: true),
        candidates,
        limit: demo.config.quickAppCount,
      );
    }
    final stored = await HomeLayoutService.readQuickApps(accountKey);
    if (stored.initialized) return stored;

    final candidates = await getQuickAppCandidates();
    return HomeLayoutService.initializeQuickAppsIfNeeded(
      accountKey,
      _defaultQuickAppsConfig(stored, candidates),
    );
  }

  /// Loads catalog state, Quick Apps configuration, and recent usage once for
  /// surfaces that render the full Quick Apps projection.
  static Future<QuickAppsProjection> loadQuickAppsProjection(
    String accountKey,
  ) async {
    final catalogFuture = loadCatalog();
    final recentFuture = getRecentAppIds(accountKey);
    final demo = DemoDataService.instance;

    if (demo.enabled) {
      final results = await Future.wait<Object>([catalogFuture, recentFuture]);
      final candidates = _installedCandidates(results[0] as AppCatalogSnapshot);
      final config = _defaultQuickAppsConfig(
        const QuickAppsConfig(enabled: true, initialized: true),
        candidates,
        limit: demo.config.quickAppCount,
      );
      return QuickAppsProjection(
        candidates: candidates,
        config: config,
        recentIds: results[1] as List<String>,
      );
    }

    final results = await Future.wait<Object>([
      catalogFuture,
      HomeLayoutService.readQuickApps(accountKey),
      recentFuture,
    ]);
    final catalog = results[0] as AppCatalogSnapshot;
    final candidates = _installedCandidates(catalog);
    final stored = results[1] as QuickAppsConfig;
    final recentIds = results[2] as List<String>;
    final config =
        stored.initialized
            ? stored
            : await HomeLayoutService.initializeQuickAppsIfNeeded(
              accountKey,
              _defaultQuickAppsConfig(stored, candidates),
            );

    return QuickAppsProjection(
      candidates: candidates,
      config: config,
      recentIds: recentIds,
    );
  }

  /// Loads the non-core plugin catalog and runtime states in one pass.
  static Future<AppCatalogSnapshot> loadCatalog() async {
    final managed = await getManagedApps();
    final plugins = managed
        .where((plugin) => !plugin.metadata.core)
        .toList(growable: false);
    final storedStates = await _readStates();
    final states = <String, AppRuntimeState>{};
    for (final plugin in plugins) {
      final id = plugin.metadata.id;
      states[id] = _effectiveState(id, plugin, storedStates[id]);
    }
    return AppCatalogSnapshot(plugins: plugins, states: states);
  }

  static List<AppDefinition> _installedCandidates(AppCatalogSnapshot catalog) {
    return [
      for (final plugin in catalog.plugins)
        if (catalog.states[plugin.metadata.id]?.installed ?? false) plugin,
    ];
  }

  static QuickAppsConfig _defaultQuickAppsConfig(
    QuickAppsConfig base,
    Iterable<AppDefinition> candidates, {
    int? limit,
  }) {
    final defaults = [
      for (final plugin in candidates)
        if (plugin.metadata.defaultPinned) plugin.metadata.id,
    ];
    final selected =
        limit == null ? defaults : defaults.take(limit).toList(growable: false);
    return base.copyWith(
      selectedAppIds: selected,
      manualOrder: selected,
      initialized: true,
    );
  }

  static Future<List<AppDefinition>> getManagedApps() async {
    final apps = await _getAllManagedApps();
    return filterAppsForBuild(apps, debugBuild: DevelopmentModeService.isDev);
  }

  /// Filters the catalog using an explicit build mode so the release gate can
  /// be tested without changing the current process mode.
  static List<AppDefinition> filterAppsForBuild(
    Iterable<AppDefinition> apps, {
    required bool debugBuild,
  }) {
    final source = apps.toList(growable: false);
    if (debugBuild) return source;
    return source
        .where((plugin) => !plugin.metadata.requiresDev)
        .toList(growable: false);
  }

  static bool isVisibleInCurrentMode(AppDefinition plugin) {
    return isVisibleInBuild(plugin, debugBuild: DevelopmentModeService.isDev);
  }

  static bool isVisibleInBuild(
    AppDefinition plugin, {
    required bool debugBuild,
  }) {
    return !plugin.metadata.requiresDev || debugBuild;
  }

  static Future<List<AppDefinition>> _getAllManagedApps() async =>
      AppRegistry.builtIns;

  static Future<AppRuntimeState> getState(String id) async {
    final plugin = await _findApp(id);
    final states = await _readStates();
    return _effectiveState(id, plugin, states[id]);
  }

  static Future<void> uninstall(String id) async {
    final plugin = await _findApp(id);
    if (plugin == null || plugin.metadata.core || !plugin.metadata.removable) {
      return;
    }

    final states = await _readStates();
    final current = await getState(id);
    states[id] = current.copyWith(installed: false);
    await _writeStates(states);
    _notifyChanged();
  }

  /// 从编译期注册表恢复/安装内置应用。
  static Future<void> reinstallFromCatalog(String id) async {
    final plugin = AppRegistry.publishedById(id);
    if (plugin == null || plugin.metadata.core) return;

    final states = await _readStates();
    states[id] = AppRuntimeState(installed: true, core: plugin.metadata.core);
    await _writeStates(states);
    _notifyChanged();
  }

  static Future<void> resetRuntimeState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_statesKey);
    _notifyChanged();
  }

  static Future<AppDefinition?> _findApp(String id) async =>
      AppRegistry.publishedById(id);
  static Future<Map<String, AppRuntimeState>> _readStates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statesKey);
    if (raw == null || raw.isEmpty) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(
        key,
        AppRuntimeState.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  static Future<void> _writeStates(Map<String, AppRuntimeState> states) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(
      states.map((key, value) => MapEntry(key, value.toJson())),
    );
    final saved = await prefs.setString(_statesKey, raw);
    if (!saved) throw StateError('应用运行状态保存失败');
  }

  static void _notifyChanged() {
    appCatalogNotifier.value++;
  }
}

AppRuntimeState _effectiveState(
  String id,
  AppDefinition? plugin,
  AppRuntimeState? stored,
) {
  final isCore = plugin?.metadata.core ?? isCoreAppId(id);
  if (stored == null) {
    return AppRuntimeState(installed: true, core: isCore);
  }
  return AppRuntimeState(
    installed: isCore ? true : stored.installed,
    core: isCore,
  );
}

class AppRuntimeState {
  final bool installed;
  final bool core;

  const AppRuntimeState({required this.installed, required this.core});

  AppRuntimeState copyWith({bool? installed, bool? core}) {
    return AppRuntimeState(
      installed: installed ?? this.installed,
      core: core ?? this.core,
    );
  }

  Map<String, dynamic> toJson() => {'installed': installed, 'core': core};

  factory AppRuntimeState.fromJson(Map<String, dynamic> json) {
    return AppRuntimeState(
      installed: json['installed'] as bool? ?? true,
      core: json['core'] as bool? ?? false,
    );
  }
}
