import 'package:flutter/widgets.dart';

import '../services/platform_environment.dart';
import 'adaptive_navigation_item.dart';
import 'material_navigation_shell.dart';

export 'adaptive_navigation_item.dart';

/// Composition-boundary dispatcher for root navigation presentation.
///
/// The host remains the single owner of tab identity, selected state, lazy page
/// instances and account/session lifetime. Navigation adapts to device and
/// window size while keeping the Material 3 presentation on every platform.
class AdaptiveNavigationScaffold extends StatelessWidget {
  final List<AdaptiveNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;
  final Key? navigationRegionKey;
  final DeviceFamily? deviceFamilyOverride;
  final WindowClass? windowClassOverride;

  const AdaptiveNavigationScaffold({
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
    final environment = PlatformEnvironment.fromContext(
      context,
      deviceFamilyOverride: deviceFamilyOverride,
      windowClassOverride: windowClassOverride,
    );
    final deviceFamily = deviceFamilyOverride ?? environment.deviceFamily;
    final windowClass = windowClassOverride ?? environment.windowClass;

    return MaterialNavigationShell(
      items: items,
      selectedIndex: selectedIndex,
      onSelected: onSelected,
      deviceFamily: deviceFamily,
      windowClass: windowClass,
      navigationRegionKey: navigationRegionKey,
      child: child,
    );
  }
}
