import 'package:flutter/material.dart';

import 'network_self_service_models.dart';

class NetworkSelfServiceDashboard extends StatelessWidget {
  final NetworkSelfServiceOverview overview;
  final bool overviewLoading;
  final String? overviewError;
  final Future<void> Function() onRefreshOverview;

  const NetworkSelfServiceDashboard({
    super.key,
    required this.overview,
    required this.overviewLoading,
    required this.overviewError,
    required this.onRefreshOverview,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (overviewLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefreshOverview,
            child: _PageList(
              children: [
                if (overviewError != null) ...[
                  _StaleErrorBanner(
                    message: overviewError!,
                    onRetry: onRefreshOverview,
                  ),
                  const SizedBox(height: 12),
                ],
                const _SectionHeader(title: '套餐信息'),
                const SizedBox(height: 10),
                if (overview.packages.isEmpty)
                  const _EmptyCard(
                    icon: Icons.data_usage_outlined,
                    title: '暂无套餐数据',
                    message: '服务没有返回可展示的套餐信息。',
                  )
                else
                  ...overview.packages.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PackageCard(package: item),
                    ),
                  ),
                const SizedBox(height: 8),
                _SectionHeader(
                  title: '在线设备',
                  subtitle:
                      overview.onlineSessions.isEmpty
                          ? '当前没有在线会话'
                          : '${overview.onlineSessions.length} 台设备在线',
                ),
                const SizedBox(height: 10),
                if (overview.onlineSessions.isEmpty)
                  const _EmptyCard(
                    icon: Icons.devices_outlined,
                    title: '没有在线设备',
                    message: '新会话建立后会显示 IP、MAC 与上线时间。',
                  )
                else
                  ...overview.onlineSessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SessionCard(session: session),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PageList extends StatelessWidget {
  final List<Widget> children;

  const _PageList({required this.children});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
    children: [
      Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 3),
        Text(
          subtitle!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

class _PackageCard extends StatelessWidget {
  final NetworkPackageUsage package;

  const _PackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _display(package.packageName),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '已用流量',
                    value: _display(package.usedTraffic),
                    color: scheme.primary,
                  ),
                ),
                Container(width: 1, height: 42, color: scheme.outlineVariant),
                Expanded(
                  child: _Metric(
                    label: '套餐余额',
                    value: _display(package.balance),
                    color: scheme.secondary,
                  ),
                ),
                Container(width: 1, height: 42, color: scheme.outlineVariant),
                Expanded(
                  child: _Metric(
                    label: '结算日期',
                    value: _display(package.settlementDate),
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _SessionCard extends StatelessWidget {
  final NetworkOnlineSession session;

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            child: const Icon(Icons.laptop_chromebook_outlined),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _display(session.ipAddress),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_display(session.macAddress)),
                const SizedBox(height: 8),
                Text(
                  '${_display(session.onlineAt)} · ${_display(session.packageName)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _StaleErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _StaleErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '显示的是上次成功数据：$message',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

String _display(String value) => value.isEmpty ? '暂无' : value;
