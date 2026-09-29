import 'package:flutter/material.dart';

import '../services/auth_lifecycle_service.dart';

class AuthRecoveryPage extends StatelessWidget {
  final AuthLifecycleResult result;
  final VoidCallback onRetry;
  final VoidCallback onManualLogin;
  final VoidCallback onClearAccount;

  const AuthRecoveryPage({
    super.key,
    required this.result,
    required this.onRetry,
    required this.onManualLogin,
    required this.onClearAccount,
  });

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final retryable = result.status == AuthLifecycleStatus.retryableFailure;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    retryable ? Icons.sync_problem_outlined : Icons.lock_clock,
                    size: 48,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    retryable ? '正在恢复登录状态' : '需要重新登录',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (retryable)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: onManualLogin,
                      icon: const Icon(Icons.login),
                      label: const Text('手动登录'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: retryable ? onManualLogin : onRetry,
                    child: Text(retryable ? '改用手动登录' : '重试自动恢复'),
                  ),
                  TextButton(
                    onPressed: onClearAccount,
                    child: const Text('清除本地账号'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
