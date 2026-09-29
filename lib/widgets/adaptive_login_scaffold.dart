import 'package:flutter/material.dart';

import '../capabilities/dev_visibility.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// Presentation-only shell for the shared unified-identity login WebView.
class AdaptiveLoginScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback onOpenLog;
  final VoidCallback onConfirm;
  final bool isConfirming;

  const AdaptiveLoginScaffold({
    super.key,
    required this.child,
    required this.onOpenLog,
    required this.onConfirm,
    required this.isConfirming,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('统一身份认证'),
          centerTitle: true,
          actions: [
            DevOnly(
              child: IconButton(
                icon: const Icon(Icons.article_outlined),
                tooltip: '查看日志',
                onPressed: onOpenLog,
              ),
            ),
            TextButton(
              onPressed: isConfirming ? null : onConfirm,
              child: Text(isConfirming ? '确认中' : '完成'),
            ),
          ],
        ),
      ),
      body: child,
    );
  }
}
