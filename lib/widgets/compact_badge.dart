import 'package:flutter/material.dart';

/// Compact inline state marker rendered next to a title.
///
/// Only for a state the surrounding layout cannot express on its own, such as a
/// value that is a fallback default rather than a stored choice. Keep the label
/// to one or two characters; anything longer belongs in the title itself.
class CompactBadge extends StatelessWidget {
  const CompactBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
