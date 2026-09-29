import 'package:flutter/widgets.dart';

import '../services/platform_environment.dart';
import 'adaptive_navigation_scaffold.dart';

/// Root navigation presentation boundary.
///
/// The host supplies semantic destinations, selection, and the retained page
/// tree. Platform/window chrome is delegated to the adaptive navigation layer.
class AdaptiveRootNavigation extends StatelessWidget {
  final List<AdaptiveNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;
  final Key? navigationRegionKey;
  final DeviceFamily? deviceFamilyOverride;
  final WindowClass? windowClassOverride;

  const AdaptiveRootNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    this.navigationRegionKey,
    this.deviceFamilyOverride,
    this.windowClassOverride,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveNavigationScaffold(
      items: items,
      selectedIndex: selectedIndex,
      onSelected: onSelected,
      deviceFamilyOverride: deviceFamilyOverride,
      windowClassOverride: windowClassOverride,
      navigationRegionKey: navigationRegionKey,
      child: child,
    );
  }
}
