import 'package:flutter/material.dart';

import '../services/platform_environment.dart';
import 'adaptive_navigation_item.dart';

/// Material-only root navigation presentation.
///
/// Navigation state, destination identity and page lifetime remain owned by
/// the host. This shell only renders the existing Android/Web NavigationBar.
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
  });

  final List<AdaptiveNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final DeviceFamily deviceFamily;
  final WindowClass windowClass;
  final Widget child;
  final Key? navigationRegionKey;

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
                  extended: windowClass.isExpanded,
                  labelType:
                      windowClass.isExpanded
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                  leading:
                      windowClass.isExpanded
                          ? Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            child: Text(
                              'MyCHU',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          )
                          : null,
                  destinations: [
                    for (final item in items)
                      NavigationRailDestination(
                        icon: _navigationIcon(item.icon),
                        selectedIcon: _navigationIcon(item.selectedIcon),
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: child,
      bottomNavigationBar:
          items.length < 2
              ? null
              : KeyedSubtree(
                key: navigationRegionKey,
                child: NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  destinations: [
                    for (final item in items)
                      NavigationDestination(
                        icon: _navigationIcon(item.icon),
                        selectedIcon: _navigationIcon(item.selectedIcon),
                        label: item.label,
                      ),
                  ],
                ),
              ),
    );
  }

  Widget _navigationIcon(IconData icon) => Icon(icon);
}
