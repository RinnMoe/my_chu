import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../apps/app_registry.dart';
import '../capabilities/academic_schedule/academic_schedule_capability.dart';
import 'navigation_layout_service.dart';

/// Presentation metadata for one bottom navigation destination.
///
/// The shell keeps ownership of page builders, account fences and selection
/// state. This type only carries the label and icons so the root bar and the
/// settings list cannot drift apart.
@immutable
class NavigationTabPresentation {
  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const NavigationTabPresentation({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Presentation metadata for every destination the host itself renders.
///
/// Built-in app tabs resolve through [AppRegistry] so a single bar label is
/// stored on the app metadata.
abstract final class NavigationTabPresentations {
  static const _home = NavigationTabPresentation(
    key: NavigationLayoutService.hostHomeKey,
    label: '焦点',
    icon: Icons.lightbulb_outline,
    selectedIcon: Icons.lightbulb,
  );

  static const _apps = NavigationTabPresentation(
    key: NavigationLayoutService.hostAppsKey,
    label: '功能',
    icon: Symbols.category_search,
    selectedIcon: Symbols.category_search,
  );

  static const _map = NavigationTabPresentation(
    key: NavigationLayoutService.hostMapKey,
    label: '地图',
    icon: Icons.map_outlined,
    selectedIcon: Icons.map,
  );

  static const _profile = NavigationTabPresentation(
    key: NavigationLayoutService.hostProfileKey,
    label: '选项',
    icon: Symbols.deployed_code,
    selectedIcon: Symbols.deployed_code,
  );

  /// The timetable capability is host-owned rather than a registered app, so
  /// its label and icon come from the capability declaration.
  static NavigationTabPresentation get _schedule => NavigationTabPresentation(
    key: NavigationLayoutService.academicScheduleKey,
    label: academicScheduleCapability.navigationLabel,
    icon: academicScheduleCapability.icon,
    selectedIcon: academicScheduleCapability.icon,
  );

  /// The 选项 glyph carries two host states, so the bar reports a pending
  /// update or a signed-out session even before the red update dot is noticed.
  ///
  /// A known update wins: it is the state the user has to act on, and the
  /// account glyph returns as soon as the update is installed.
  static IconData profileIconFor({
    required bool updateAvailable,
    required bool signedIn,
  }) {
    if (updateAvailable) return Symbols.deployed_code_update;
    if (!signedIn) return Symbols.deployed_code_account;
    return Symbols.deployed_code;
  }

  /// Resolves any persistable bar key, including built-in app tabs, to its
  /// presentation metadata.
  static NavigationTabPresentation? forKey(String key) {
    switch (key) {
      case NavigationLayoutService.hostHomeKey:
        return _home;
      case NavigationLayoutService.hostAppsKey:
        return _apps;
      case NavigationLayoutService.academicScheduleKey:
        return _schedule;
      case NavigationLayoutService.hostMapKey:
        return _map;
      case NavigationLayoutService.hostProfileKey:
        return _profile;
    }
    final metadata = AppRegistry.publishedById(key)?.metadata;
    if (metadata == null) return null;
    return NavigationTabPresentation(
      key: key,
      label: metadata.navigationLabel ?? metadata.name,
      icon: metadata.icon,
      selectedIcon: metadata.icon,
    );
  }
}
