import 'package:flutter/material.dart';

import '../../apps/app.dart';
import '../../apps/app_service.dart';
import '../../capabilities/dev_visibility.dart';
import '../../services/navigation_layout_service.dart';
import '../../services/navigation_tab_presentation.dart';
import '../../widgets/adaptive_navigation_layout_row.dart';
import '../../widgets/adaptive_settings.dart';
import '../../widgets/compact_badge.dart';

/// 底栏设置：启用、排序与应用首页的唯一设置入口。
///
/// 焦点与选项固定在两端，不参与重排或关闭；课表固定存在；其余内置功能
/// Tab 受 [NavigationLayoutService.maxAppTabs] 上限约束。点击任一行把该页面
/// 设为应用启动后的首屏，当前首屏在行内以标记显示，不再单独列一遍底栏。
class BottomBarSection extends StatefulWidget {
  const BottomBarSection({super.key});

  @override
  State<BottomBarSection> createState() => _BottomBarSectionState();
}

class _BottomBarSectionState extends State<BottomBarSection> {
  List<_BarRowItem> _middle = [];
  Set<String> _enabledAppIds = {};
  Set<String> _enabledHostIds = {};
  String _startKey = NavigationLayoutService.hostHomeKey;
  bool _loading = true;

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
    final layout = await NavigationLayoutService.read();
    final plugins = await AppService.getManagedApps();

    final eligible = <String, AppDefinition>{
      for (final plugin in plugins)
        if (!plugin.metadata.core &&
            plugin.metadata.showInNavigation &&
            (await AppService.getState(plugin.metadata.id)).installed)
          plugin.metadata.id: plugin,
    };

    final middle = <_BarRowItem>[];
    final seen = <String>{};
    final enabledAppIds = <String>{};
    final enabledHostIds = <String>{};
    for (final key in layout.order) {
      seen.add(key);
      if (key == NavigationLayoutService.hostAppsKey ||
          key == NavigationLayoutService.academicScheduleKey ||
          key == NavigationLayoutService.hostMapKey) {
        middle.add(_BarRowItem.host(key));
        enabledHostIds.add(key);
      } else if (eligible.containsKey(key)) {
        enabledAppIds.add(key);
        middle.add(_BarRowItem.plugin(eligible[key]!));
      }
    }
    if (!seen.contains(NavigationLayoutService.academicScheduleKey)) {
      final appsIndex = middle.indexWhere(
        (item) => item.key == NavigationLayoutService.hostAppsKey,
      );
      middle.insert(
        appsIndex >= 0 ? appsIndex + 1 : 0,
        const _BarRowItem.host(NavigationLayoutService.academicScheduleKey),
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
        const _BarRowItem.host(NavigationLayoutService.hostMapKey),
      );
    }
    for (final plugin in eligible.values) {
      if (!seen.contains(plugin.metadata.id)) {
        middle.add(_BarRowItem.plugin(plugin));
      }
    }

    if (!mounted) return;
    setState(() {
      _middle = middle;
      _enabledAppIds = enabledAppIds;
      _enabledHostIds = enabledHostIds;
      _startKey = NavigationLayoutService.resolveStartKey(
        layout,
        availableKeys: NavigationLayoutService.resolveTabKeys(layout),
      );
      _loading = false;
    });
  }

  /// 把该页面设为应用启动后的首屏；未启用的页面不能作为首屏。
  Future<void> _selectStart(String key) async {
    if (key == _startKey) return;
    setState(() => _startKey = key);
    await NavigationLayoutService.setStartKey(key);
  }

  Future<void> _move(int index, int delta) async {
    final to = index + delta;
    if (to < 0 || to >= _middle.length) return;
    final items = List<_BarRowItem>.from(_middle);
    final moved = items.removeAt(index);
    items.insert(to, moved);
    setState(() => _middle = items);
    await NavigationLayoutService.setOrder(
      // 只持久化已启用（宿主页 + 已开启的应用 Tab）的键，避免重排时把
      // 未启用的应用行误写入顺序。
      [
        for (final item in items)
          if (_isEnabled(item)) item.key,
      ],
    );
  }

  /// 开关宿主页面。目前只有地图可关闭，课表是强制项、没有开关。
  Future<void> _toggleHost(String hostKey, bool enabled) async {
    final layout = await NavigationLayoutService.read();
    final order = List<String>.from(layout.order);
    if (enabled) {
      if (!order.contains(hostKey)) {
        final scheduleIndex = order.indexOf(
          NavigationLayoutService.academicScheduleKey,
        );
        order.insert(
          scheduleIndex >= 0 ? scheduleIndex + 1 : order.length,
          hostKey,
        );
      }
    } else {
      order.remove(hostKey);
    }
    await NavigationLayoutService.setOrder(order);
    await _load();
  }

  Future<void> _toggleApp(AppDefinition plugin, bool enabled) async {
    final ok = await NavigationLayoutService.setAppEnabled(
      plugin.metadata.id,
      enabled,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('底栏最多显示 ${NavigationLayoutService.maxAppTabs} 个功能'),
        ),
      );
    }
    await _load();
  }

  bool _isEnabled(_BarRowItem item) {
    if (item.plugin == null) return _enabledHostIds.contains(item.key);
    return _enabledAppIds.contains(item.plugin!.metadata.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdaptiveSettingsSection(
        title: '底栏设置',
        footer: '点击某一行，设为应用启动后的首屏',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }
    return AdaptiveSettingsSection(
      title: '底栏设置',
      footer: '点击某一行，设为应用启动后的首屏',
      dividerIndent: 64,
      children: _buildRows(),
    );
  }

  List<Widget> _buildRows() {
    return [
      _fixedRow(
        NavigationLayoutService.hostHomeKey,
        const ValueKey('page-preferences-bar-home'),
      ),
      for (var i = 0; i < _middle.length; i++) _buildMiddleRow(i),
      _fixedRow(
        NavigationLayoutService.hostProfileKey,
        const ValueKey('page-preferences-bar-profile'),
      ),
    ];
  }

  Widget _fixedRow(String key, Key rowKey) {
    final presentation = NavigationTabPresentations.forKey(key);
    return AdaptiveNavigationLayoutRow(
      key: rowKey,
      icon: presentation?.icon ?? Icons.circle_outlined,
      title: presentation?.label ?? key,
      titleAccessory: _accessoryFor(key, requiresDev: false),
      onTap: () => _selectStart(key),
    );
  }

  Widget _buildMiddleRow(int index) {
    final item = _middle[index];
    final presentation = NavigationTabPresentations.forKey(item.key);
    final plugin = item.plugin;
    final isFirst = index == 0;
    final isLast = index == _middle.length - 1;
    final isMap = item.key == NavigationLayoutService.hostMapKey;
    final enabled = _isEnabled(item);

    return AdaptiveNavigationLayoutRow(
      key: ValueKey(item.key),
      icon: presentation?.icon ?? Icons.circle_outlined,
      title: presentation?.label ?? item.key,
      titleAccessory: _accessoryFor(
        item.key,
        requiresDev: plugin?.metadata.requiresDev ?? false,
      ),
      enabled: enabled,
      // 未启用的页面不在底栏里，不能作为启动首屏。
      onTap: enabled ? () => _selectStart(item.key) : null,
      onEnabledChanged:
          plugin != null
              ? (value) => _toggleApp(plugin, value)
              : isMap
              ? (value) => _toggleHost(item.key, value)
              : null,
      reorderable: true,
      onMoveUp: isFirst ? null : () => _move(index, -1),
      onMoveDown: isLast ? null : () => _move(index, 1),
    );
  }

  Widget? _accessoryFor(String key, {required bool requiresDev}) {
    final badges = <Widget>[
      if (requiresDev) const DevBadge(),
      if (key == _startKey) const CompactBadge(label: '首屏'),
    ];
    if (badges.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < badges.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          badges[index],
        ],
      ],
    );
  }
}

class _BarRowItem {
  final String key;
  final AppDefinition? plugin;

  const _BarRowItem.host(this.key) : plugin = null;
  _BarRowItem.plugin(AppDefinition this.plugin) : key = plugin.metadata.id;

  @override
  String toString() => plugin?.metadata.id ?? key;
}
