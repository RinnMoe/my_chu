import 'package:flutter/material.dart';

import '../apps/app.dart';
import '../apps/app_service.dart';
import '../capabilities/dev_visibility.dart';
import '../services/auth_service.dart';
import '../services/navigation_layout_service.dart';
import '../widgets/adaptive_navigation_layout_row.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 底栏管理页（独立打开时使用，带标题栏）。
class NavigationLayoutPage extends StatelessWidget {
  final String? accountKey;

  const NavigationLayoutPage({super.key, this.accountKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('底栏管理')),
      ),
      body: NavigationLayoutPanel(accountKey: accountKey),
    );
  }
}

/// 底栏管理内容面板：供独立页与“页面管理”Tab 复用。
class NavigationLayoutPanel extends StatefulWidget {
  final String? accountKey;

  const NavigationLayoutPanel({super.key, this.accountKey});

  @override
  State<NavigationLayoutPanel> createState() => _NavigationLayoutPanelState();
}

class _NavigationLayoutPanelState extends State<NavigationLayoutPanel>
    with AutomaticKeepAliveClientMixin {
  String _accountKey = 'anonymous';
  List<_NavRowItem> _middle = [];
  Set<String> _enabledAppIds = {};
  Set<String> _enabledHostIds = {};
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    NavigationLayoutService.revision.addListener(_load);
    appCatalogNotifier.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    NavigationLayoutService.revision.removeListener(_load);
    appCatalogNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final accountKey =
        widget.accountKey ??
        (await AuthService.getCurrentAccount())?.accountKey ??
        'anonymous';
    final layout = await NavigationLayoutService.read(accountKey);
    final plugins = await AppService.getManagedApps();

    final eligible = <String, AppDefinition>{
      for (final plugin in plugins)
        if (!plugin.metadata.core &&
            plugin.metadata.showInNavigation &&
            (await AppService.getState(plugin.metadata.id)).installed)
          plugin.metadata.id: plugin,
    };

    final middle = <_NavRowItem>[];
    final seen = <String>{};
    final enabledAppIds = <String>{};
    final enabledHostIds = <String>{};
    for (final key in layout.order) {
      seen.add(key);
      if (key == NavigationLayoutService.hostAppsKey ||
          key == NavigationLayoutService.academicScheduleKey ||
          key == NavigationLayoutService.hostMapKey) {
        middle.add(_NavRowItem.host(key));
        enabledHostIds.add(key);
      } else if (eligible.containsKey(key)) {
        enabledAppIds.add(key);
        middle.add(_NavRowItem.plugin(eligible[key]!));
      }
    }
    if (!seen.contains(NavigationLayoutService.academicScheduleKey)) {
      final appsIndex = middle.indexWhere(
        (item) => item.key == NavigationLayoutService.hostAppsKey,
      );
      middle.insert(
        appsIndex >= 0 ? appsIndex + 1 : 0,
        const _NavRowItem.host(NavigationLayoutService.academicScheduleKey),
      );
      enabledHostIds.add(NavigationLayoutService.academicScheduleKey);
    }
    if (!seen.contains(NavigationLayoutService.hostMapKey)) {
      final scheduleIndex = middle.indexWhere(
        (item) => item.key == NavigationLayoutService.academicScheduleKey,
      );
      final appsIndex = middle.indexWhere(
        (item) => item.key == NavigationLayoutService.hostAppsKey,
      );
      final insertAfter = scheduleIndex >= 0 ? scheduleIndex : appsIndex;
      middle.insert(
        insertAfter >= 0 ? insertAfter + 1 : 0,
        const _NavRowItem.host(NavigationLayoutService.hostMapKey),
      );
    }
    for (final plugin in eligible.values) {
      if (!seen.contains(plugin.metadata.id)) {
        middle.add(_NavRowItem.plugin(plugin));
      }
    }

    if (!mounted) return;
    setState(() {
      _accountKey = accountKey;
      _middle = middle;
      _enabledAppIds = enabledAppIds;
      _enabledHostIds = enabledHostIds;
      _loading = false;
    });
  }

  Future<void> _move(int index, int delta) async {
    final to = index + delta;
    if (to < 0 || to >= _middle.length) return;
    final items = List<_NavRowItem>.from(_middle);
    final moved = items.removeAt(index);
    items.insert(to, moved);
    setState(() => _middle = items);
    await NavigationLayoutService.setOrder(
      _accountKey,
      // 只持久化已启用（宿主页 + 已开启的应用 Tab）的键，避免重排时把
      // 未启用的应用行误写入顺序。
      [
        for (final item in items)
          if (_isEnabled(item)) item.key,
      ],
    );
  }

  Future<void> _toggleHost(String hostKey, bool enabled) async {
    final layout = await NavigationLayoutService.read(_accountKey);
    final order = List<String>.from(layout.order);
    if (enabled) {
      if (!order.contains(hostKey)) {
        final appsIdx = order.indexOf(NavigationLayoutService.hostAppsKey);
        final scheduleIdx = order.indexOf(
          NavigationLayoutService.academicScheduleKey,
        );
        final insertAfter =
            hostKey == NavigationLayoutService.academicScheduleKey
                ? appsIdx
                : scheduleIdx >= 0
                ? scheduleIdx
                : appsIdx;
        order.insert(insertAfter >= 0 ? insertAfter + 1 : 0, hostKey);
      }
    } else {
      order.remove(hostKey);
    }
    await NavigationLayoutService.setOrder(_accountKey, order);
    await _load();
  }

  Future<void> _toggleApp(AppDefinition plugin, bool enabled) async {
    final ok = await NavigationLayoutService.setAppEnabled(
      _accountKey,
      plugin.metadata.id,
      enabled,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('底栏最多显示 ${NavigationLayoutService.maxAppTabs} 个功能 Tab'),
        ),
      );
    }
    await _load();
  }

  bool _isEnabled(_NavRowItem item) {
    if (item.plugin == null) return _enabledHostIds.contains(item.key);
    return _enabledAppIds.contains(item.plugin!.metadata.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final enabled = _middle.any((item) => item.plugin != null);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: _buildNavigationRows()),
        ),
        if (!enabled) ...[
          const SizedBox(height: 12),
          Text(
            '暂无可添加的功能。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildNavigationRows() {
    final rows = <Widget>[
      const AdaptiveNavigationLayoutRow(
        key: ValueKey('home'),
        icon: Icons.home_outlined,
        title: '首页',
        enabled: true,
      ),
      for (var i = 0; i < _middle.length; i++) _buildMiddleRow(i),
      const AdaptiveNavigationLayoutRow(
        key: ValueKey('profile'),
        icon: Icons.person_outline,
        title: '我的',
        enabled: true,
      ),
    ];

    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 1, indent: 64),
        rows[i],
      ],
    ];
  }

  Widget _buildMiddleRow(int index) {
    final item = _middle[index];
    final plugin = item.plugin;
    final isFirst = index == 0;
    final isLast = index == _middle.length - 1;

    if (plugin == null) {
      final isMap = item.key == NavigationLayoutService.hostMapKey;
      final isSchedule =
          item.key == NavigationLayoutService.academicScheduleKey;
      return AdaptiveNavigationLayoutRow(
        key: ValueKey(item.key),
        icon:
            item.key == NavigationLayoutService.hostAppsKey
                ? Icons.apps_outlined
                : isSchedule
                ? Icons.calendar_month_outlined
                : Icons.map_outlined,
        title:
            item.key == NavigationLayoutService.hostAppsKey
                ? '功能'
                : isSchedule
                ? '课表'
                : '地图',
        enabled: _isEnabled(item),
        onEnabledChanged:
            isMap ? (value) => _toggleHost(item.key, value) : null,
        reorderable: true,
        onMoveUp: isFirst ? null : () => _move(index, -1),
        onMoveDown: isLast ? null : () => _move(index, 1),
      );
    }

    final metadata = plugin.metadata;
    return AdaptiveNavigationLayoutRow(
      key: ValueKey(plugin.metadata.id),
      icon: metadata.icon,
      title: metadata.navigationLabel ?? metadata.name,
      subtitle: metadata.description,
      titleAccessory: metadata.requiresDev ? const DevBadge() : null,
      enabled: _isEnabled(item),
      onEnabledChanged: (value) => _toggleApp(plugin, value),
      reorderable: true,
      onMoveUp: isFirst ? null : () => _move(index, -1),
      onMoveDown: isLast ? null : () => _move(index, 1),
    );
  }
}

class _NavRowItem {
  final String key;
  final AppDefinition? plugin;

  const _NavRowItem.host(this.key) : plugin = null;
  _NavRowItem.plugin(AppDefinition this.plugin) : key = plugin.metadata.id;

  @override
  String toString() => plugin?.metadata.id ?? key;
}
