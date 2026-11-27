import 'package:flutter/material.dart';

import '../capabilities/chat_demo/chat_demo_brand.dart';
import '../capabilities/chat_demo/chat_demo_storage.dart';
import '../capabilities/manual_login_web_view_page.dart';
import '../services/deepseek_api_settings_service.dart';
import '../services/logging/logger.dart';
import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_settings.dart';
import '../widgets/app_bottom_sheet.dart';

/// MyCHU 原生「问 Yui」设置页。
class DeepSeekApiSettingsPage extends StatefulWidget {
  const DeepSeekApiSettingsPage({
    super.key,
    this.onClearHistory,
    this.service,
    this.onVerifyKey,
    this.platformPageBuilder,
  });

  final Future<void> Function()? onClearHistory;
  final DeepSeekApiSettingsService? service;
  final Future<DeepSeekApiKeyCheckResult> Function(String apiKey)? onVerifyKey;
  final Widget Function(String title, String url)? platformPageBuilder;

  @override
  State<DeepSeekApiSettingsPage> createState() =>
      _DeepSeekApiSettingsPageState();
}

class _DeepSeekApiSettingsPageState extends State<DeepSeekApiSettingsPage> {
  static const String _platformKeysUrl = 'https://platform.deepseek.com/api_keys';

  late final DeepSeekApiSettingsService _service =
      widget.service ?? DeepSeekApiSettingsService.instance;

  bool _loading = true;
  bool _configured = false;
  String? _maskedKey;
  bool _saving = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? key;
    try {
      key = await _service.read();
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
    if (!mounted) return;
    setState(() {
      _configured = key != null;
      _maskedKey = key == null ? null : DeepSeekApiSettingsService.mask(key);
      _loading = false;
    });
  }

  Future<void> _openKeyEditorSheet() async {
    final saved = await showAppBottomSheet<bool>(
      context: context,
      scrollBody: true,
      builder:
          (_) => _ApiKeyEditorSheet(
            replacing: _configured,
            onVerifyAndSave: (rawKey) async {
              final key = rawKey.trim();
              final verify = widget.onVerifyKey ?? _service.verify;
              final result = await verify(key);
              switch (result) {
                case DeepSeekApiKeyCheckResult.invalidKey:
                  return 'API Key 无效，请检查后重试';
                case DeepSeekApiKeyCheckResult.networkError:
                  return '无法连接 DeepSeek，请检查网络后重试';
                case DeepSeekApiKeyCheckResult.valid:
                  await _service.write(key);
                  return null;
              }
            },
          ),
    );
    if (saved != true || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('API Key 已保存')));
  }

  void _openPlatformKeysWebView() {
    final builder =
        widget.platformPageBuilder ??
        (title, url) => ManualLoginWebViewPage(title: title, url: url);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => builder('DeepSeek 开放平台', _platformKeysUrl),
      ),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '删除 API Key？',
      message: '删除后需重新填写才能继续使用「$askYuiName」。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.clear();
      if (!mounted) return;
      setState(() {
        _configured = false;
        _maskedKey = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API Key 已删除')));
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '清除所有对话？',
      message: '将永久删除本机保存的全部对话与附件，无法恢复。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await (widget.onClearHistory ?? ChatDemoStorageService.clearHistory)();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清除所有对话')));
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.onClearHistory != null ? '清除失败，请稍后重试' : '清除失败，请关闭对话页后重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('$askYuiName 设置')),
      body:
          _loading
              ? const AdaptiveLoadingState()
              : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      AdaptiveSettingsSection(
                        title: 'DeepSeek API',
                        footer: '密钥仅保存在本机。',
                        children: [
                          AdaptiveSettingsRow(
                            icon:
                                _configured
                                    ? Icons.key_outlined
                                    : Icons.key_off_outlined,
                            title: 'API Key',
                            subtitle: _maskedKey,
                            trailingValue: _configured ? '更换' : '未配置',
                            onTap: _saving ? null : _openKeyEditorSheet,
                          ),
                          AdaptiveSettingsRow(
                            icon: Icons.language_outlined,
                            title: '获取 API Key',
                            trailingValue: 'DeepSeek 开放平台',
                            onTap: _saving ? null : _openPlatformKeysWebView,
                          ),
                          if (_configured)
                            ListTile(
                              leading: Icon(
                                Icons.delete_outline,
                                color: errorColor,
                              ),
                              title: Text(
                                '删除 API Key',
                                style: TextStyle(color: errorColor),
                              ),
                              enabled: !_saving,
                              onTap: _clear,
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AdaptiveSettingsSection(
                        title: '对话记录',
                        children: [
                          ListTile(
                            leading:
                                _clearing
                                    ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : Icon(
                                      Icons.delete_sweep_outlined,
                                      color: errorColor,
                                    ),
                            title: Text(
                              _clearing ? '正在清除…' : '清除所有对话',
                              style: TextStyle(color: errorColor),
                            ),
                            enabled: !_clearing,
                            onTap: _clearHistory,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

class _ApiKeyEditorSheet extends StatefulWidget {
  const _ApiKeyEditorSheet({
    required this.replacing,
    required this.onVerifyAndSave,
  });

  final bool replacing;
  final Future<String?> Function(String apiKey) onVerifyAndSave;

  @override
  State<_ApiKeyEditorSheet> createState() => _ApiKeyEditorSheetState();
}

class _ApiKeyEditorSheetState extends State<_ApiKeyEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? errorMessage;
    try {
      errorMessage = await widget.onVerifyAndSave(_controller.text);
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      errorMessage = '保存失败，请稍后重试';
    }
    if (!mounted) return;
    if (errorMessage == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSheetHeader(
                title: widget.replacing ? '更换 API Key' : '配置 API Key',
                padding: const EdgeInsets.only(bottom: 12),
              ),
              TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_submitting,
                obscureText: _obscure,
                autofillHints: const [],
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-…',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '显示' : '隐藏',
                    onPressed:
                        _submitting
                            ? null
                            : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 API Key';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child:
                      _submitting
                          ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.38,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('验证中…'),
                            ],
                          )
                          : const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
