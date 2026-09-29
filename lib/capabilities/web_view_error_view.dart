import 'package:flutter/material.dart';

/// Shared host-owned error surface for WebViews.
///
/// Native WebView error pages expose implementation details such as URLs and
/// Chromium error codes. Keep the user-facing state in Flutter so every
/// built-in WebView can present the same safe, retryable experience.
class WebViewErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const WebViewErrorView({
    super.key,
    this.message = '页面暂时无法打开，请检查网络后重试。',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 56, color: colors.primary),
              const SizedBox(height: 20),
              Text(
                '页面加载失败',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
