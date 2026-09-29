import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../capabilities/android_device_compatibility.dart';
import '../services/app_remote_services_service.dart';
import '../services/diagnostic_report_service.dart';
import '../services/fenfa/fenfa_models.dart';
import '../services/fenfa/fenfa_service.dart';
import '../services/public_http_client.dart';
import '../services/platform_environment.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// Fenfa 匿名反馈表单。
class FenfaFeedbackPage extends StatefulWidget {
  final FenfaService? service;
  final DiagnosticReportService? diagnosticService;
  final AndroidDeviceCompatibilityCapability? deviceCompatibility;

  const FenfaFeedbackPage({
    super.key,
    this.service,
    this.diagnosticService,
    this.deviceCompatibility,
  });

  @override
  State<FenfaFeedbackPage> createState() => _FenfaFeedbackPageState();
}

class _FenfaFeedbackPageState extends State<FenfaFeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _contactController = TextEditingController();

  FenfaFeedbackCategory _category = FenfaFeedbackCategory.bug;
  bool _submitting = false;
  bool _submitted = false;
  String? _errorMessage;
  bool _attachDiagnostics = false;
  String? _diagnosticLog;
  bool _diagnosticLoading = false;

  int get _contentMaxLength =>
      _attachDiagnostics
          ? kFenfaFeedbackWithDiagnosticsMaxContentLength
          : kFenfaFeedbackMaxContentLength;

  FenfaService get _service => widget.service ?? FenfaService.shared;

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<String> _ensureDiagnosticLog() async {
    final current = _diagnosticLog;
    if (current != null) return current;
    final supplied = widget.diagnosticService;
    if (supplied != null) {
      final text = supplied.feedbackText();
      _diagnosticLog = text;
      return text;
    }

    var version = 'unknown';
    var build = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {
      // Keep explicit unknown metadata if package information is unavailable.
    }
    AndroidDeviceProfile? deviceProfile;
    try {
      deviceProfile =
          await (widget.deviceCompatibility ??
                  androidDeviceCompatibilityCapability)
              .getProfile();
    } catch (_) {
      // Device compatibility is optional; the feedback remains useful without it.
    }
    if (!mounted) return '';
    final service = DiagnosticReportService(
      appVersion: version,
      appBuild: build,
      deviceProfile: deviceProfile,
      environment: PlatformEnvironment.fromContext(context),
    );
    final text = service.feedbackText();
    _diagnosticLog = text;
    return text;
  }

  Future<void> _submit() async {
    if (_contentController.text.trim().isEmpty) {
      setState(() => _errorMessage = '请输入反馈内容');
      return;
    }
    if (_formKey.currentState case final state?) {
      if (!state.validate()) return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final diagnosticLog =
          _attachDiagnostics ? await _ensureDiagnosticLog() : '';
      await _service.submitFeedback(
        FenfaFeedbackDraft(
          category: _category,
          content: _contentController.text,
          contact: _contactController.text,
          diagnosticLog: diagnosticLog,
        ),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } on AppRemoteServicesDisabledException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = AppRemoteServicesDisabledException.userMessage;
      });
    } on PublicHttpException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage =
            error.statusCode == 429 ? '提交过于频繁，请稍后再试。' : '提交失败，请稍后重试。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = '提交失败，请稍后重试。';
      });
    }
  }

  Future<void> _setAttachDiagnostics(bool value) async {
    if (!value) {
      setState(() {
        _attachDiagnostics = false;
        _errorMessage = null;
      });
      return;
    }
    if (_contentController.text.runes.length >
        kFenfaFeedbackWithDiagnosticsMaxContentLength) {
      setState(() => _errorMessage = '附带诊断信息时，反馈内容最多 2700 字');
      return;
    }
    setState(() {
      _diagnosticLoading = true;
      _errorMessage = null;
    });
    try {
      final diagnostics = await _ensureDiagnosticLog();
      if (!mounted) return;
      setState(() {
        _attachDiagnostics = diagnostics.isNotEmpty;
        _diagnosticLoading = false;
        if (diagnostics.isEmpty) _errorMessage = '暂无可附带的诊断信息。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _diagnosticLoading = false;
        _errorMessage = '诊断信息暂时不可用。';
      });
    }
  }

  Future<void> _showDiagnosticsPreview() async {
    final diagnostics = await _ensureDiagnosticLog();
    if (!mounted || diagnostics.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('诊断日志预览'),
            content: SizedBox(
              width: 520,
              height: 240,
              child: SingleChildScrollView(
                child: SelectableText(
                  diagnostics,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _submitted ? _buildSuccess(context) : _buildForm(context);
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('建言献策')),
      ),
      body: body,
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            '告诉我们你遇到的问题或想要的改进。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<FenfaFeedbackCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: '反馈类型'),
            items: [
              for (final category in FenfaFeedbackCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(_categoryLabel(category)),
                ),
            ],
            onChanged:
                _submitting
                    ? null
                    : (category) {
                      if (category != null) {
                        setState(() => _category = category);
                      }
                    },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contentController,
            enabled: !_submitting,
            minLines: 5,
            maxLines: 8,
            maxLength: _contentMaxLength,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              labelText: '反馈内容',
              hintText: '请描述你遇到的问题或建议',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入反馈内容';
              }
              return null;
            },
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _contactController,
            enabled: !_submitting,
            maxLength: kFenfaFeedbackMaxContactLength,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '联系方式（可选）',
              hintText: '建议使用邮箱以便开发者与您联系',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _attachDiagnostics,
            onChanged:
                _submitting || _diagnosticLoading
                    ? null
                    : _setAttachDiagnostics,
            title: const Text('附带诊断信息'),
            subtitle: const Text('勾选本项有助于开发者排查故障。诊断信息完全匿名。'),
            secondary: IconButton(
              tooltip: '预览诊断信息',
              onPressed:
                  _submitting || _diagnosticLoading
                      ? null
                      : _showDiagnosticsPreview,
              icon: const Icon(Icons.visibility_outlined),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon:
                _submitting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.send_outlined),
            label: Text(_submitting ? '提交中…' : '提交反馈'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: colors.primary),
            const SizedBox(height: 16),
            Text(
              '感谢你的反馈，我们会尽快查看。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(FenfaFeedbackCategory category) {
    return switch (category) {
      FenfaFeedbackCategory.bug => '问题反馈',
      FenfaFeedbackCategory.suggestion => '功能建议',
      FenfaFeedbackCategory.other => '其他',
    };
  }
}
