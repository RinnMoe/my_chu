import 'package:flutter/material.dart';
import '../services/logging/logger.dart';
import '../services/host_permission_service.dart';
import '../pages/error_log_page.dart';

class DiagnosticsEntries extends StatefulWidget {
  const DiagnosticsEntries({super.key});
  @override
  State<DiagnosticsEntries> createState() => _DiagnosticsEntriesState();
}

class _DiagnosticsEntriesState extends State<DiagnosticsEntries> {
  bool _busy = false;
  Future<void> _setCrashRecording(bool enabled) async {
    setState(() => _busy = true);
    try {
      if (enabled && await AppLogger.requiresCrashStoragePermission()) {
        final permission =
            await hostPermissionService.requestCrashReportStoragePermission();
        if (!permission.granted) throw StateError('Storage permission denied');
      }
      await AppLogger.setCrashRecording(enabled);
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置失败，请检查存储权限后重试。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: const Text('崩溃报告抓取'),
        secondary: const Icon(Icons.bug_report_outlined),
        subtitle: Text(
          !AppLogger.supportsCrashRecording
              ? '当前系统暂不支持自动保存至公共下载目录'
              : '点击开始抓取，崩溃后日志将保存在Download文件夹',
        ),
        value: AppLogger.isCrashRecording,
        onChanged:
            _busy || !AppLogger.supportsCrashRecording
                ? null
                : _setCrashRecording,
      ),
      ListTile(
        title: const Text('错误日志'),
        subtitle: const Text('查看或导出错误日志'),
        leading: const Icon(Icons.article_outlined),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ErrorLogPage()),
            ),
      ),
    ],
  );
}
