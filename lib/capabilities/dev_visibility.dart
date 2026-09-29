import 'package:flutter/material.dart';

import '../services/development_mode_service.dart';

/// Renders [child] only while the process is in DEV mode.
class DevOnly extends StatelessWidget {
  final Widget child;

  const DevOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DevelopmentModeService.isDev ? child : const SizedBox.shrink();
  }
}

/// Compact label used to identify a visible development-only feature.
class DevBadge extends StatelessWidget {
  const DevBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: 'DEV',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'DEV',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onTertiaryContainer,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
