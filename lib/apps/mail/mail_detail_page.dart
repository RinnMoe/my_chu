import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/reliability_event.dart';
import '../../services/file_save_service.dart';
import '../../services/mail/mail_compose.dart';
import '../../services/mail/mail_error.dart';
import '../../services/mail/mail_html_document.dart';
import '../../services/mail/mail_mime.dart';
import '../../services/mail/mail_models.dart';
import '../../services/mail/mail_preferences.dart';
import '../../services/mail/mail_session.dart';
import '../../services/user_error_message.dart';
import '../../widgets/adaptive_confirmation_dialog.dart';
import '../../widgets/adaptive_feedback.dart';
import 'mail_compose_page.dart';
import 'mail_html_view.dart';
import 'mail_widgets.dart';

class MailDetailPage extends StatelessWidget {
  final String folderPath;
  final MailHeader header;
  final ValueChanged<int>? onMarkedRead;
  final MailSession? session;

  /// 回复/转发成功后通知上一页刷新文件夹与列表。
  final VoidCallback? onSent;

  const MailDetailPage({
    super.key,
    required this.folderPath,
    required this.header,
    this.onMarkedRead,
    this.session,
    this.onSent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('邮件')),
      body: MailDetailView(
        folderPath: folderPath,
        header: header,
        onMarkedRead: onMarkedRead,
        session: session,
        onSent: onSent,
      ),
    );
  }
}

/// 整封邮件由 WebView 按 HTML 排版，原生层负责取信、附件下载、应用内写信与外部链接跳转。
class MailDetailView extends StatefulWidget {
  final String folderPath;
  final MailHeader header;
  final ValueChanged<int>? onMarkedRead;
  final MailSession? session;

  /// 写信页回传发送成功结果后触发，用于刷新列表与文件夹未读数。
  final VoidCallback? onSent;

  const MailDetailView({
    super.key,
    required this.folderPath,
    required this.header,
    this.onMarkedRead,
    this.session,
    this.onSent,
  });

  @override
  State<MailDetailView> createState() => _MailDetailViewState();
}

class _MailDetailViewState extends State<MailDetailView> {
  /// 深色主题下的浅色纸面：邮件普遍写死深色文字，只有浅底才能正确显示。
  static const _paperTheme = MailDocumentTheme(
    textColor: Color(0xFF1F1F1F),
    mutedColor: Color(0xFF5F6368),
    linkColor: Color(0xFF0B57D0),
    surfaceColor: Color(0xFFF1F3F4),
    borderColor: Color(0xFFDADCE0),
    accentColor: Color(0xFF0B57D0),
    onAccentColor: Color(0xFFFFFFFF),
    avatarColor: Color(0xFFE8F0FE),
    onAvatarColor: Color(0xFF0B57D0),
    paperColor: Color(0xFFFFFFFF),
  );

  static final _remoteImagePattern = RegExp(
    r'''<img\b[^>]*\bsrc\s*=\s*["']?https?:''',
    caseSensitive: false,
  );

  late final MailSession _session = widget.session ?? MailSession.instance;
  final MailPreferences _preferences = MailPreferences();

  MailBody? _body;
  String? _error;
  String? _document;
  int? _signature;
  bool _loading = true;
  bool _preferencesReady = false;
  bool _allowRemoteImages = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
    unawaited(_load());
    if (!widget.header.isRead) {
      unawaited(_markRead());
    }
  }

  Future<void> _loadPreferences() async {
    var showRemoteImages = false;
    try {
      showRemoteImages = await _preferences.showRemoteImages();
    } on Object {
      // 读取失败按默认值处理，不阻塞正文。
    }
    if (!mounted) return;
    setState(() {
      _allowRemoteImages = showRemoteImages;
      _preferencesReady = true;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await _session.loadBody(
        widget.folderPath,
        widget.header.uid,
      );
      if (!mounted) return;
      setState(() {
        _body = body;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is MailException ? error.userMessage : '邮件加载失败，请稍后重试';
        _loading = false;
      });
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailRead,
      );
    }
  }

  Future<void> _markRead() async {
    try {
      await _session.setSeen(widget.folderPath, widget.header.uid, true);
      widget.onMarkedRead?.call(widget.header.uid);
    } on Object {
      // 已读状态同步失败不阻塞阅读，下次刷新会重新对齐。
    }
  }

  /// 当前配置邮箱：回复时把自己与发件人从抄送里排除。
  String get _selfAddress => _session.state.value.config?.email ?? '';

  /// 引用原文优先用纯文本，HTML 邮件先转成纯文本。
  String get _originalText {
    final text = _body?.text;
    if (text != null && text.trim().isNotEmpty) return text;
    return mailPlainTextFromHtml(_body?.html ?? '');
  }

  Future<void> _reply({bool replyAll = false}) async {
    final header = widget.header;
    if ((header.from?.address ?? '').trim().isEmpty) {
      _toast('无法回复：缺少发件人地址');
      return;
    }
    final draft = buildReplyDraft(
      header: header,
      selfAddress: _selfAddress,
      originalText: _originalText,
      replyAll: replyAll,
    );
    await _openCompose(draft, replyAll ? '回复全部' : '回复');
  }

  Future<void> _forward() async {
    final draft = buildForwardDraft(
      header: widget.header,
      originalText: _originalText,
    );
    await _openCompose(draft, '转发');
  }

  Future<void> _openCompose(MailDraft draft, String title) async {
    final result = await Navigator.of(context).push<MailSendResult>(
      MaterialPageRoute(
        builder:
            (_) => MailComposePage(
              initialDraft: draft,
              title: title,
              session: _session,
            ),
      ),
    );
    if (!mounted || result == null) return;
    _toast(result.sentCopyStored ? '已发送' : '已发送，未保存到已发送文件夹');
    widget.onSent?.call();
  }

  Future<void> _openLink(Uri uri) async {
    if (uri.scheme == 'mailto') {
      var launched = false;
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Object {
        launched = false;
      }
      if (!launched && mounted) _toast('无法打开链接');
      return;
    }
    final host = uri.host;
    final isCampus = host == 'chd.edu.cn' || host.endsWith('.chd.edu.cn');
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '打开外部链接',
      message:
          isCampus ? '将离开 MyCHU 打开：\n$host' : '该链接不属于校园域名，请确认可信后继续：\n$host',
      confirmLabel: '打开',
    );
    if (confirmed != true) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) _toast('无法打开链接');
  }

  Future<void> _enableRemoteImages() async {
    if (_allowRemoteImages) return;
    setState(() => _allowRemoteImages = true);
    await _preferences.setShowRemoteImages(true);
  }

  Future<void> _handleAction(Uri uri) async {
    if (uri.host == 'attachment') {
      final index = int.tryParse(uri.queryParameters['index'] ?? '');
      final attachments = _body?.attachments ?? const <MailAttachment>[];
      if (index == null || index < 0 || index >= attachments.length) return;
      await _download(attachments[index]);
      return;
    }
    if (uri.host == 'reply') {
      await _reply();
      return;
    }
    if (uri.host == 'reply-all') {
      await _reply(replyAll: true);
      return;
    }
    if (uri.host == 'forward') {
      await _forward();
      return;
    }
    if (uri.host == 'show-images') {
      await _enableRemoteImages();
    }
  }

  Future<void> _download(MailAttachment attachment) async {
    if (_downloading) return;
    _downloading = true;
    _toast('正在下载…');
    File? temporary;
    try {
      final bytes = await _session.downloadAttachment(
        widget.folderPath,
        widget.header.uid,
        attachment,
      );
      final tempDirectory = await getTemporaryDirectory();
      final displayName = mailDisplayFileName(attachment.fileName);
      temporary = File(
        '${tempDirectory.path}${Platform.pathSeparator}'
        'mychu_mail_${widget.header.uid}_'
        '${DateTime.now().microsecondsSinceEpoch}.bin',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      final saved = await FileSaveService.saveFileToDownloads(
        fileName: displayName,
        sourceFile: temporary,
      );
      if (!mounted) return;
      _toast(saved == null ? '保存失败，请稍后重试' : '已保存到下载目录');
    } on Object catch (error) {
      if (mounted) {
        _toast(error is MailException ? error.userMessage : '保存失败，请稍后重试');
        logUserFacingError(
          UserErrorContext.download,
          error,
          operationId: UserOperationId.mailAttachment,
        );
      }
    } finally {
      _downloading = false;
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } on Object {
          // 临时文件清理失败不影响保存结果。
        }
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_preferencesReady) {
      return const AdaptiveLoadingState(label: '正在加载邮件…');
    }
    if (_error != null) {
      return AdaptiveErrorState(
        title: '邮件加载失败',
        message: _error!,
        onRetry: _load,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return MailHtmlView(
          document: _documentFor(context, constraints.maxWidth),
          onOpenLink: (uri) => unawaited(_openLink(uri)),
          onAction: (uri) => unawaited(_handleAction(uri)),
        );
      },
    );
  }

  String _documentFor(BuildContext context, double width) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final allowReplyAll = hasReplyAllRecipients(widget.header, _selfAddress);
    final signature = Object.hash(
      _body,
      _allowRemoteImages,
      allowReplyAll,
      dark,
      width.round(),
      colors.primary,
      colors.onPrimary,
      colors.onSurface,
      colors.onSurfaceVariant,
      colors.surfaceContainerHigh,
      colors.outlineVariant,
      colors.primaryContainer,
      colors.onPrimaryContainer,
    );
    final cached = _document;
    if (cached != null && signature == _signature) return cached;

    final header = widget.header;
    final body = _body;
    _signature = signature;
    _document = MailHtmlDocument.build(
      subject: header.displaySubject,
      senderName: header.from?.displayName ?? '未知发件人',
      senderAddress: header.from?.address ?? '',
      senderInitial: header.from?.initial ?? '?',
      dateText: formatMailDate(header.date),
      recipientsText:
          header.to.isEmpty
              ? ''
              : header.to.map((address) => address.displayName).join('、'),
      bodyHtml:
          body?.html == null ? '' : MailHtmlSanitizer.sanitize(body!.html!),
      bodyText: body?.text ?? '',
      truncated: body?.truncated ?? false,
      allowRemoteImages: _allowRemoteImages,
      showImageAction:
          !_allowRemoteImages && _remoteImagePattern.hasMatch(body?.html ?? ''),
      allowReplyAll: allowReplyAll,
      attachments: [
        for (final attachment in body?.attachments ?? const <MailAttachment>[])
          MailAttachmentLabel(
            name: mailDisplayFileName(attachment.fileName),
            size: formatFileSize(attachment.size),
          ),
      ],
      inlineImages: body?.inlineImages ?? const {},
      theme: dark ? _paperTheme : _themeFrom(colors),
      availableWidth: (width - (dark ? 56 : 40)).clamp(120, 2000),
    );
    return _document!;
  }

  static MailDocumentTheme _themeFrom(ColorScheme colors) {
    return MailDocumentTheme(
      textColor: colors.onSurface,
      mutedColor: colors.onSurfaceVariant,
      linkColor: colors.primary,
      surfaceColor: colors.surfaceContainerHigh,
      borderColor: colors.outlineVariant,
      accentColor: colors.primary,
      onAccentColor: colors.onPrimary,
      avatarColor: colors.primaryContainer,
      onAvatarColor: colors.onPrimaryContainer,
    );
  }
}
