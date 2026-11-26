import 'package:flutter/material.dart';

import '../capabilities/chat_demo/chat_demo_brand.dart';
import '../capabilities/chat_demo/chat_demo_storage.dart';
import '../services/deepseek_api_settings_service.dart';
import '../services/logging/logger.dart';
import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_settings.dart';

/// MyCHU 原生 DeepSeek API 设置页。
///
/// Key 是应用级配置，不要求登录校园账号，也不随账号切换。
class DeepSeekApiSettingsPage extends StatefulWidget {
  const DeepSeekApiSettingsPage({super.key, this.onClearHistory});

  final Future<void> Function()? onClearHistory;

  @override
  State<DeepSeekApiSettingsPage> createState() =>
      _DeepSeekApiSettingsPageState();
}

class _DeepSeekApiSettingsPageState extends State<DeepSeekApiSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _service = DeepSeekApiSettingsService.instance;

  bool _loading = true;
  bool _configured = false;
  bool _editing = false;
  bool _saving = false;
  bool _clearing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
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
      _editing = key == null;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.write(_key.text);
      if (!mounted) return;
      _key.clear();
      setState(() {
        _configured = true;
        _editing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DeepSeek API Key 已保存。')));
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (mounted) {
        setState(() => _error = '保存失败，请稍后重试。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '删除 DeepSeek API Key？',
      message: '删除后需重新配置 DeepSeek API Key 才能使用「$askYuiName」。此操作不影响校园账号和聊天记录。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.clear();
      if (!mounted) return;
      _key.clear();
      setState(() {
        _configured = false;
        _editing = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DeepSeek API Key 已删除。')));
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (mounted) {
        setState(() => _error = '删除失败，请稍后重试。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '清除所有对话？',
      message: '将删除「$askYuiName」在本机的全部会话和附件，且无法恢复。DeepSeek API Key 不受影响。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _clearing = true;
      _error = null;
    });
    try {
      await (widget.onClearHistory ?? ChatDemoStorageService.clearHistory)();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('聊天记录已清除。')));
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      if (mounted) {
        setState(
          () =>
              _error =
                  widget.onClearHistory != null
                      ? '清除失败，请稍后重试。'
                      : '清除失败，请先退出「$askYuiName」页面后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$askYuiName 设置')),
      body:
          _loading
              ? const AdaptiveLoadingState()
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdaptiveSettingsSection(
                    title: 'DeepSeek API',
                    footer:
                        'Key 仅保存在本机安全存储，仅用于「$askYuiName」请求 DeepSeek；'
                        '不随校园账号同步，也不会写入聊天记录。',
                    children: [
                      ListTile(
                        leading: Icon(
                          _configured
                              ? Icons.check_circle_outline
                              : Icons.key_off_outlined,
                        ),
                        title: Text(_configured ? '已配置' : '未配置'),
                        trailing:
                            _configured
                                ? TextButton(
                                  onPressed:
                                      _saving
                                          ? null
                                          : () => setState(() {
                                            _editing = !_editing;
                                            _error = null;
                                          }),
                                  child: Text(_editing ? '取消' : '更换'),
                                )
                                : null,
                      ),
                    ],
                  ),
                  if (_editing) ...[
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: AdaptiveSettingsSection(
                        title: '输入 API Key',
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: TextFormField(
                              controller: _key,
                              obscureText: true,
                              autofillHints: const [],
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.visiblePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _save(),
                              decoration: const InputDecoration(
                                labelText: 'DeepSeek API Key',
                                hintText: 'sk-…',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '请输入 API Key。';
                                }
                                return null;
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child:
                                  _saving
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Text('保存'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_configured && !_editing) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _clear,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除 API Key'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  AdaptiveSettingsSection(
                    title: '聊天记录',
                    footer: '仅清除「$askYuiName」在本机的会话和附件，不影响 API Key 或校园账号。',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.delete_sweep_outlined),
                        title: const Text('清除所有对话'),
                        trailing: TextButton(
                          onPressed: _clearing ? null : _clearHistory,
                          child: Text(_clearing ? '清理中…' : '清除'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
    );
  }
}
