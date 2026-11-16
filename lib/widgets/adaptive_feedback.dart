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
      child: const CircularProgressIndicator(
        strokeWidth: 3,
        semanticsLabel: '正在加载',
      ),
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
    return AdaptiveStatusState(
      icon: Icons.cloud_off_outlined,
      message: [title, if (message != null) message!].join('\n'),
      error: true,
      action:
          onRetry == null
              ? null
              : FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
    );
  }
}

class AdaptiveStatusState extends StatelessWidget {
  const AdaptiveStatusState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final Widget? action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: error,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  icon,
                  size: 48,
                  color:
                      error
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
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
