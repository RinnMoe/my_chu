import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/course_live_activity_service.dart';
import '../services/platform_compatibility_service.dart';
import '../widgets/apple_window_controls.dart';

class CourseLiveTestPage extends StatefulWidget {
  const CourseLiveTestPage({super.key});

  @override
  State<CourseLiveTestPage> createState() => _CourseLiveTestPageState();
}

class _CourseLiveTestPageState extends State<CourseLiveTestPage> {
  bool _busy = false;
  String _message = '虚拟课程不写入课表。测试会暂时代替真实课前通知，结束测试后恢复。';

  Future<void> _run({bool? delayed, bool ongoing = false}) async {
    setState(() => _busy = true);
    try {
      if (delayed == null) {
        await CourseLiveActivityService.stopDeveloperTest();
        if (mounted) setState(() => _message = '测试已结束，原有通知计划已恢复。');
      } else {
        final result = await CourseLiveActivityService.startDeveloperTest(
          delayed: delayed,
          ongoing: ongoing,
        );
        final starts = DateTime.fromMillisecondsSinceEpoch(
          result['startAt'] as int,
        );
        if (mounted) {
          setState(
            () =>
                _message =
                    ongoing
                        ? '已请求显示课中进度，2 分钟后结束。可返回桌面检查。'
                        : '${delayed ? '1 分钟后显示通知' : '通知已请求发布'}，'
                            '${TimeOfDay.fromDateTime(starts).format(context)} 上课后切换进度，2 分钟后结束。'
                            '可返回桌面测试；通知权限与精确闹钟权限需已开启。',
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _message = '操作失败，请确认隐私协议及系统通知设置后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WindowControlsAwareAppBar(
      child: AppBar(title: const Text('课前通知测试')),
    ),
    body:
        !kDebugMode || !PlatformCompatibilityService.isAndroid
            ? const Center(child: Text('仅 Android Debug 可用'))
            : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_message),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : () => _run(delayed: false),
                  child: const Text('立即显示 · 2 分钟后上课'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('course-live-test-ongoing'),
                  onPressed:
                      _busy ? null : () => _run(delayed: false, ongoing: true),
                  child: const Text('立即显示课中进度 · 2 分钟后结束'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(delayed: true),
                  child: const Text('延迟显示 · 1 分钟后进入课前窗口'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => _run(),
                  child: const Text('结束测试并恢复'),
                ),
                const SizedBox(height: 16),
                const Text(
                  '虚拟课程 · 高等数学 / 测试教室 A101\n'
                  '可验证课前信息、课中进度与到点撤销。测试退出页面后继续；重启应用或切换账号时结束。'
                  '短时间反复测试可能受到系统闹钟配额限制。',
                ),
              ],
            ),
  );
}
