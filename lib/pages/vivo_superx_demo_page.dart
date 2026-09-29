import 'package:flutter/material.dart';

import '../capabilities/east8_time.dart';
import '../services/host_permission_service.dart';
import '../services/vivo_superx_demo_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

enum _VivoDemoPhase { before, during, after, afterNoNext, nextDay, unavailable }

class VivoSuperXDemoPage extends StatefulWidget {
  const VivoSuperXDemoPage({super.key});

  @override
  State<VivoSuperXDemoPage> createState() => _VivoSuperXDemoPageState();
}

class _VivoSuperXDemoPageState extends State<VivoSuperXDemoPage> {
  _VivoDemoPhase _phase = _VivoDemoPhase.during;
  final _courseNameController = TextEditingController(text: 'Demo 课程');
  final _locationController = TextEditingController(text: 'WM3101');
  final _startOffsetController = TextEditingController(text: '-10');
  final _endOffsetController = TextEditingController(text: '20');
  VivoSuperXDemoStatus? _status;
  bool _working = false;
  String? _lastMessage;
  int _changedRecord = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _courseNameController.dispose();
    _locationController.dispose();
    _startOffsetController.dispose();
    _endOffsetController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await VivoSuperXDemoService.status();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = const VivoSuperXDemoStatus());
    }
  }

  void _selectPhase(_VivoDemoPhase phase) {
    setState(() {
      _phase = phase;
      switch (phase) {
        case _VivoDemoPhase.before:
          _startOffsetController.text = '10';
          _endOffsetController.text = '55';
        case _VivoDemoPhase.during:
          _startOffsetController.text = '-10';
          _endOffsetController.text = '20';
        case _VivoDemoPhase.after:
        case _VivoDemoPhase.afterNoNext:
        case _VivoDemoPhase.nextDay:
          _startOffsetController.text = '-40';
          _endOffsetController.text = '-10';
        case _VivoDemoPhase.unavailable:
          break;
      }
      _lastMessage = null;
    });
  }

  _DemoInput? _readInputs() {
    final now = east8Now();
    final startOffset = int.tryParse(_startOffsetController.text.trim());
    final endOffset = int.tryParse(_endOffsetController.text.trim());
    if (startOffset == null || endOffset == null) {
      _setMessage('请输入有效的分钟偏移');
      return null;
    }
    final start = now.add(Duration(minutes: startOffset));
    final end = now.add(Duration(minutes: endOffset));
    if (!end.isAfter(start)) {
      _setMessage('结束时间必须晚于开始时间');
      return null;
    }
    final name = _courseNameController.text.trim();
    return _DemoInput(
      now: now,
      start: start,
      end: end,
      name: name.isEmpty ? 'Demo 课程' : name,
      location: _locationController.text.trim(),
    );
  }

  Future<void> _create() async {
    final input = _readInputs();
    if (input == null) return;
    final permission =
        await hostPermissionService.requestNotificationPermission();
    if (!mounted) return;
    if (!permission.granted) {
      _setMessage('未获得通知权限');
      return;
    }
    final render = _renderFor(input);
    setState(() {
      _working = true;
      _changedRecord = 0;
      _lastMessage = null;
    });
    try {
      await VivoSuperXDemoService.post(_payloadFor(0, render));
      _changedRecord = 1;
      if (!mounted) return;
      setState(() => _lastMessage = '已创建原子通知');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _update() async {
    final input = _readInputs();
    if (input == null) return;
    final render = _renderFor(input);
    setState(() {
      _working = true;
      _lastMessage = null;
    });
    try {
      await VivoSuperXDemoService.post(_payloadFor(1, render));
      _changedRecord++;
      if (!mounted) return;
      setState(() => _lastMessage = '已更新原子通知');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _end() async {
    final input = _readInputs();
    if (input == null) return;
    final render = _renderFor(input);
    setState(() {
      _working = true;
      _lastMessage = null;
    });
    try {
      await VivoSuperXDemoService.post(_payloadFor(2, render));
      _changedRecord++;
      if (!mounted) return;
      setState(() => _lastMessage = '已结束原子通知');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _working = true;
      _lastMessage = null;
    });
    try {
      await VivoSuperXDemoService.cancel();
      _changedRecord = 0;
      if (!mounted) return;
      setState(() => _lastMessage = '已取消原子通知');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  VivoSuperXDemoPayload _payloadFor(int operation, _DemoRender render) {
    return VivoSuperXDemoPayload(
      operation: operation,
      title: render.title,
      content: render.body,
      shortText: render.shortText.isEmpty ? render.title : render.shortText,
      progressPercent: _progressPercent(render),
      changedRecord: _changedRecord,
      keepDuration: operation == 2 ? 30 : 0,
    );
  }

  int _progressPercent(_DemoRender render) {
    if (render.progressMax <= 0) return 0;
    final percent = render.progress * 100 ~/ render.progressMax;
    return percent.clamp(0, 100).toInt();
  }

  _DemoRender _renderFor(_DemoInput input) {
    return switch (_phase) {
      _VivoDemoPhase.before => _DemoRender(
        title: '下节课 · ${input.name}',
        body: [
          if (input.location.isNotEmpty) input.location,
          '${_timeText(input.start)}-${_timeText(input.end)}',
        ].join(' · '),
        shortText: '${_timeText(input.start)} 上课',
        progress: 0,
        progressMax: 1,
      ),
      _VivoDemoPhase.during => _DemoRender(
        title: '正在上课 · ${input.name}',
        body: [
          if (input.location.isNotEmpty) input.location,
          '${_timeText(input.end)} 下课',
        ].join(' · '),
        shortText: '${_timeText(input.end)} 下课',
        progress:
            input.now.difference(input.start).inMinutes.clamp(0, 60).toInt(),
        progressMax: 60,
      ),
      _VivoDemoPhase.after => _afterRender(input),
      _VivoDemoPhase.afterNoNext => const _DemoRender(
        title: '今日课程结束',
        body: '今天没有更多课程',
        shortText: '课程结束',
        progress: 1,
        progressMax: 1,
      ),
      _VivoDemoPhase.nextDay => _DemoRender(
        title: '今日课程结束',
        body: [
          '下节课 明天 08:30',
          if (input.location.isNotEmpty) input.location,
        ].join(' · '),
        shortText: '明天 08:30',
        progress: 1,
        progressMax: 1,
      ),
      _VivoDemoPhase.unavailable => const _DemoRender(
        title: '课程实时动态',
        body: '暂时无法获取课程',
        shortText: '无法获取课程',
        progress: 0,
        progressMax: 0,
      ),
    };
  }

  _DemoRender _afterRender(_DemoInput input) {
    final nextStart = input.now.add(const Duration(minutes: 35));
    return _DemoRender(
      title: '下节课 · 下一门 Demo 课',
      body: [
        if (input.location.isNotEmpty) input.location,
        '${_timeText(nextStart)} 上课',
      ].join(' · '),
      shortText: _timeText(nextStart),
      progress: 1,
      progressMax: 1,
    );
  }

  void _setMessage(String message) {
    if (mounted) setState(() => _lastMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('vivo 原子通知 Demo')),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (false || !VivoSuperXDemoService.isSupported) {
      return const Center(child: Text('此开发 Demo 仅在 Android 上可用。'));
    }
    final theme = Theme.of(context);
    final updateEnabled = _changedRecord > 0 && !_working;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('演示阶段', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final phase in _VivoDemoPhase.values)
              ChoiceChip(
                label: Text(_phaseLabel(phase)),
                selected: _phase == phase,
                onSelected: (_) => _selectPhase(phase),
              ),
          ],
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
                onPressed: _working ? null : _create,
                child: const Text('创建原子通知'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: updateEnabled ? _update : null,
                child: const Text('更新原子通知'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: updateEnabled ? _end : null,
                child: const Text('结束原子通知'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _working ? null : _cancel,
                child: const Text('直接取消'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _statusText(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_lastMessage case final message?) ...[
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  String _statusText() {
    final status = _status;
    if (status == null) return '设备支持：检查中';
    return '设备支持：${status.supportCustomFun ? '是' : '否'} · '
        '场景开关：${status.sceneEnabled ? '开' : '关'}';
  }

  String _phaseLabel(_VivoDemoPhase phase) {
    return switch (phase) {
      _VivoDemoPhase.before => '课前',
      _VivoDemoPhase.during => '上课中',
      _VivoDemoPhase.after => '下课后有下节',
      _VivoDemoPhase.afterNoNext => '下课后无课',
      _VivoDemoPhase.nextDay => '次日首课',
      _VivoDemoPhase.unavailable => '不可用',
    };
  }

  String _timeText(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}

class _DemoInput {
  final DateTime now;
  final DateTime start;
  final DateTime end;
  final String name;
  final String location;

  const _DemoInput({
    required this.now,
    required this.start,
    required this.end,
    required this.name,
    required this.location,
  });
}

class _DemoRender {
  final String title;
  final String body;
  final String shortText;
  final int progress;
  final int progressMax;

  const _DemoRender({
    required this.title,
    required this.body,
    required this.shortText,
    required this.progress,
    required this.progressMax,
  });
}
