import 'package:flutter/material.dart';

double appBottomSheetContentHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  return ((media.size.height - media.padding.top) * 0.9 - 48).clamp(
    0.0,
    double.infinity,
  );
}

/// Shared modal bounds, keyboard handling and safe areas for host and apps.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool scrollBody = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder:
        (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: appBottomSheetContentHeight(sheetContext),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: MediaQuery.removeViewInsets(
              context: sheetContext,
              removeBottom: true,
              child: Builder(
                builder: (context) {
                  final content = builder(context);
                  return scrollBody
                      ? SingleChildScrollView(child: content)
                      : content;
                },
              ),
            ),
          ),
        ),
  );
}

class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.padding = const EdgeInsets.only(left: 16, right: 16, bottom: 8),
  });

  final String title;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ...actions,
      ],
    ),
  );
}
