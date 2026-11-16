import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../capabilities/android_device_compatibility.dart';
import '../services/diagnostic_report_service.dart';
import '../services/file_save_service.dart';
import '../services/logging/logger.dart';

typedef ErrorLogSaveFile =
    Future<String?> Function({
      required String fileName,
      required List<int> bytes,
    });
typedef ErrorLogShareFile =
    Future<bool> Function({required String path, required String fileName});

class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({
    super.key,
    this.service,
    this.saveFile,
    this.shareFile,
    this.deviceCompatibility,
  });
  final DiagnosticReportService? service;
  final ErrorLogSaveFile? saveFile;
  final ErrorLogShareFile? shareFile;
  final AndroidDeviceCompatibilityCapability? deviceCompatibility;
  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  DiagnosticReportService? _service;
  bool _loading = true;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (!mounted) return;
    if (widget.service != null) {
      setState(() {
        _service = widget.service;
        _loading = false;
      });
      return;
    }
    var version = 'unknown';
    var build = 'unknown';
    AndroidDeviceProfile? device;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (e, stack) {
      AppLogger.error(e, stackTrace: stack);
    }
    try {
      device =
          await (widget.deviceCompatibility ??
                  androidDeviceCompatibilityCapability)
              .getProfile();
    } catch (e, stack) {
      AppLogger.error(e, stackTrace: stack);
    }
    if (!mounted) return;
    setState(() {
      _service =
          widget.service ??
          DiagnosticReportService(
            appVersion: version,
            appBuild: build,
            deviceProfile: device,
          );
      _loading = false;
    });
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _share() async {
    final service = _service;
    final snapshot = AppLogger.entries;
    final resetVersion = AppLogger.resetVersion;
    if (_busy || service == null || snapshot.isEmpty) return;
    setState(() => _busy = true);
    try {
      final text = service.buildText();
      final name = service.fileName();
      final path = await (widget.saveFile ?? FileSaveService.saveToDownloads)(
        fileName: name,
        bytes: utf8.encode(text),
      );
      if (path == null || path.isEmpty) {
        throw StateError('Error log saving failed');
      }
      final shared = await (widget.shareFile ?? FileSaveService.shareFile)(
        path: path,
        fileName: name,
      );
      if (!shared) throw StateError('Error log sharing failed');
      AppLogger.clearExported(snapshot, resetVersion: resetVersion);
      _message('日志已保存并打开分享面板。');
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
      _message('分享失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '清空错误日志？',
      message: '',
      confirmLabel: '清空',
      destructive: true,
    );
    if (confirmed == true) AppLogger.clear();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<List<ErrorEntry>>(
    valueListenable: AppLogger.errors,
    builder:
        (context, entries, _) => Scaffold(
          appBar: AppBar(
            title: const Text('错误日志'),
            actions: [
              IconButton(
                tooltip: '分享错误日志',
                onPressed: _loading || _busy || entries.isEmpty ? null : _share,
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: '清空错误日志',
                onPressed: _loading || _busy || entries.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body:
              _loading
                  ? const AdaptiveLoadingState()
                  : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('暂无错误日志，复现问题后返回查看。'),
                        ),
                      for (final entry in entries.reversed)
                        ExpansionTile(
                          key: ObjectKey(entry),
                          title: Text(
                            entry.content.split('\n').take(2).join('\n'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(entry.timestamp.toLocal().toString()),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SelectableText(entry.content),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
        ),
  );
}
