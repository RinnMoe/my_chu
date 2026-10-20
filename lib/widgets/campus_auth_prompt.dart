import 'package:flutter/material.dart';
import '../capabilities/host_login.dart';
import '../services/host_auth_coordinator.dart';
import '../services/host_auth_state.dart';

/// A content empty state, rather than navigation chrome.
class CampusAuthPrompt extends StatelessWidget {
  const CampusAuthPrompt({
    super.key,
    this.title = '校园数据',
    this.icon = Icons.school_outlined,
    this.compact = false,
  });
  final String title;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: HostAuthState.snapshot,
    builder: (context, state, _) {
      if (state.status == HostAuthStatus.available) {
        return const SizedBox.shrink();
      }
      final storageError = state.status == HostAuthStatus.storageError;
      final theme = Theme.of(context);
      final description = storageError ? '账号暂时无法读取，可重试后继续。' : '登录校园账号后同步$title';
      void activate() {
        if (storageError) {
          HostAuthCoordinator.retry();
        } else {
          HostLogin.open(context);
        }
      }

      if (compact) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(description, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: activate,
                child: Text(storageError ? '重试' : '登录'),
              ),
            ],
          ),
        );
      }
      final content = Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  storageError ? Icons.manage_accounts_outlined : icon,
                  size: 40,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                storageError ? '账号暂时不可用' : '查看$title',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: activate,
                child: Text(storageError ? '重试' : '登录校园账号'),
              ),
            ],
          ),
        ),
      );
      return SafeArea(
        child: LayoutBuilder(
          builder:
              (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : 0,
                  ),
                  child: Center(child: content),
                ),
              ),
        ),
      );
    },
  );
}

/// Confirmed authentication failures occupy their own space below the content.
/// A failed identity probe does not establish that the device is offline.
class CampusAuthStatusOverlay extends StatelessWidget {
  const CampusAuthStatusOverlay({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: HostAuthState.snapshot,
    child: child,
    builder: (context, state, child) {
      final show =
          state.accountKey != null &&
          state.status == HostAuthStatus.loginRequired;
      final theme = Theme.of(context);
      final banner = SafeArea(
        top: false,
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('登录已失效，已保留本地数据')),
                TextButton(
                  onPressed: () => HostLogin.open(context),
                  child: const Text('重新登录'),
                ),
              ],
            ),
          ),
        ),
      );
      return LayoutBuilder(
        builder:
            (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (constraints.hasBoundedHeight)
                  Expanded(child: child!)
                else
                  child!,
                if (show) banner,
              ],
            ),
      );
    },
  );
}
