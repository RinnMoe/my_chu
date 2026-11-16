import 'package:flutter/material.dart';

import 'app_bottom_sheet.dart';

class AppSelectionOption<T> {
  const AppSelectionOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

class AppSelectionTile extends StatelessWidget {
  const AppSelectionTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final Widget title;
  final Widget? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: ListTile(
      title: title,
      subtitle: subtitle,
      selected: selected,
      enabled: enabled,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: enabled ? onTap : null,
    ),
  );
}

Future<AppSelectionOption<T>?> showAppSelectionSheet<T>(
  BuildContext context, {
  required String title,
  required T value,
  required List<AppSelectionOption<T>> options,
}) => showAppBottomSheet<AppSelectionOption<T>>(
  context: context,
  builder:
      (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeader(title: title),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  for (final option in options)
                    AppSelectionTile(
                      title: Text(option.label),
                      subtitle:
                          option.subtitle == null
                              ? null
                              : Text(option.subtitle!),
                      selected: option.value == value,
                      onTap: () => Navigator.of(context).pop(option),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
);

/// A labeled selection field with the same single-choice sheet on every page.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<AppSelectionOption<T>> options;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && options.isNotEmpty;
    final selected =
        options.where((option) => option.value == value).firstOrNull;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap:
              !enabled
                  ? null
                  : () async {
                    final result = await showAppSelectionSheet<T>(
                      context,
                      title: label,
                      value: value,
                      options: options,
                    );
                    if (result != null && context.mounted) {
                      onChanged!(result.value);
                    }
                  },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, enabled: enabled),
            child: Row(
              children: [
                Expanded(child: Text(selected?.label ?? '请选择')),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
