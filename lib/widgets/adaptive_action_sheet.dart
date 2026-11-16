import 'app_bottom_sheet.dart';
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
}) {
  return showAppBottomSheet<T>(
    context: context,
    builder:
        (sheetContext) => AdaptiveActionSheet<T>(
          title: title,
          message: message,
          options: options,
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
  });

  final String? title;
  final String? message;
  final List<AdaptiveActionSheetOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Text(
                title!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(message!, style: theme.textTheme.bodyMedium),
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
        ],
      ),
    );
  }
}
