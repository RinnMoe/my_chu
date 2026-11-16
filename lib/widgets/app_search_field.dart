import 'package:flutter/material.dart';

/// In-page search with a stable label and a conditional clear action.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder:
            (context, value, _) => TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    value.text.isEmpty
                        ? null
                        : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            controller.clear();
                            if (onClear != null) {
                              onClear!();
                            } else {
                              onChanged?.call('');
                            }
                          },
                        ),
              ),
            ),
      );
}
