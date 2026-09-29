import 'package:flutter/material.dart';

/// A grouped Material 3 settings section.
class AdaptiveSettingsSection extends StatelessWidget {
  const AdaptiveSettingsSection({
    super.key,
    this.title,
    required this.children,
    this.margin = EdgeInsets.zero,
    this.dividerIndent = 56,
  });

  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) Divider(height: 1, indent: dividerIndent),
                  children[index],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A Material 3 row for settings and grouped preferences.
class AdaptiveSettingsRow extends StatelessWidget {
  const AdaptiveSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingValue,
    this.trailing,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? _buildTrailing(context),
      onTap: onTap,
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    final theme = Theme.of(context);
    final value =
        trailingValue == null
            ? null
            : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                trailingValue!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
    final chevron = showChevron ? const Icon(Icons.chevron_right) : null;
    if (value == null && chevron == null) return null;
    if (value == null) return chevron;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        value,
        if (chevron != null) const SizedBox(width: 4),
        if (chevron != null) chevron,
      ],
    );
  }
}
