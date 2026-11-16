import '../../widgets/adaptive_feedback.dart';
import 'package:flutter/material.dart';

class PortalNoticeFullPageError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const PortalNoticeFullPageError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveErrorState(title: message, onRetry: onRetry);
  }
}
