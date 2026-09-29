import 'package:flutter/material.dart';

import '../apps/portal_personal/portal_personal_page.dart';
import '../capabilities/skeleton_block.dart';
import '../services/auth_service.dart';
import '../services/credential_sync_service.dart';
import '../services/home_focus_service.dart';
import '../services/in_app_notification_service.dart';
import '../services/platform_environment.dart';
import 'app_sheet.dart';
import 'notifications_page.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 首页 Focus：统一渲染考试、待办、动态提醒、公告与同步状态，最多 3 条。
class HomeFocusSection extends StatelessWidget {
  final HomeFocusSnapshot? snapshot;
  final CredentialSyncState? credentialSyncState;
  final bool loading;
  final VoidCallback? onRetry;

  const HomeFocusSection({
    super.key,
    this.snapshot,
    this.credentialSyncState,
    this.loading = false,
    this.onRetry,
  });

  Route<void> _notificationsRoute(BuildContext context, Widget page) {
    return MaterialPageRoute<void>(builder: (_) => page);
  }

  Future<void> _openItem(BuildContext context, HomeFocusItem item) async {
    final destination = item.destination;
    if (destination is HomeFocusAnnouncementDestination) {
      await Navigator.push(
        context,
        _notificationsRoute(
          context,
          _AppAnnouncementPage(title: item.title, content: destination.content),
        ),
      );
      return;
    }
    if (destination is HomeFocusAppDestination) {
      final notificationId = destination.notificationId;
      if (notificationId != null) {
        final account = await AuthService.getCurrentAccount();
        final accountKey = account?.accountKey;
        if (accountKey != null) {
          await InAppNotificationService.markRead(accountKey, notificationId);
        }
      }
      if (!context.mounted) return;
      final appId = destination.appId;
      if (appId != null && appId.isNotEmpty) {
        final pageBuilder =
            item.kind == HomeFocusKind.todo &&
                    appId == 'feature.portal.personal'
                ? (BuildContext _) =>
                    const PortalPersonalPage(initialTabIndex: 1)
                : null;
        if (await openTargetId(context, appId, appPageBuilder: pageBuilder)) {
          return;
        }
      }
      if (!context.mounted) return;
      await Navigator.push(
        context,
        _notificationsRoute(context, const NotificationsPage()),
      );
      return;
    }

    if (destination is HomeFocusNoticeDestination) {
      // 公告 Focus 只表达打开通知中心公告 Tab，不直达单条公告详情。
      await Navigator.push(
        context,
        _notificationsRoute(
          context,
          const NotificationsPage(initialTabIndex: 1),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      _notificationsRoute(context, const NotificationsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final environment = PlatformEnvironment.fromContext(context);
    final denseTablet =
        environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded;

    final syncState = credentialSyncState;
    final showCredentialSync =
        syncState != null && (syncState.isSyncing || syncState.hasError);
    if (loading && snapshot == null && !showCredentialSync) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SkeletonBlock(width: 40, height: 40, radius: 12),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock(width: 160, height: 14),
                  SizedBox(height: 6),
                  SkeletonBlock(width: 220, height: 12),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final items = snapshot?.items ?? const <HomeFocusItem>[];
    final hasError = snapshot?.hasError == true;
    if (items.isEmpty && !hasError && !showCredentialSync) {
      return const SizedBox.shrink();
    }

    if (items.isEmpty && hasError && !showCredentialSync) {
      return _FocusErrorState(onRetry: onRetry, loading: loading);
    }

    final materialTheme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '焦点',
                  style: materialTheme.textTheme.titleSmall?.copyWith(
                    color: materialTheme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasError)
                _FocusRefreshError(onRetry: onRetry, loading: loading),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          container: true,
          label: '首页焦点',
          child: Column(
            children: [
              if (showCredentialSync) ...[
                _CredentialSyncPanel(state: syncState),
                if (items.isNotEmpty || hasError) const SizedBox(height: 8),
              ],
              if (items.isNotEmpty)
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _FocusRow(
                    item: items[i],
                    onTap: () => _openItem(context, items[i]),

                    dense: denseTablet,
                  ),
                ]
              else if (hasError)
                _FocusErrorState(onRetry: onRetry, loading: loading),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppAnnouncementPage extends StatelessWidget {
  final String title;
  final String content;

  const _AppAnnouncementPage({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SelectableText(content.trim().isEmpty ? '暂无内容' : content),
        ],
      ),
    );

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('应用公告')),
      ),
      body: body,
    );
  }
}

class _CredentialSyncPanel extends StatelessWidget {
  final CredentialSyncState state;

  const _CredentialSyncPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final progress =
        state.totalSteps == 0 ? null : state.completedSteps / state.totalSteps;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      label: state.message,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              state.hasError
                  ? colors.errorContainer
                  : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (state.isSyncing)
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.onSecondaryContainer,
                ),
              )
            else
              Icon(Icons.info_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.isSyncing ? '正在同步应用凭证' : '部分凭证尚未同步',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color:
                          state.hasError
                              ? colors.onErrorContainer
                              : colors.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          state.hasError
                              ? colors.onErrorContainer
                              : colors.onSecondaryContainer,
                    ),
                  ),
                  if (state.isSyncing) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${state.completedSteps} / ${state.totalSteps} 项已检查',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  final bool loading;

  const _FocusErrorState({required this.onRetry, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.sync_problem_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '焦点暂时无法加载',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: loading ? null : onRetry,
            child: Text(loading ? '重试中…' : '重试'),
          ),
        ],
      ),
    );
  }
}

class _FocusRefreshError extends StatelessWidget {
  final VoidCallback? onRetry;
  final bool loading;

  const _FocusRefreshError({required this.onRetry, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '更新失败',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: loading ? null : onRetry,
          child: Text(loading ? '重试中…' : '重试'),
        ),
      ],
    );
  }
}

class _FocusRow extends StatelessWidget {
  final HomeFocusItem item;
  final VoidCallback onTap;

  final bool dense;

  const _FocusRow({
    required this.item,
    required this.onTap,

    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final verticalPadding = dense ? 8.0 : 10.0;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _priorityColor(colors, item.priority);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_kindIcon(item.kind), size: 22, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (item.tertiaryText?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.tertiaryText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(HomeFocusKind kind) {
    return switch (kind) {
      HomeFocusKind.todo => Icons.assignment_outlined,
      HomeFocusKind.exam => Icons.event_available_outlined,
      HomeFocusKind.campusNotice => Icons.campaign_outlined,
      HomeFocusKind.appAnnouncement => Icons.campaign_outlined,
      HomeFocusKind.dataChange => Icons.sync_alt_outlined,
      HomeFocusKind.serviceAlert => Icons.warning_amber_outlined,
      HomeFocusKind.importantReminder => Icons.notifications_active_outlined,
      HomeFocusKind.publicHoliday => Icons.event_note_outlined,
    };
  }

  Color _priorityColor(ColorScheme colors, HomeFocusPriority priority) {
    return switch (priority) {
      HomeFocusPriority.p0 => colors.error,
      HomeFocusPriority.p1 => colors.primary,
      HomeFocusPriority.p2 => colors.tertiary,
      HomeFocusPriority.p3 => colors.onSurfaceVariant,
    };
  }
}
