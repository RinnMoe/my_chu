import 'package:flutter/material.dart';

/// Material 3 loading state for a page or bounded module.
class AdaptiveLoadingState extends StatelessWidget {
  const AdaptiveLoadingState({super.key, this.label, this.radius = 14});

  final String? label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: const CircularProgressIndicator(strokeWidth: 3),
    );
    if (label == null) return Center(child: indicator);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [indicator, const SizedBox(height: 12), Text(label!)],
      ),
    );
  }
}

/// Material 3 bounded error state with an optional retry action.
class AdaptiveErrorState extends StatelessWidget {
  const AdaptiveErrorState({
    super.key,
    required this.title,
    this.message,
    this.retryLabel = '重试',
    this.onRetry,
  });

  final String title;
  final String? message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}

/// Shows a short Material 3 message dialog.
Future<void> showAdaptiveMessageDialog(
  BuildContext context, {
  required String message,
  String title = '提示',
  String confirmLabel = '好',
}) {
  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(confirmLabel),
            ),
          ],
        ),
  );
}
