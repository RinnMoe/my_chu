import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/reliability_event.dart';
import '../../services/mail/mail_compose.dart';
import '../../services/mail/mail_error.dart';
import '../../services/mail/mail_models.dart';
import '../../services/mail/mail_session.dart';
import '../../services/user_error_message.dart';
import '../../widgets/adaptive_confirmation_dialog.dart';
import 'mail_widgets.dart';

/// 写信页：纯文本正文 + 内存附件。
///
/// 附件只保留在选择结果里，不落盘、不写缓存；发送成功后把
/// [MailSendResult] 回传给调用方。
class MailComposePage extends StatefulWidget {
  final MailSession? session;
  final MailDraft? initialDraft;
  final String title;

  const MailComposePage({
    super.key,
    this.session,
    this.initialDraft,
    this.title = '写信',
  });

  @override
  State<MailComposePage> createState() => _MailComposePageState();
}

class _MailComposePageState extends State<MailComposePage> {
  static const _maxContentWidth = 720.0;

  late final MailSession _session = widget.session ?? MailSession.instance;
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _bccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;

  late final String _initialTo;
  late final String _initialCc;
  late final String _initialBcc;
  late final String _initialSubject;
  late final String _initialBody;
  late final int _initialAttachmentCount;

  final List<OutgoingAttachment> _attachments = [];
  bool _showCcBcc = false;
  bool _sending = false;
  bool _picking = false;
  bool _confirmingDiscard = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _initialTo = _formatAddresses(draft?.to ?? const []);
    _initialCc = _formatAddresses(draft?.cc ?? const []);
    _initialBcc = _formatAddresses(draft?.bcc ?? const []);
    _initialSubject = draft?.subject ?? '';
    _initialBody = draft?.text ?? '';
    _initialAttachmentCount = draft?.attachments.length ?? 0;
    if (_initialAttachmentCount > 0) {
      _attachments.addAll(draft!.attachments);
    }
    _showCcBcc = _initialCc.isNotEmpty || _initialBcc.isNotEmpty;
    _toController = TextEditingController(text: _initialTo);
    _ccController = TextEditingController(text: _initialCc);
    _bccController = TextEditingController(text: _initialBcc);
    _subjectController = TextEditingController(text: _initialSubject);
    _bodyController = TextEditingController(text: _initialBody);
    _dirty = _computeDirty();
    for (final controller in _controllers) {
      controller.addListener(_syncDirty);
    }
  }

  List<TextEditingController> get _controllers => [
    _toController,
    _ccController,
    _bccController,
    _subjectController,
    _bodyController,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_syncDirty);
      controller.dispose();
    }
    super.dispose();
  }

  /// 输入变化只在实际变脏/复原时重建，`canPop` 才能跟随未保存状态。
  void _syncDirty() {
    final dirty = _computeDirty();
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
  }

  bool _computeDirty() =>
      _toController.text != _initialTo ||
      _ccController.text != _initialCc ||
      _bccController.text != _initialBcc ||
      _subjectController.text != _initialSubject ||
      _bodyController.text != _initialBody ||
      _attachments.length != _initialAttachmentCount;

  Future<void> _send() async {
    if (_sending) return;

    List<MailAddress> to;
    List<MailAddress> cc;
    List<MailAddress> bcc;
    try {
      to = parseMailRecipientList(_toController.text);
      cc = parseMailRecipientList(_ccController.text);
      bcc = parseMailRecipientList(_bccController.text);
    } on FormatException {
      setState(() => _error = '收件地址格式不正确，请检查后重试');
      return;
    }

    final draft = MailDraft(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: _subjectController.text,
      text: _bodyController.text,
      attachments: [..._attachments],
      inReplyTo: widget.initialDraft?.inReplyTo,
    );
    final validation = draft.validationError;
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final result = await _session.send(draft);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on MailException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.userMessage;
        _sending = false;
      });
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailSend,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '发送失败，请稍后重试';
        _sending = false;
      });
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailSend,
      );
    }
  }

  Future<void> _pickAttachments() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final files = await openFiles();
      for (final file in files) {
        if (!mounted) return;
        await _addAttachment(file);
      }
    } on Object {
      if (mounted) setState(() => _error = '无法打开文件选择器，请重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addAttachment(XFile file) async {
    if (_attachments.length >= MailComposeLimits.maxAttachments) {
      setState(
        () => _error = '附件最多 ${MailComposeLimits.maxAttachments} 个，请先移除后再添加',
      );
      return;
    }
    Uint8List bytes;
    try {
      final size = await file.length();
      if (!mounted) return;
      if (size > MailComposeLimits.maxAttachmentBytes) {
        setState(() => _error = '单个附件不能超过 10 MB，请压缩后再添加');
        return;
      }
      final total = _totalAttachmentBytes + size;
      if (total > MailComposeLimits.maxTotalAttachmentBytes) {
        setState(() => _error = '附件合计不能超过 15 MB，请减少后再添加');
        return;
      }
      bytes = await file.readAsBytes();
    } on Object {
      if (mounted) setState(() => _error = '无法读取「${file.name}」，请重新选择');
      return;
    }
    if (!mounted) return;
    setState(() {
      _attachments.add(
        OutgoingAttachment(
          name: file.name,
          mimeType: file.mimeType ?? 'application/octet-stream',
          bytes: bytes,
        ),
      );
    });
    _syncDirty();
  }

  int get _totalAttachmentBytes {
    var total = 0;
    for (final attachment in _attachments) {
      total += attachment.size;
    }
    return total;
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _attachments.length) return;
    setState(() {
      _attachments.removeAt(index);
      _error = null;
    });
    _syncDirty();
  }

  /// 有未发送改动时，返回前弹出放弃确认。
  Future<void> _handleBack() async {
    if (_sending || _confirmingDiscard) return;
    _confirmingDiscard = true;
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '放弃这封邮件？',
      message: '已填写的内容不会保留。',
      confirmLabel: '放弃',
      destructive: true,
    );
    _confirmingDiscard = false;
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope<Object?>(
      canPop: !_dirty && !_sending,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  child:
                      _sending
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('发送'),
                ),
              ),
            ),
          ],
        ),
        // 窗口够高时正文吃掉剩余高度；空间不足（小窗、键盘弹出）时整页滚动，
        // 正文仍保留最小高度，不依赖无界约束下的 Expanded。
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildFields(theme, colors)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildBodyField(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFields(ThemeData theme, ColorScheme colors) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _toController,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '收件人',
                  prefixIcon: const Icon(Icons.person_outline),
                  suffixIcon: IconButton(
                    tooltip: _showCcBcc ? '收起抄送和密送' : '展开抄送和密送',
                    onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
                    icon: Icon(
                      _showCcBcc ? Icons.unfold_less : Icons.unfold_more,
                    ),
                  ),
                ),
              ),
              if (_showCcBcc) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _ccController,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '抄送'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bccController,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '密送'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _subjectController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '主题'),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < _attachments.length; index++)
                      InputChip(
                        label: Text(_attachmentLabel(_attachments[index])),
                        deleteButtonTooltipMessage: '移除附件',
                        onDeleted: () => _removeAttachment(index),
                      ),
                  ],
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _picking ? null : _pickAttachments,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('添加附件'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBodyField() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 240),
            child: TextField(
              controller: _bodyController,
              expands: true,
              minLines: null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '正文',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _attachmentLabel(OutgoingAttachment attachment) {
    final size = formatFileSize(attachment.size);
    return size.isEmpty ? attachment.name : '${attachment.name}  $size';
  }

  static String _formatAddresses(List<MailAddress> addresses) {
    return addresses.map(_formatAddress).join(', ');
  }

  static String _formatAddress(MailAddress address) {
    final name = address.name?.trim() ?? '';
    return name.isEmpty ? address.address : '$name <${address.address}>';
  }
}
