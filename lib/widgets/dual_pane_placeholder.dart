import 'package:flutter/material.dart';

/// Detail-pane placeholder for split-view layouts before a list item is picked.
///
/// The list and the empty pane already express the master-detail relationship,
/// so no instructional copy is shown. The icon is decorative and hidden from
/// semantics.
class DualPanePlaceholder extends StatelessWidget {
  const DualPanePlaceholder({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: ExcludeSemantics(
          child: Icon(icon, size: 40, color: colors.outline),
        ),
      ),
    );
  }
}
