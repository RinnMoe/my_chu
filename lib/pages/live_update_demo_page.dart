import 'package:flutter/material.dart';

import '../capabilities/east8_time.dart';
import '../capabilities/live_update.dart';
import '../services/live_update_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class LiveUpdateDemoPage extends StatefulWidget {
  const LiveUpdateDemoPage({super.key});

  @override
  State<LiveUpdateDemoPage> createState() => _LiveUpdateDemoPageState();
}

class _LiveUpdateDemoPageState extends State<LiveUpdateDemoPage> {
  final _courseNameController = TextEditingController(text: 'Demo 课程');
  final _locationController = TextEditingController(text: 'WM3101');
  final _startOffsetController = TextEditingController(text: '10');
  final _endOffsetController = TextEditingController(text: '55');
  bool _working = false;
  String? _lastMessage;

  @override
  void dispose() {
    _courseNameController.dispose();
    _locationController.dispose();
    _startOffsetController.dispose();
    _endOffsetController.dispose();
    super.dispose();
  }

  Future<void> _trigger() async {
    final now = east8Now();
    final name = _courseNameController.text.trim();
    final location = _locationController.text.trim();
    final startOffset = int.tryParse(_startOffsetController.text.trim());
    final endOffset = int.tryParse(_endOffsetController.text.trim());
    if (startOffset == null || endOffset == null) {
      setState(() => _lastMessage = '请输入有效的分钟偏移');
      return;
    }
    final start = now.add(Duration(minutes: startOffset));
    final end = now.add(Duration(minutes: endOffset));
    if (!end.isAfter(start)) {
      setState(() => _lastMessage = '结束时间必须晚于开始时间');
      return;
    }

    final content = _contentFor(
      now: now,
      start: start,
      end: end,
      name: name.isEmpty ? 'Demo 课程' : name,
      location: location,
    );

    setState(() => _working = true);
    try {
      await LiveUpdateService.debugPostDemo(
        content,
        targetAppId: 'feature.academic.schedule',
      );
      if (!mounted) return;
      setState(() => _lastMessage = '已触发课前 Demo');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _working = true);
    try {
      await LiveUpdateService.debugClearDemo();
      if (!mounted) return;
      setState(() => _lastMessage = '已清除 Demo');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  LiveUpdateContent _contentFor({
    required DateTime now,
    required DateTime start,
    required DateTime end,
    required String name,
    required String location,
  }) {
    return LiveUpdateContent.active(
      render: LiveUpdateRender(
        title: name,
        body: [
          if (location.isNotEmpty) location,
          '${_timeText(start)}-${_timeText(end)}',
        ].join(' · '),
        shortCriticalText: truncateLiveUpdateChipText(location),
        trackerEmoji: '🎓',
        progress: 0,
        progressMax: 1,
        requestPromoted: true,
        ongoing: true,
      ),
      now: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = _buildBody(context, theme);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('系统实时动态 Demo')),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (!LiveUpdateService.isSupported) {
      return const Center(child: Text('当前平台不支持系统实时动态 Demo。'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('课前提示 Demo', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '仅模拟开课前的课程提示；触发后显示距离开课 10 分钟的实时动态。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _courseNameController,
          decoration: const InputDecoration(labelText: '课程名'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: '教室'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startOffsetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '开始偏移（分钟）'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _endOffsetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '结束偏移（分钟）'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _working ? null : _trigger,
                child: const Text('触发 Demo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _working ? null : _clear,
                child: const Text('清除 Demo'),
              ),
            ),
          ],
        ),
        if (_lastMessage case final message?) ...[
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  String _timeText(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}
