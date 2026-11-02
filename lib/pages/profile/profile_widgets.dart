import 'package:flutter/material.dart';

import '../../services/ip_status_service.dart';
import '../../widgets/adaptive_settings.dart';

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

/// 账号分组首行：身份信息与当前网络环境。
///
/// 身份卡并入“账号”分组后不再单独占一张卡片，`ListTile` 的分栏与相邻设置项
/// 对齐；网络状态作为尾随控件，点开同一个网络详情面板。
class ProfileIdentityRow extends StatelessWidget {
  final bool loading;
  final bool loadFailed;
  final String? name;
  final String? uid;
  final String? identity;
  final CampusNetworkStatus? networkStatus;
  final bool networkLoading;
  final VoidCallback? onRetryAccount;
  final VoidCallback? onOpenNetworkDetails;

  const ProfileIdentityRow({
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
    final materialTheme = Theme.of(context);
    final titleStyle = materialTheme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final detailStyle = materialTheme.textTheme.bodySmall?.copyWith(
      color: materialTheme.colorScheme.onSurfaceVariant,
    );
    final retryWidget =
        onRetryAccount == null
            ? null
            : TextButton(onPressed: onRetryAccount, child: const Text('重试'));
    if (loading) {
      return ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: const _Skeleton(width: 160, height: 18),
        subtitle: const _Skeleton(width: 112, height: 14),
        trailing: _NetworkStatusChip(
          status: networkStatus,
          loading: networkLoading,
          onPressed: onOpenNetworkDetails,
        ),
      );
    }
    if (loadFailed) {
      return ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: const Text('账号信息暂不可用'),
        trailing: retryWidget,
      );
    }
    final accountLine = [
      if (uid?.trim().isNotEmpty ?? false) uid!.trim(),
      if (identity?.trim().isNotEmpty ?? false) identity!.trim(),
    ].join(' ');
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: Text(
        name ?? '未登录',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
      subtitle:
          accountLine.isEmpty ? null : Text(accountLine, style: detailStyle),
      trailing: _NetworkStatusChip(
        status: networkStatus,
        loading: networkLoading,
        onPressed: onOpenNetworkDetails,
      ),
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
  final VoidCallback? onPressed;

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
