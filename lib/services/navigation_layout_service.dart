import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../apps/app_registry.dart';
import '../apps/app_service.dart';

/// Persisted middle-section order and launch page for the bottom navigation
/// bar.
///
/// The bar is `焦点` (fixed first) + a reorderable middle + `选项` (fixed
/// last). The middle holds the host tabs `功能`/`课表`/`地图` and any user-enabled
/// app tabs. App tab order is the single source of truth: an app id
/// present in [NavigationTabLayout.order] is enabled. Development-only host tabs
/// may be injected into the resolved runtime order without being persisted.
///
/// [NavigationTabLayout.startKey] is the destination selected on launch. It may
/// name any destination the bar can render, including the fixed first/last ones.
class NavigationTabLayout {
  final List<String> order;

  /// Destination selected when the application starts. Defaults to the focus
  /// page, which keeps the pre-setting behaviour for existing layouts.
  final String startKey;

  const NavigationTabLayout({
    required this.order,
    this.startKey = NavigationLayoutService.hostHomeKey,
  });

  Map<String, dynamic> toJson() => {'order': order, 'startKey': startKey};

  factory NavigationTabLayout.fromJson(Map<String, dynamic> json) {
    final raw = json['order'];
    final rawStartKey = json['startKey'];
    return NavigationTabLayout(
      order:
          raw is List
              ? raw.whereType<String>().toList(growable: false)
              : const [],
      // Layouts written before the launch setting existed carry no start key;
      // they must keep opening on the focus page instead of failing to decode.
      startKey:
          rawStartKey is String && rawStartKey.isNotEmpty
              ? rawStartKey
              : NavigationLayoutService.hostHomeKey,
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
  /// capped at [maxAppTabs]; `home`/`profile` are rejected. The stored launch
  /// page is preserved unless the reordered bar no longer renders it.
  static Future<void> setOrder(List<String> keys) async {
    final validNavigationAppIds = await _validNavigationAppIds();
    final current = await read(validAppIds: validNavigationAppIds);
    final middle = _normalized(
      NavigationTabLayout(
        order: keys.where((key) => !_isHostRoot(key)).toList(),
        startKey: current.startKey,
      ),
      validNavigationAppIds,
    );
    await _write(middle);
  }

  /// Selects the destination the application starts on.
  ///
  /// Any rendered bar destination is accepted, including the fixed focus and
  /// profile pages. A key that is not part of the resolved middle section (for
  /// example a disabled app tab) is normalised back to the focus page.
  static Future<void> setStartKey(String key) async {
    final validNavigationAppIds = await _validNavigationAppIds();
    final layout = await read(validAppIds: validNavigationAppIds);
    final next = _normalized(
      NavigationTabLayout(order: layout.order, startKey: key),
      validNavigationAppIds,
    );
    await _write(next);
  }

  /// Resolves [NavigationTabLayout.startKey] against the destinations the shell
  /// can actually render right now.
  ///
  /// A tab hidden by the published safety policy, an uninstalled app or a build
  /// filter falls back to the focus page without discarding the stored choice,
  /// so the user's launch page returns once the destination is available.
  static String resolveStartKey(
    NavigationTabLayout layout, {
    required Iterable<String> availableKeys,
  }) => availableKeys.contains(layout.startKey)
      ? layout.startKey
      : hostHomeKey;

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
      final totalCount = order.length + 2; // 中段 + 首页/选项
      if (!present && pluginCount >= maxAppTabs) return false;
      if (!present && totalCount >= maxTotalTabs) return false;
      if (!present) {
        order.add(pluginId);
      }
    } else {
      order.remove(pluginId);
    }
    await _write(NavigationTabLayout(order: order, startKey: layout.startKey));
    return true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key());
    revision.value++;
  }

  /// Full tab key order: `焦点` first, `选项` last.
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

    // 焦点和选项占两项，因此中段最多保留四项。 Preserve the configured
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
    // The launch page must still be a member of the resolved bar; a disabled
    // app tab silently returns to the focus page instead of persisting a
    // destination that can never be selected.
    final startKey = layout.startKey;
    return NavigationTabLayout(
      order: result,
      startKey:
          startKey == hostHomeKey ||
                  startKey == hostProfileKey ||
                  result.contains(startKey)
              ? startKey
              : hostHomeKey,
    );
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
