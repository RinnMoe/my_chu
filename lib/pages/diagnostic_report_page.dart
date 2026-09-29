import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../capabilities/android_device_compatibility.dart';
import '../services/diagnostic_report_service.dart';
import '../services/error_feedback_service.dart';
import '../services/file_save_service.dart';
import '../services/platform_environment.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

typedef DiagnosticSaveFile =
    Future<String?> Function({
      required String fileName,
      required List<int> bytes,
    });

typedef DiagnosticShareFile =
    Future<bool> Function({required String path, required String fileName});

/// Formal, user-visible diagnostic log/export page.
class DiagnosticReportPage extends StatefulWidget {
  final DiagnosticReportService? service;
  final DiagnosticLogBuffer? diagnostics;

  final DiagnosticSaveFile? saveFile;
  final DiagnosticShareFile? shareFile;
  final AndroidDeviceCompatibilityCapability? deviceCompatibility;

  const DiagnosticReportPage({
    super.key,
    this.service,
    this.diagnostics,

    this.saveFile,
    this.shareFile,
    this.deviceCompatibility,
  });

  @override
  State<DiagnosticReportPage> createState() => _DiagnosticReportPageState();
}

class _DiagnosticReportPageState extends State<DiagnosticReportPage> {
  DiagnosticReport? _report;
  String _appVersion = 'unknown';
  String _appBuild = 'unknown';
  String? _errorMessage;
  String? _statusMessage;
  AndroidDeviceProfile? _deviceProfile;
  bool _loading = true;
  bool _working = false;

  DiagnosticLogBuffer get _buffer =>
      widget.service?.diagnostics ??
      widget.diagnostics ??
      sharedDiagnosticLogBuffer;

  @override
  void initState() {
    super.initState();
    _buffer.addListener(_onLogUpdated);
    if (widget.service != null) {
      _report = widget.service!.build();
      _loading = false;
    } else {
      _loadPackageInfo();
    }
  }

  @override
  void dispose() {
    _buffer.removeListener(_onLogUpdated);
    super.dispose();
  }

  void _onLogUpdated() {
    if (!mounted) return;
    setState(() => _report = _serviceForContext().build());
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _appBuild = info.buildNumber;
    } catch (_) {
      // The report remains useful with explicit unknown version metadata.
    }
    try {
      _deviceProfile =
          await (widget.deviceCompatibility ??
                  androidDeviceCompatibilityCapability)
              .getProfile();
    } catch (_) {
      // Device compatibility is optional; the report remains useful without it.
    }
    if (!mounted) return;
    setState(() {
      _report = _serviceForContext().build();
      _loading = false;
    });
  }

  DiagnosticReportService _serviceForContext() {
    final supplied = widget.service;
    if (supplied != null) return supplied;
    return DiagnosticReportService(
      diagnostics: widget.diagnostics,
      appVersion: _appVersion,
      appBuild: _appBuild,
      deviceProfile: _deviceProfile,
      environment: PlatformEnvironment.fromContext(context),
    );
  }

  DiagnosticReport get _currentReport =>
      _report ?? _serviceForContext().build();

  Future<void> _save() async => _runFileAction(share: false);

  Future<void> _share() async => _runFileAction(share: true);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _currentReport.toText()));
    if (!mounted) return;
    setState(() => _statusMessage = '诊断日志已复制到剪贴板。');
    _showMessage(_statusMessage!);
  }

  void _showMessage(String message) {
    {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _runFileAction({required bool share}) async {
    if (_working) return;
    final report = _currentReport;
    final service = _serviceForContext();
    final fileName = service.fileName(report: report);
    final bytes = utf8.encode(report.toText());
    setState(() {
      _working = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final saveFile = widget.saveFile ?? FileSaveService.saveToDownloads;
      final path = await saveFile(fileName: fileName, bytes: bytes);
      if (path == null || path.isEmpty) throw StateError('save failed');
      if (share) {
        final shareFile = widget.shareFile ?? FileSaveService.shareFile;
        if (!await shareFile(path: path, fileName: fileName)) {
          throw StateError('share failed');
        }
      }
      if (!mounted) return;
      setState(() {
        _working = false;
        _statusMessage = share ? '已打开系统分享面板。' : '诊断报告已保存。';
      });
      _showMessage(_statusMessage!);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _errorMessage = share ? '分享失败，请稍后重试。' : '保存失败，请稍后重试。';
      });
      _showMessage(_errorMessage!);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('清空诊断日志？'),
            content: const Text('仅清除当前进程内的诊断事件，无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('清空'),
              ),
            ],
          ),
    );
    if (confirmed == true) _buffer.clear();
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      key: const ValueKey('diagnostic-report-preview'),
      width: double.infinity,
      height: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _currentReport.toText(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('诊断信息'),
          actions: [
            IconButton(
              tooltip: '复制全部',
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              tooltip: '保存报告',
              onPressed: _working ? null : _save,
              icon: const Icon(Icons.save_alt_outlined),
            ),
            IconButton(
              tooltip: '分享报告',
              onPressed: _working ? null : _share,
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              tooltip: '清空诊断日志',
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
      body: _buildBody(context),
    );
  }
}
