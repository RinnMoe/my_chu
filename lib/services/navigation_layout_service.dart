import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../apps/app_registry.dart';
import '../apps/app_service.dart';

/// Persisted middle-section order for the bottom navigation bar.
///
/// The bar is `首页` (fixed first) + a reorderable middle + `我的` (fixed
/// last). The middle holds the host tabs `应用`/`课表`/`地图` and any user-enabled
/// app tabs. App tab order is the single source of truth: an app id
/// present in [NavigationTabLayout.order] is enabled. Development-only host tabs
/// may be injected into the resolved runtime order without being persisted.
class NavigationTabLayout {
  final List<String> order;

  const NavigationTabLayout({required this.order});

  Map<String, dynamic> toJson() => {'order': order};

  factory NavigationTabLayout.fromJson(Map<String, dynamic> json) {
    final raw = json['order'];
    return NavigationTabLayout(
      order:
          raw is List
              ? raw.whereType<String>().toList(growable: false)
              : const [],
    );
  }
}

/// Device-wide bottom navigation layout.
class NavigationLayoutService {
  static const hostHomeKey = 'home';
  static const hostAppsKey = 'apps';
  static const hostMapKey = 'map';
  static const hostProfileKey = 'profile';

  /// User-configured app tabs are capped at 2; schedule and map do not use that
  /// quota. Persisted destinations remain within [maxTotalTabs] (6); ephemeral
  /// development destinations are added only to the runtime order.
  static const maxAppTabs = 2;
  static const maxTotalTabs = 6;
  static const academicScheduleKey = 'feature.academic.schedule';

  static const defaultAppTabs = [academicScheduleKey];
  static const defaultMiddle = [hostAppsKey, ...defaultAppTabs, hostMapKey];
  static const defaultOrder = defaultMiddle;

  /// Bumped whenever the layout changes so the shell can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _key() => 'preferences.v1.navigation';

  static Future<NavigationTabLayout> read({Set<String>? validAppIds}) async {
    final validNavigationAppIds = validAppIds ?? await _validNavigationAppIds();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    if (raw != null) {
      final normalized = _decodeOrDefault(raw, validNavigationAppIds);
      if (raw != jsonEncode(normalized.toJson())) {
        await _write(normalized);
      }
      return normalized;
    }

    return _decodeOrDefault('', validNavigationAppIds);
  }

  /// Reorders the middle section. The `apps` host key is always kept;
  /// `map` is optional; the schedule host is always present. App ids are
  /// capped at [maxAppTabs]; `home`/`profile` are rejected.
  static Future<void> setOrder(List<String> keys) async {
    final validNavigationAppIds = await _validNavigationAppIds();
    final middle = _normalized(
      NavigationTabLayout(
        order: keys.where((key) => !_isHostRoot(key)).toList(),
      ),
      validNavigationAppIds,
    );
    await _write(middle);
  }

  /// Enables or disables an app tab. Host tabs use [setOrder]. Returns false
  /// when the app tab cap would be exceeded. The schedule host is mandatory.
  static Future<bool> setAppEnabled(String pluginId, bool enabled) async {
    if (pluginId == academicScheduleKey) return true;
    final validNavigationAppIds = await _validNavigationAppIds();
    final layout = await read(validAppIds: validNavigationAppIds);
    final order = List<String>.from(layout.order);
    final present = order.contains(pluginId);
    if (enabled) {
      if (!validNavigationAppIds.contains(pluginId)) return false;
      final pluginCount = order.where(validNavigationAppIds.contains).length;
      final totalCount = order.length + 2; // 中段 + 首页/我的
      if (!present && pluginCount >= maxAppTabs) return false;
      if (!present && totalCount >= maxTotalTabs) return false;
      if (!present) {
        order.add(pluginId);
      }
    } else {
      order.remove(pluginId);
    }
    await _write(NavigationTabLayout(order: order));
    return true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key());
    revision.value++;
  }

  /// Full tab key order: `首页` first, `我的` last.
  static List<String> resolveTabKeys(NavigationTabLayout layout) {
    final middle = layout.order;
    return [hostHomeKey, ...middle, hostProfileKey];
  }

  static NavigationTabLayout _normalized(
    NavigationTabLayout layout,
    Set<String> validAppIds,
  ) {
    final result = <String>[];
    for (final key in layout.order) {
      if (_isHostRoot(key)) continue;
      if (_isHostKey(key)) {
        if (!result.contains(key)) result.add(key);
        continue;
      }
      if (!validAppIds.contains(key)) continue;
      if (!result.contains(key) &&
          result.where(validAppIds.contains).length < maxAppTabs) {
        result.add(key);
      }
    }
    if (!result.contains(hostAppsKey)) {
      result.insert(0, hostAppsKey);
    }
    if (!result.contains(academicScheduleKey)) {
      final appsIndex = result.indexOf(hostAppsKey);
      result.insert(appsIndex >= 0 ? appsIndex + 1 : 0, academicScheduleKey);
    }

    // 首页和我的占两项，因此中段最多保留四项。 Preserve the configured
    // relative order and trim only optional entries when migrating an older
    // layout that exceeded the new mandatory schedule-tab limit.
    const maxMiddle = maxTotalTabs - 2;
    while (result.length > maxMiddle) {
      final removable = result.lastIndexWhere(
        (key) => key != hostAppsKey && key != academicScheduleKey,
      );
      if (removable < 0) break;
      result.removeAt(removable);
    }
    return NavigationTabLayout(order: result);
  }

  static NavigationTabLayout _decodeOrDefault(
    String raw,
    Set<String> validAppIds,
  ) {
    if (raw.isEmpty) {
      return _normalized(
        const NavigationTabLayout(order: defaultOrder),
        validAppIds,
      );
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return _normalized(
        const NavigationTabLayout(order: defaultOrder),
        validAppIds,
      );
    }
    return _normalized(NavigationTabLayout.fromJson(decoded), validAppIds);
  }

  static Future<Set<String>> _validNavigationAppIds() async {
    final valid = <String>{};
    for (final plugin in AppRegistry.builtIns) {
      final metadata = plugin.metadata;
      if (metadata.core ||
          !metadata.showInNavigation ||
          !AppService.isVisibleInCurrentMode(plugin)) {
        continue;
      }
      if ((await AppService.getState(metadata.id)).installed) {
        valid.add(metadata.id);
      }
    }
    return valid;
  }

  static bool _isHostKey(String key) =>
      key == hostAppsKey || key == academicScheduleKey || key == hostMapKey;

  static bool _isHostRoot(String key) =>
      key == hostHomeKey || key == hostProfileKey;

  static Future<void> _write(NavigationTabLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(), jsonEncode(layout.toJson()));
    revision.value++;
  }
}
