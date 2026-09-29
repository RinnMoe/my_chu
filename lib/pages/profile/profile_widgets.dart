import 'package:flutter/material.dart';

import '../../services/ip_status_service.dart';
import '../../widgets/adaptive_settings.dart';

class ProfileSection extends StatelessWidget {
  final String title;
  final Widget child;

  const ProfileSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class ProfileSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final VoidCallback onTap;

  const ProfileSettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailingValue: trailingValue,
      onTap: onTap,
    );
  }
}

class ProfileIdentityCard extends StatelessWidget {
  final bool loading;
  final bool loadFailed;
  final String? name;
  final String? uid;
  final String? identity;
  final CampusNetworkStatus? networkStatus;
  final bool networkLoading;
  final VoidCallback? onRetryAccount;
  final VoidCallback? onOpenNetworkDetails;

  const ProfileIdentityCard({
    super.key,
    required this.loading,
    required this.loadFailed,
    required this.name,
    required this.uid,
    this.identity,
    required this.networkStatus,
    required this.networkLoading,
    required this.onRetryAccount,
    required this.onOpenNetworkDetails,
  });

  @override
  Widget build(BuildContext context) {
    final identityCard = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _IdentityBody(this)),
          const SizedBox(width: 12),
          _NetworkStatusChip(
            status: networkStatus,
            loading: networkLoading,
            onPressed: onOpenNetworkDetails,
          ),
        ],
      ),
    );
    return Card(clipBehavior: Clip.antiAlias, child: identityCard);
  }
}

class _IdentityBody extends StatelessWidget {
  final ProfileIdentityCard card;

  const _IdentityBody(this.card);

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final titleStyle = materialTheme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final detailStyle = materialTheme.textTheme.bodySmall?.copyWith(
      color: materialTheme.colorScheme.onSurfaceVariant,
    );
    final retryWidget =
        card.onRetryAccount == null
            ? null
            : TextButton(
              onPressed: card.onRetryAccount,
              child: const Text('重试'),
            );
    if (card.loading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Skeleton(width: 160, height: 24),
          SizedBox(height: 8),
          _Skeleton(width: 112, height: 16),
        ],
      );
    }
    if (card.loadFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('账号信息暂不可用', style: materialTheme.textTheme.titleMedium),
          if (retryWidget != null) retryWidget,
        ],
      );
    }
    final accountLine = [
      if (card.uid?.trim().isNotEmpty ?? false) card.uid!.trim(),
      if (card.identity?.trim().isNotEmpty ?? false) card.identity!.trim(),
    ].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          card.name ?? '未登录',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (accountLine.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(accountLine, style: detailStyle),
        ],
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double width;
  final double height;

  const _Skeleton({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _NetworkStatusChip extends StatelessWidget {
  final CampusNetworkStatus? status;
  final bool loading;
  final VoidCallback? onPressed;

  const _NetworkStatusChip({
    required this.status,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 76,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final label =
        status?.inWhiteList == true
            ? '校园网'
            : status == null
            ? '网络状态不可用'
            : '校外网';

    return ActionChip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

class SignOutAction extends StatelessWidget {
  final VoidCallback onPressed;

  const SignOutAction({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.logout_outlined),
        label: const Text('退出登录'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

Future<void> showNetworkStatusSheet(
  BuildContext context, {
  required CampusNetworkStatus? status,
  required Future<CampusNetworkStatus?> Function() refresh,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _NetworkStatusSheet(status: status, refresh: refresh),
  );
}

class _NetworkStatusSheet extends StatefulWidget {
  final CampusNetworkStatus? status;
  final Future<CampusNetworkStatus?> Function() refresh;

  const _NetworkStatusSheet({required this.status, required this.refresh});

  @override
  State<_NetworkStatusSheet> createState() => _NetworkStatusSheetState();
}

class _NetworkStatusSheetState extends State<_NetworkStatusSheet> {
  CampusNetworkStatus? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final next = await widget.refresh();
    if (!mounted) return;
    setState(() {
      _status = next;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('网络环境', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    title: const Text('当前网络'),
                    trailing: Text(
                      _status?.inWhiteList == true
                          ? '校园网'
                          : _status == null
                          ? '不可用'
                          : '校外网',
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    dense: true,
                    title: const Text('本机 IP'),
                    trailing: Text(_status?.ip ?? '不可用'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon:
                    _loading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh),
                label: Text(_loading ? '检测中' : '重新检测'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
