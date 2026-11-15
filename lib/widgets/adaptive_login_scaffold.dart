import 'package:flutter/material.dart';

import '../capabilities/dev_visibility.dart';

/// Presentation-only shell for the shared unified-identity login WebView.
class AdaptiveLoginScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onConfirm;
  final bool isConfirming;

  const AdaptiveLoginScaffold({
    super.key,
    required this.child,
    required this.onOpenDiagnostics,
    required this.onConfirm,
    required this.isConfirming,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统一身份认证'),
        centerTitle: true,
        actions: [
          DevOnly(
            child: IconButton(
              icon: const Icon(Icons.article_outlined),
              tooltip: '诊断信息',
              onPressed: onOpenDiagnostics,
            ),
          ),
          TextButton(
            onPressed: isConfirming ? null : onConfirm,
            child: Text(isConfirming ? '确认中' : '完成'),
          ),
        ],
      ),
      body: child,
    );
  }
}
