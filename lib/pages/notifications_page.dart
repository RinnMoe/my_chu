import 'package:flutter/material.dart';

import '../apps/portal_notices/portal_notices_page.dart';
import '../capabilities/east8_time.dart';
import '../services/auth_service.dart';
import '../services/demo_data_service.dart';
import '../services/in_app_notification_service.dart';
import 'alert_visuals.dart';
import 'app_sheet.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 通知中心：聚合各应用/能力贡献的应用内提醒，按账号持久化。
class NotificationsPage extends StatefulWidget {
  final int initialTabIndex;

  const NotificationsPage({super.key, this.initialTabIndex = 0});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<PortalNoticesPanelState> _noticesKey =
      GlobalKey<PortalNoticesPanelState>();
  String? _accountKey;
  List<InAppNotification> _items = const [];
  bool _loading = true;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, 1),
  );

  @override
  void initState() {
    super.initState();
    InAppNotificationService.revision.addListener(_reload);
    DemoDataService.revision.addListener(_reload);
    _tabController.addListener(_onTabChanged);
    _reload();
  }

  @override
  void dispose() {
    InAppNotificationService.revision.removeListener(_reload);
    DemoDataService.revision.removeListener(_reload);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final account = await AuthService.getCurrentAccount();
    final accountKey = account?.accountKey;
    final items =
        accountKey == null
            ? const <InAppNotification>[]
            : await InAppNotificationService.list(accountKey);
    if (!mounted) return;
    setState(() {
      _accountKey = accountKey;
      _items = items;
      _loading = false;
    });
  }

  Future<void> _openItem(InAppNotification item) async {
    final accountKey = _accountKey;
    if (accountKey == null) return;
    if (!item.read) {
      await InAppNotificationService.markRead(accountKey, item.id);
    }
    if (!mounted) return;
    final deeplink = item.deeplinkAppId;
    if (deeplink != null && deeplink.isNotEmpty) {
      if (await openTargetId(context, deeplink)) return;
    }
  }

  Future<void> _markAllRead() async {
    final accountKey = _accountKey;
    if (accountKey == null) return;
    await InAppNotificationService.markAllRead(accountKey);
  }

  int get _unreadCount => _items.where((item) => !item.read).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _buildMaterialPage(theme);
  }

  Widget _buildMaterialPage(ThemeData theme) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('通知中心'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: '提醒'), Tab(text: '公告')],
          ),
          actions: [
            if (_tabController.index == 1)
              IconButton(
                tooltip: '刷新通知公告',
                onPressed: () => _noticesKey.currentState?.refresh(),
                icon: const Icon(Icons.refresh),
              )
            else if (_unreadCount > 0)
              TextButton.icon(
                onPressed: _markAllRead,
                icon: const Icon(Icons.done_all_outlined, size: 18),
                label: const Text('全部已读'),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
      body: _buildMaterialTabView(theme),
    );
  }

  Widget _buildMaterialTabView(ThemeData theme) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildMaterialBody(theme),
        PortalNoticesPanel(key: _noticesKey),
      ],
    );
  }

  Widget _buildMaterialBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return _MaterialEmptyNotifications(theme: theme);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _items[index];
        return _MaterialNotificationCard(
          item: item,
          onTap: () => _openItem(item),
        );
      },
    );
  }
}

class _MaterialNotificationCard extends StatelessWidget {
  final InAppNotification item;
  final VoidCallback onTap;

  const _MaterialNotificationCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = !item.read;
    final severityColor = alertSeverityColor(context, item.severity);
    return Card(
      clipBehavior: Clip.antiAlias,
      color:
          unread && !item.resolved
              ? colors.surfaceContainerLowest
              : colors.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      unread
                          ? colors.secondaryContainer
                          : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  item.resolved
                      ? Icons.notifications_paused_outlined
                      : alertSeverityIcon(item.severity),
                  size: 22,
                  color:
                      unread && !item.resolved
                          ? severityColor
                          : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (item.body != null && item.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${item.source} · ${_relativeTime(item.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialEmptyNotifications extends StatelessWidget {
  final ThemeData theme;

  const _MaterialEmptyNotifications({required this.theme});

  @override
  Widget build(BuildContext context) {
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.notifications_none,
                size: 36,
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text('暂无通知', style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = east8Now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
