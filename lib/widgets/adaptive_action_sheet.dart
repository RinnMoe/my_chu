import 'package:flutter/material.dart';

/// One value-bearing action in an [AdaptiveActionSheet].
@immutable
class AdaptiveActionSheetOption<T> {
  const AdaptiveActionSheetOption({
    required this.label,
    required this.value,
    this.selected = false,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final T value;
  final bool selected;
  final bool destructive;
  final bool enabled;
}

/// Shows a Material 3 action sheet and returns the chosen value.
Future<T?> showAdaptiveActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<AdaptiveActionSheetOption<T>> options,
  String cancelLabel = '取消',
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder:
        (sheetContext) => AdaptiveActionSheet<T>(
          title: title,
          message: message,
          options: options,
          cancelLabel: cancelLabel,
        ),
  );
}

/// The Material 3 surface used by [showAdaptiveActionSheet].
class AdaptiveActionSheet<T> extends StatelessWidget {
  const AdaptiveActionSheet({
    super.key,
    this.title,
    this.message,
    required this.options,
    this.cancelLabel = '取消',
  });

  final String? title;
  final String? message;
  final List<AdaptiveActionSheetOption<T>> options;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (title != null || message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!, style: theme.textTheme.titleLarge),
                  if (message != null) ...[
                    const SizedBox(height: 4),
                    Text(message!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          for (final option in options)
            ListTile(
              title: Text(
                option.label,
                style:
                    option.destructive
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
              ),
              trailing: option.selected ? const Icon(Icons.check) : null,
              enabled: option.enabled,
              onTap:
                  option.enabled
                      ? () => Navigator.of(context).pop(option.value)
                      : null,
            ),
          ListTile(
            title: Text(cancelLabel),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
