import 'package:flutter/material.dart';

/// A grouped Material 3 settings section.
class AdaptiveSettingsSection extends StatelessWidget {
  const AdaptiveSettingsSection({
    super.key,
    this.title,
    this.footer,
    required this.children,
    this.margin = EdgeInsets.zero,
    this.dividerIndent = 16,
  });

  final String? title;

  /// 卡片下方的说明，用于承载布局本身表达不了的约束或后果。
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: margin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[AppSectionHeading(title!)],
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var index = 0; index < children.length; index++) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          indent: dividerIndent,
                          endIndent: 16,
                        ),
                      children[index],
                    ],
                  ],
                ),
              ),
              if (footer != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    footer!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final value = trailingValue;
        final titleStyle = theme.textTheme.bodyLarge!;
        final valueStyle = theme.textTheme.bodyMedium!.copyWith(
          color:
              enabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.disabledColor,
        );
        double textWidth(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final stacked =
            value != null &&
            trailing == null &&
            textWidth(title, titleStyle) + textWidth(value, valueStyle) >
                constraints.maxWidth - 136;
        return ListTile(
          enabled: enabled,
          leading: Icon(icon),
          title: Text(title),
          subtitle:
              stacked
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (subtitle != null) Text(subtitle!),
                      Text(value, style: valueStyle),
                    ],
                  )
                  : subtitle == null
                  ? null
                  : Text(subtitle!),
          trailing:
              trailing ??
              (stacked
                  ? showChevron
                      ? const Icon(Icons.chevron_right)
                      : null
                  : _buildTrailing(context)),
          onTap: onTap,
        );
      },
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
                  color:
                      enabled
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.disabledColor,
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

class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
