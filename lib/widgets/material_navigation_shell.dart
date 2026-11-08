import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../services/platform_environment.dart';
import '../theme/app_glass.dart';
import 'adaptive_navigation_item.dart';
import 'glass_surface.dart';

/// Root navigation with Material and native liquid-glass bottom bar styles.
///
/// Navigation state, destination identity and page lifetime remain owned by
/// the host. This shell renders the selected navigation presentation.
///
/// The page body extends behind the bottom bar (`extendBody`) so scroll content
/// shows through either style's glass material, and the body
/// receives a bottom `MediaQuery` inset equal to the bar height. Root pages add
/// that inset to their scroll padding so the last item is never hidden.
class MaterialNavigationShell extends StatelessWidget {
  const MaterialNavigationShell({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.deviceFamily,
    required this.windowClass,
    required this.child,
    this.navigationRegionKey,
    this.floatingBottomBar = false,
  });

  final List<AdaptiveNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final DeviceFamily deviceFamily;
  final WindowClass windowClass;
  final Widget child;
  final Key? navigationRegionKey;
  final bool floatingBottomBar;

  /// M3 NavigationBar 的默认高度；与 [NavigationBarThemeData.height] 一致。
  static const double _navigationBarHeight = 80;

  @override
  Widget build(BuildContext context) {
    final useRail =
        deviceFamily == DeviceFamily.tablet && windowClass.isAtLeastMedium;
    if (useRail) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: KeyedSubtree(
                key: navigationRegionKey,
                child: NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  extended: false,
                  minWidth: 80,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final item in items)
                      NavigationRailDestination(
                        icon: Tooltip(
                          message: item.label,
                          child: _navigationIcon(item.icon, item.badgeLabel),
                        ),
                        selectedIcon: Tooltip(
                          message: item.label,
                          child: _navigationIcon(
                            item.selectedIcon,
                            item.badgeLabel,
                          ),
                        ),
                        label: Text(item.label),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    final showBottomBar = items.length >= 2;
    final isMap =
        showBottomBar &&
        items[selectedIndex].role == AdaptiveNavigationRole.map;
    final colors = Theme.of(context).colorScheme;
    final floatingBar =
        floatingBottomBar && showBottomBar
            ? GlassTabBar.bottom(
              tabs: [
                for (final item in items)
                  GlassTab(
                    icon: _navigationIcon(item.icon, item.badgeLabel),
                    activeIcon: _navigationIcon(
                      item.selectedIcon,
                      item.badgeLabel,
                    ),
                    label: item.label,
                    semanticLabel: item.label,
                  ),
              ],
              selectedIndex: selectedIndex,
              onTabSelected: onSelected,
              quality: AppGlassMaterial.quality,
              backgroundQuality: AppGlassMaterial.quality,
              settings:
                  isMap
                      ? AppGlassMaterial.settingsFor(colors, mapBackdrop: true)
                      : null,
              platformViewBackdrop:
                  isMap && !ImageFilter.isShaderFilterSupported,
              selectedIconColor: colors.primary,
              selectedLabelColor: colors.primary,
              unselectedIconColor: colors.onSurface,
              unselectedLabelColor: colors.onSurface,
            )
            : null;
    final barHeight =
        floatingBar?.preferredSize.height ??
        NavigationBarTheme.of(context).height ??
        _navigationBarHeight;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      // 页面内容延伸到玻璃底栏后面，玻璃才有可采样的内容。
      extendBody: showBottomBar,
      body: showBottomBar ? _withBottomBarInset(context, barHeight) : child,
      bottomNavigationBar:
          showBottomBar
              ? KeyedSubtree(
                key: navigationRegionKey,
                child:
                    floatingBar != null
                        ? SafeArea(top: false, child: floatingBar)
                        : _GlassBottomBar(
                          selectedIndex: selectedIndex,
                          onSelected: onSelected,
                          items: items,
                          iconBuilder: _navigationIcon,
                        ),
              )
              : null,
    );
  }

  /// 把底栏高度并入 body 的底部 `MediaQuery`，让根页面自己决定滚动留白。
  Widget _withBottomBarInset(BuildContext context, double barHeight) {
    final mediaQuery = MediaQuery.of(context);
    final inset = barHeight + mediaQuery.padding.bottom;
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(bottom: inset),
      ),
      child: child,
    );
  }

  Widget _navigationIcon(IconData icon, String? badgeLabel) =>
      badgeLabel == null
          ? Icon(icon)
          : Semantics(
            label: badgeLabel,
            child: Badge(backgroundColor: Colors.red, child: Icon(icon)),
          );
}

/// 贴边玻璃底栏：全宽直角，内容叠在玻璃之上。
class _GlassBottomBar extends StatelessWidget {
  const _GlassBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    required this.iconBuilder,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AdaptiveNavigationItem> items;
  final Widget Function(IconData icon, String? badgeLabel) iconBuilder;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      // 贴边直角：底栏是整块玻璃，不等同于浮在内容上的圆角卡片。
      shape: const LiquidRoundedRectangle(borderRadius: 0),
      // 材质始终只做背景，地图上增加染色以保证图标对比度。
      platformViewBackdrop:
          items[selectedIndex].role == AdaptiveNavigationRole.map,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          navigationBarTheme: Theme.of(context).navigationBarTheme.copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              final ink = Theme.of(context).colorScheme.onSurface;
              if (states.contains(WidgetState.pressed)) {
                return ink.withValues(alpha: .12);
              }
              if (states.contains(WidgetState.focused)) {
                return ink.withValues(alpha: .14);
              }
              if (states.contains(WidgetState.hovered)) {
                return ink.withValues(alpha: .06);
              }
              return Colors.transparent;
            }),
          ),
        ),
        child: NavigationBar(
          // 玻璃是唯一表面，NavigationBar 保留布局和指示器，按压使用柔和高亮。
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: [
            for (final item in items)
              NavigationDestination(
                icon: iconBuilder(item.icon, item.badgeLabel),
                selectedIcon: iconBuilder(item.selectedIcon, item.badgeLabel),
                label: item.label,
              ),
          ],
        ),
      ),
    );
  }
}
