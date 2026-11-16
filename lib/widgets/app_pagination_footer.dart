import 'package:flutter/material.dart';

class AppPaginationFooter extends StatelessWidget {
  const AppPaginationFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    this.error,
  });

  final bool loading;
  final bool hasMore;
  final String? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            Semantics(
              label: '正在加载',
              child: const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          else if (error != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ] else if (hasMore)
            TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('加载更多'),
            )
          else
            Text(
              '已全部加载',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    ),
  );
}
