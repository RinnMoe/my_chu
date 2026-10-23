import 'package:flutter/widgets.dart';

/// Stable semantic role for root navigation presentation.
///
/// The role is deliberately independent from the localized label and from the
/// item's position. Host destinations must set their role explicitly; plugin
/// destinations use [custom].
enum AdaptiveNavigationRole { home, apps, map, profile, custom }

/// Platform-neutral root navigation presentation data.
///
/// This object deliberately carries no navigation state or page builder. The
/// host owns destination identity, selected state and page lifetime; adaptive
/// shells only render this presentation contract.
@immutable
class AdaptiveNavigationItem {
  final AdaptiveNavigationRole role;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? badgeLabel;

  const AdaptiveNavigationItem({
    this.role = AdaptiveNavigationRole.custom,
    this.badgeLabel,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}
