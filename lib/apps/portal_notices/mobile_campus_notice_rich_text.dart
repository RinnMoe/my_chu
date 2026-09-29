import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../../services/service_endpoints.dart';

typedef NoticeExternalLinkOpener = Future<void> Function(Uri uri);

/// 本地富文本渲染：把移动校园公告正文 HTML 转成 Flutter 文本与内嵌图片。
class MobileCampusNoticeRichText extends StatefulWidget {
  final String html;
  final TextStyle? style;
  final NoticeExternalLinkOpener? onOpenLink;

  const MobileCampusNoticeRichText({
    super.key,
    required this.html,
    this.style,
    this.onOpenLink,
  });

  @override
  State<MobileCampusNoticeRichText> createState() =>
      _MobileCampusNoticeRichTextState();
}

class _MobileCampusNoticeRichTextState
    extends State<MobileCampusNoticeRichText> {
  NoticeRichTextBuilder? _builder;
  InlineSpan? _span;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);

    final width =
        (MediaQuery.sizeOf(context).width - 32).clamp(120, 520).toDouble();
    _builder = NoticeRichTextBuilder(
      baseUrl: CampusServiceEndpoints.mobileCampusBase,
      baseStyle:
          widget.style ?? theme.textTheme.bodyMedium ?? const TextStyle(),
      linkColor: theme.colorScheme.primary,
      attachmentBackgroundColor: theme.colorScheme.surfaceContainerHigh,
      attachmentBorderColor: theme.colorScheme.outlineVariant,
      attachmentForegroundColor: theme.colorScheme.primary,
      attachmentIconColor: theme.colorScheme.primary,
      imageWidth: width,
      maxAttachmentWidth: width,
      onOpen: _open,
    );
    _span = _builder!.build(widget.html);
  }

  @override
  void didUpdateWidget(MobileCampusNoticeRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html || oldWidget.style != widget.style) {
      _span = _builder?.build(widget.html);
    }
  }

  Future<void> _open(Uri uri) async {
    final opener = widget.onOpenLink;
    if (opener != null) {
      await opener(uri);
      return;
    }

    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(_span ?? const TextSpan(), style: widget.style);
  }
}

/// 将公告 HTML 转换为带链接、基础排版和内嵌图片的 [InlineSpan]。
class NoticeRichTextBuilder {
  final String baseUrl;
  final TextStyle baseStyle;
  final Color linkColor;
  final Color? attachmentBackgroundColor;
  final Color? attachmentBorderColor;
  final Color? attachmentForegroundColor;
  final Color? attachmentIconColor;
  final double imageWidth;
  final double? maxAttachmentWidth;
  final NoticeExternalLinkOpener onOpen;

  NoticeRichTextBuilder({
    required this.baseUrl,
    required this.baseStyle,
    required this.linkColor,
    this.attachmentBackgroundColor,
    this.attachmentBorderColor,
    this.attachmentForegroundColor,
    this.attachmentIconColor,
    required this.imageWidth,
    this.maxAttachmentWidth,
    required this.onOpen,
  });

  InlineSpan build(String html) {
    final body = html_parser.parse(html).body;
    if (body == null) return const TextSpan();
    return _buildNode(body, baseStyle);
  }

  static Uri? resolveUrl(String href, String baseUrl) {
    final value = href.trim();
    if (value.isEmpty) return null;
    final raw = Uri.tryParse(value);
    if (raw == null) return null;

    final uri = raw.hasScheme ? raw : Uri.parse(baseUrl).resolve(value);
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  /// Returns whether a valid HTTP(S) link is likely an attachment/download
  /// entry rather than a regular page link.
  static bool isAttachmentLink({
    required Uri uri,
    required String label,
    bool hasDownloadAttribute = false,
  }) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (hasDownloadAttribute) return true;

    final normalizedLabel = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_attachmentLabelPattern.hasMatch(normalizedLabel)) return true;

    final lastPathSegment =
        uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.toLowerCase();
    final extension =
        lastPathSegment.contains('.')
            ? lastPathSegment.substring(lastPathSegment.lastIndexOf('.') + 1)
            : '';
    if (_attachmentExtensions.contains(extension)) return true;

    final pathLooksLikeDownload = uri.pathSegments.any((segment) {
      final value = segment.toLowerCase();
      return value.contains('download') || value.contains('attachment');
    });
    if (pathLooksLikeDownload) return true;

    return uri.queryParameters.keys.any((key) {
      final value = key.toLowerCase();
      return value.contains('download') || value.contains('attachment');
    });
  }

  InlineSpan _buildNode(html_dom.Node node, TextStyle style, {Uri? link}) {
    if (node is html_dom.Text) {
      return TextSpan(text: node.text, style: style);
    }
    if (node is! html_dom.Element) return const TextSpan();

    final tag = node.localName ?? '';
    if (tag == 'br') return TextSpan(text: '\n', style: style);
    if (tag == 'img') return _imageSpan(node, style, link);

    final childStyle = _styleFor(tag, style);
    final linkUri = link ?? _linkFor(node);
    final isAnchor = tag == 'a' && linkUri != null;
    final isAttachment = isAnchor && _isAttachmentLink(node, linkUri);
    final linkChildStyle =
        isAnchor
            ? childStyle.copyWith(
              color: isAttachment ? _attachmentForeground : linkColor,
              decoration:
                  isAttachment ? TextDecoration.none : TextDecoration.underline,
              decorationColor: linkColor.withValues(alpha: 0.78),
              decorationThickness: isAttachment ? null : 1.2,
            )
            : childStyle;
    final children = <InlineSpan>[];
    if (tag == 'li') {
      children.add(TextSpan(text: _listPrefix(node), style: childStyle));
    }
    if (tag == 'td' || tag == 'th') {
      children.add(const TextSpan(text: '\t'));
    }
    for (final child in node.nodes) {
      children.add(
        _buildNode(
          child,
          isAnchor ? linkChildStyle : childStyle,
          link: linkUri,
        ),
      );
    }

    InlineSpan span = TextSpan(children: children, style: childStyle);
    if (linkUri != null && tag == 'a') {
      span =
          isAttachment
              ? _attachmentSpan(node, children, linkUri, linkChildStyle)
              : _regularLinkSpan(children, linkUri, linkChildStyle);
    }

    if (_lineTags.contains(tag) || _blockTags.contains(tag)) {
      return TextSpan(
        children: [span, const TextSpan(text: '\n')],
        style: style,
      );
    }
    return span;
  }

  WidgetSpan _regularLinkSpan(
    List<InlineSpan> children,
    Uri uri,
    TextStyle style,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(uri),
        child: Text.rich(TextSpan(children: children, style: style)),
      ),
    );
  }

  WidgetSpan _attachmentSpan(
    html_dom.Element node,
    List<InlineSpan> children,
    Uri uri,
    TextStyle style,
  ) {
    final label = _linkLabel(node, uri);
    final labelChildren =
        node.text.trim().isEmpty
            ? <InlineSpan>[TextSpan(text: label)]
            : children;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: _attachmentBorder),
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        button: true,
        label: '附件：$label',
        child: Material(
          color: _attachmentBackground,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpen(uri),
            customBorder: shape,
            child: _attachmentContent(labelChildren, uri, style),
          ),
        ),
      ),
    );
  }

  Widget _attachmentContent(
    List<InlineSpan> labelChildren,
    Uri uri,
    TextStyle style,
  ) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 36, maxWidth: _maxAttachmentWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_attachmentIcon(uri), size: 16, color: _attachmentIconColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: labelChildren,
                  style: style.copyWith(
                    color: _attachmentForeground,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isAttachmentLink(html_dom.Element node, Uri uri) {
    if (node.querySelector('img') != null) return false;
    return isAttachmentLink(
      uri: uri,
      label: node.text,
      hasDownloadAttribute: node.attributes.containsKey('download'),
    );
  }

  String _linkLabel(html_dom.Element node, Uri uri) {
    final label = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (label.isNotEmpty) return label;
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return '查看附件';
  }

  Uri? _linkFor(html_dom.Element node) {
    if (node.localName != 'a') return null;
    return resolveUrl(node.attributes['href'] ?? '', baseUrl);
  }

  WidgetSpan _imageSpan(html_dom.Element node, TextStyle style, Uri? link) {
    final alt = node.attributes['alt']?.trim() ?? '';
    final src = node.attributes['src']?.trim() ?? '';
    final uri = resolveUrl(src, baseUrl);
    if (uri == null) {
      return WidgetSpan(child: Text(alt.isEmpty ? '[图片]' : alt, style: style));
    }

    final image = Image.network(
      uri.toString(),
      width: imageWidth,
      fit: BoxFit.fitWidth,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Text(alt.isEmpty ? '图片加载失败' : alt, style: style);
      },
    );

    Widget child = image;
    if (link != null) {
      child = GestureDetector(onTap: () => onOpen(link), child: image);
    }
    return WidgetSpan(child: child, alignment: PlaceholderAlignment.middle);
  }

  static TextStyle _styleFor(String tag, TextStyle style) {
    switch (tag) {
      case 'b':
      case 'strong':
        return style.copyWith(fontWeight: FontWeight.bold);
      case 'i':
      case 'em':
      case 'cite':
        return style.copyWith(fontStyle: FontStyle.italic);
      case 'u':
      case 'ins':
        return style.copyWith(decoration: TextDecoration.underline);
      case 's':
      case 'strike':
      case 'del':
        return style.copyWith(decoration: TextDecoration.lineThrough);
      case 'blockquote':
        return style.copyWith(fontStyle: FontStyle.italic);
      case 'h1':
        return style.copyWith(
          fontSize: 22,
          height: 1.35,
          fontWeight: FontWeight.w800,
        );
      case 'h2':
        return style.copyWith(
          fontSize: 19,
          height: 1.4,
          fontWeight: FontWeight.w700,
        );
      case 'h3':
        return style.copyWith(
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w700,
        );
      default:
        return style;
    }
  }

  static String _listPrefix(html_dom.Element node) {
    final parent = node.parent;
    if (parent is html_dom.Element && parent.localName == 'ol') {
      final items =
          parent.nodes
              .whereType<html_dom.Element>()
              .where((item) => item.localName == 'li')
              .toList();
      return '${items.indexOf(node) + 1}. ';
    }
    return '• ';
  }

  Color get _attachmentBackground =>
      attachmentBackgroundColor ?? linkColor.withValues(alpha: 0.10);

  Color get _attachmentBorder =>
      attachmentBorderColor ?? linkColor.withValues(alpha: 0.30);

  Color get _attachmentForeground => attachmentForegroundColor ?? linkColor;

  Color get _attachmentIconColor => attachmentIconColor ?? linkColor;

  double get _maxAttachmentWidth => maxAttachmentWidth ?? imageWidth;

  IconData _attachmentIcon(Uri uri) {
    final lastPathSegment =
        uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.toLowerCase();
    final extension =
        lastPathSegment.contains('.')
            ? lastPathSegment.substring(lastPathSegment.lastIndexOf('.') + 1)
            : '';
    if (extension == 'pdf') return Icons.picture_as_pdf_outlined;
    if (const {'doc', 'docx', 'rtf', 'txt', 'wps'}.contains(extension)) {
      return Icons.description_outlined;
    }
    if (const {'xls', 'xlsx', 'csv', 'et'}.contains(extension)) {
      return Icons.table_chart_outlined;
    }
    if (const {'ppt', 'pptx', 'dps'}.contains(extension)) {
      return Icons.slideshow_outlined;
    }
    if (const {'zip', 'rar', '7z', 'tar', 'gz'}.contains(extension)) {
      return Icons.archive_outlined;
    }
    if (const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension)) {
      return Icons.image_outlined;
    }
    return Icons.attach_file;
  }

  static const Set<String> _blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'dd',
    'div',
    'dl',
    'dt',
    'fieldset',
    'figcaption',
    'figure',
    'footer',
    'form',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'ul',
  };

  static const Set<String> _lineTags = {'br', 'li', 'tr', 'hr'};

  static final RegExp _attachmentLabelPattern = RegExp(
    r'(附件|下载|文件|download|attachment)',
    caseSensitive: false,
  );

  static const Set<String> _attachmentExtensions = {
    '7z',
    'apk',
    'bz2',
    'csv',
    'doc',
    'docx',
    'dps',
    'et',
    'gz',
    'jpeg',
    'jpg',
    'pdf',
    'png',
    'ppt',
    'pptx',
    'rar',
    'rtf',
    'tar',
    'txt',
    'webp',
    'wps',
    'xls',
    'xlsx',
    'zip',
  };
}
