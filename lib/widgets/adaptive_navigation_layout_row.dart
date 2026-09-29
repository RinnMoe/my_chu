import 'package:flutter/material.dart';

/// Material 3 row for navigation preferences and ordering.
class AdaptiveNavigationLayoutRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? titleAccessory;
  final bool enabled;
  final ValueChanged<bool>? onEnabledChanged;
  final bool reorderable;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const AdaptiveNavigationLayoutRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleAccessory,
    required this.enabled,
    this.onEnabledChanged,
    this.reorderable = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleLine = Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (titleAccessory != null) ...[
          const SizedBox(width: 8),
          titleAccessory!,
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleLine,
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (reorderable) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: '上移',
              visualDensity: VisualDensity.compact,
              onPressed: onMoveUp,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: '下移',
              visualDensity: VisualDensity.compact,
              onPressed: onMoveDown,
            ),
          ],
          if (onEnabledChanged != null)
            Switch(value: enabled, onChanged: onEnabledChanged),
        ],
      ),
    );
  }
}
