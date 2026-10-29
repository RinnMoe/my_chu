import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../capabilities/android_device_compatibility.dart';
import '../services/app_content/app_content_service.dart';
import '../services/app_content/app_feedback.dart';
import '../services/app_remote_services_service.dart';
import '../services/diagnostic_report_service.dart';
import '../services/feedback_community_service.dart';
import '../services/platform_environment.dart';
import '../services/public_http_client.dart';
import '../widgets/apple_window_controls.dart';

/// 提出建议：公开与私密共用一份表单，由「公开我的建议」决定提交目标。
class FeedbackComposerPage extends StatefulWidget {
  const FeedbackComposerPage({
    super.key,
    this.publicByDefault = true,
    this.communityService,
    this.feedbackService,
    this.diagnosticService,
    this.deviceCompatibility,
  });

  /// 打开时的默认模式；公开建议列表进入时为 true。
  final bool publicByDefault;

  final FeedbackCommunityService? communityService;
  final AppContentService? feedbackService;
  final DiagnosticReportService? diagnosticService;
  final AndroidDeviceCompatibilityCapability? deviceCompatibility;

  @override
  State<FeedbackComposerPage> createState() => _FeedbackComposerPageState();
}

class _FeedbackComposerPageState extends State<FeedbackComposerPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contactController = TextEditingController();
  final _requestId = FeedbackCommunityService.requestId();

  late bool _isPublic = widget.publicByDefault;
  FeedbackCommunityService? _ownedService;

  AppFeedbackCategory _category = AppFeedbackCategory.bug;
  bool _busy = false;
  bool _uncertain = false;
  bool _submitted = false;
  String? _error;
  bool _attachDiagnostics = false;
  String? _diagnosticLog;
  bool _diagnosticLoading = false;

  FeedbackCommunityService get _community =>
      widget.communityService ?? (_ownedService ??= FeedbackCommunityService());

  AppContentService get _feedback =>
      widget.feedbackService ?? AppContentService.shared;

  int get _contentLimit =>
      _attachDiagnostics
          ? kFeedbackWithDiagnosticsMaxContentLength
          : kFeedbackMaxContentLength;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contactController.dispose();
    _ownedService?.close();
    super.dispose();
  }

  void _setPublic(bool value) {
    setState(() {
      _isPublic = value;
      _error = null;
      _uncertain = false;
      if (!value &&
          _attachDiagnostics &&
          _contentController.text.runes.length >
              kFeedbackWithDiagnosticsMaxContentLength) {
        _attachDiagnostics = false;
        _error = '已附带诊断信息，反馈内容请控制在 2700 字以内。';
      }
    });
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isPublic) {
        await _community.write(
          action: 'propose',
          id: _requestId,
          title: _titleController.text.trim(),
          body: _contentController.text.trim(),
        );
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(const SnackBar(content: Text('已提交，感谢你的建议。')));
        return;
      }

      final diagnosticLog =
          _attachDiagnostics ? await _ensureDiagnosticLog() : '';
      await _feedback.submitFeedback(
        AppFeedbackDraft(
          category: _category,
          content: _contentController.text,
          contact: _contactController.text,
          diagnosticLog: diagnosticLog,
        ),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitted = true;
      });
    } on CommunityException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _uncertain = error.uncertain;
        _error = error.message;
      });
    } on AppRemoteServicesDisabledException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppRemoteServicesDisabledException.userMessage;
      });
    } on FeedbackSubmissionUnknownException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FeedbackSubmissionUnknownException.userMessage;
      });
    } on PublicHttpException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.statusCode == 429 ? '提交过于频繁，请稍后再试。' : '提交失败，请稍后重试。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '提交失败，请稍后重试。';
      });
    }
  }

  Future<void> _setAttachDiagnostics(bool value) async {
    if (!value) {
      setState(() {
        _attachDiagnostics = false;
        _error = null;
      });
      return;
    }
    if (_contentController.text.runes.length >
        kFeedbackWithDiagnosticsMaxContentLength) {
      setState(() => _error = '已附带诊断信息，反馈内容请控制在 2700 字以内。');
      return;
    }
    setState(() {
      _diagnosticLoading = true;
      _error = null;
    });
    try {
      final diagnostics = await _ensureDiagnosticLog();
      if (!mounted) return;
      setState(() {
        _attachDiagnostics = diagnostics.isNotEmpty;
        _diagnosticLoading = false;
        if (diagnostics.isEmpty) _error = '暂无可附带的诊断信息。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _diagnosticLoading = false;
        _error = '诊断信息暂时不可用。';
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
            title: const Text('诊断信息预览'),
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
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('提出建议')),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _submitted ? _buildSuccess(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isPublic,
            onChanged: _busy ? null : _setPublic,
            title: const Text('公开我的建议'),
            subtitle: Text(
              _isPublic
                  ? '发布后其他人可以看到，请不要填写联系方式或个人隐私'
                  : '您的建议反馈只有开发者能看到，可以选择附带诊断信息以助于开发者排查故障',
            ),
          ),
          const Divider(height: 32),
          if (_isPublic) ..._buildPublicFields() else ..._buildPrivateFields(),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon:
                _busy
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.send_outlined),
            label: Text(
              _busy
                  ? '提交中…'
                  : _uncertain
                  ? '重试'
                  : _isPublic
                  ? '发布'
                  : '提交反馈',
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPublicFields() => [
    TextFormField(
      controller: _titleController,
      enabled: !_busy && !_uncertain,
      maxLength: 120,
      decoration: const InputDecoration(labelText: '标题'),
      validator:
          (value) => (value?.trim().length ?? 0) < 3 ? '至少输入 3 个字' : null,
    ),
    TextFormField(
      controller: _contentController,
      enabled: !_busy && !_uncertain,
      minLines: 5,
      maxLines: 10,
      maxLength: kFeedbackMaxContentLength,
      decoration: const InputDecoration(
        alignLabelWithHint: true,
        labelText: '内容',
      ),
      validator: (value) => (value?.trim().length ?? 0) < 3 ? '请补充内容' : null,
    ),
  ];

  List<Widget> _buildPrivateFields() => [
    DropdownButtonFormField<AppFeedbackCategory>(
      initialValue: _category,
      decoration: const InputDecoration(labelText: '反馈类型'),
      items: [
        for (final category in AppFeedbackCategory.values)
          DropdownMenuItem(
            value: category,
            child: Text(_categoryLabel(category)),
          ),
      ],
      onChanged:
          _busy
              ? null
              : (category) {
                if (category != null) setState(() => _category = category);
              },
    ),
    const SizedBox(height: 16),
    TextFormField(
      controller: _contentController,
      enabled: !_busy,
      minLines: 5,
      maxLines: 10,
      maxLength: _contentLimit,
      textInputAction: TextInputAction.newline,
      decoration: const InputDecoration(
        alignLabelWithHint: true,
        labelText: '反馈内容',
        hintText: '请描述你遇到的问题或建议',
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return '请输入反馈内容';
        return null;
      },
    ),
    const SizedBox(height: 4),
    TextFormField(
      controller: _contactController,
      enabled: !_busy,
      maxLength: kFeedbackMaxContactLength,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: '联系方式（可选）'),
    ),
    const SizedBox(height: 12),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _attachDiagnostics,
      onChanged: _busy || _diagnosticLoading ? null : _setAttachDiagnostics,
      title: const Text('附带诊断信息'),
      subtitle: const Text('不包含账号与课程信息。'),
      secondary: IconButton(
        tooltip: '预览诊断信息',
        onPressed: _busy || _diagnosticLoading ? null : _showDiagnosticsPreview,
        icon: const Icon(Icons.visibility_outlined),
      ),
    ),
  ];

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

  String _categoryLabel(AppFeedbackCategory category) {
    return switch (category) {
      AppFeedbackCategory.bug => '问题反馈',
      AppFeedbackCategory.suggestion => '功能建议',
      AppFeedbackCategory.other => '其他',
    };
  }
}
