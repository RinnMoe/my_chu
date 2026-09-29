import 'dart:async';

import 'package:flutter/material.dart';

import '../services/demo_data_service.dart';
import '../services/live_update_service.dart';
import '../services/vivo_superx_demo_service.dart';
import 'live_update_demo_page.dart';
import 'vivo_superx_demo_page.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 数据 Demo 配置页。
///
/// 这里不重复渲染业务组件，只维护全局 Demo 总开关和参数。开启后，首页、
/// 课表卡片和通知中心会在各自原始位置直接读取
/// [DemoDataService] 的替换数据。
class DataDemoPage extends StatefulWidget {
  const DataDemoPage({super.key});

  @override
  State<DataDemoPage> createState() => _DataDemoPageState();
}

class _DataDemoPageState extends State<DataDemoPage> {
  void _pushDemoPage(Widget page) {
    unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
    );
  }

  DemoDataService get _service => DemoDataService.instance;

  DemoDataConfig get _config => _service.config;

  @override
  void initState() {
    super.initState();
    DemoDataService.revision.addListener(_onDemoChanged);
  }

  @override
  void dispose() {
    DemoDataService.revision.removeListener(_onDemoChanged);
    super.dispose();
  }

  void _onDemoChanged() {
    if (mounted) setState(() {});
  }

  void _update(DemoDataConfig config) {
    _service.updateConfig(config);
  }

  void _setEnabled(bool value) {
    _service.setEnabled(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final body = _buildBody(context, theme, muted);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('数据 Demo')),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, Color muted) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SwitchListTile(
                title: Text(
                  '应用 Demo 数据',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('开启后直接替换首页、课表卡片和通知中心的数据'),
                value: _service.enabled,
                onChanged: _setEnabled,
              ),
              if (_service.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Demo 数据只在当前进程内生效，关闭总开关或退出应用后恢复真实数据。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ConfigSection(
          title: '首页与课程',

          child: Column(
            children: [
              _ConfigSwitch(
                title: '假期中',
                value: _config.holiday,
                onChanged: (value) => _update(_config.copyWith(holiday: value)),
              ),
              _ConfigSwitch(
                title: '焦点加载失败',
                value: _config.focusError,
                onChanged:
                    (value) => _update(_config.copyWith(focusError: value)),
              ),
              _ConfigSlider(
                title: '焦点数量',
                subtitle: '生产约束最多 3 条',
                value: _config.focusCount.toDouble(),
                min: 0,
                max: 3,
                divisions: 3,
                label: '${_config.focusCount}',
                onChanged:
                    (value) =>
                        _update(_config.copyWith(focusCount: value.round())),
              ),
              _ConfigSlider(
                title: '常用应用数量',
                subtitle: '生产上限 8 项',
                value: _config.quickAppCount.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                label: '${_config.quickAppCount}',
                onChanged:
                    (value) =>
                        _update(_config.copyWith(quickAppCount: value.round())),
              ),
              _ConfigSlider(
                title: '课程数量',
                value: _config.courseCount.toDouble(),
                min: 0,
                max: 8,
                divisions: 8,
                label: '${_config.courseCount}',
                onChanged:
                    (value) =>
                        _update(_config.copyWith(courseCount: value.round())),
              ),
              _ConfigSwitch(
                title: '课表加载失败',
                value: _config.scheduleError,
                onChanged:
                    (value) => _update(_config.copyWith(scheduleError: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ConfigSection(
          title: '通知',

          child: Column(
            children: [
              _ConfigSwitch(
                title: '成绩更新提醒',
                value: _config.gradeNotification,
                onChanged:
                    (value) =>
                        _update(_config.copyWith(gradeNotification: value)),
              ),
              _ConfigSwitch(
                title: '余额不足提醒',
                value: _config.balanceNotification,
                onChanged:
                    (value) =>
                        _update(_config.copyWith(balanceNotification: value)),
              ),
              _ConfigSwitch(
                title: '课程实时动态',
                value: _config.liveUpdateNotification,
                onChanged:
                    (value) => _update(
                      _config.copyWith(liveUpdateNotification: value),
                    ),
              ),
              _ConfigSwitch(
                title: '系统横幅',
                value: _config.systemBanner,
                onChanged:
                    (value) => _update(_config.copyWith(systemBanner: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        if (LiveUpdateService.isSupported)
          OutlinedButton.icon(
            onPressed: () => _pushDemoPage(const LiveUpdateDemoPage()),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('打开实时动态 Demo'),
          ),
        if (LiveUpdateService.isSupported && VivoSuperXDemoService.isSupported)
          const SizedBox(height: 8),
        if (VivoSuperXDemoService.isSupported)
          OutlinedButton.icon(
            onPressed: () => _pushDemoPage(const VivoSuperXDemoPage()),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('打开 vivo 原子通知 Demo'),
          ),
      ],
    );
  }
}

class _ConfigSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _ConfigSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(title, style: labelStyle),
        ),
        const SizedBox(height: 8),
        Card(clipBehavior: Clip.antiAlias, child: child),
      ],
    );
  }
}

class _ConfigSwitch extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ConfigSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  const _ConfigSlider({
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: SizedBox(
        width: 150,
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
