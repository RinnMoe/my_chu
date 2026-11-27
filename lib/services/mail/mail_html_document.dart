import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:html/dom.dart' as dom;

import 'mail_mime.dart';

/// 附件在正文里的展示信息。
class MailAttachmentLabel {
  final String name;
  final String size;

  const MailAttachmentLabel({required this.name, required this.size});
}

/// 邮件文档配色。浅色主题跟随应用，深色主题回落到浅色纸面。
class MailDocumentTheme {
  final Color textColor;
  final Color mutedColor;
  final Color linkColor;
  final Color surfaceColor;
  final Color borderColor;
  final Color accentColor;
  final Color onAccentColor;
  final Color avatarColor;
  final Color onAvatarColor;
  final Color? paperColor;

  const MailDocumentTheme({
    required this.textColor,
    required this.mutedColor,
    required this.linkColor,
    required this.surfaceColor,
    required this.borderColor,
    required this.accentColor,
    required this.onAccentColor,
    required this.avatarColor,
    required this.onAvatarColor,
    this.paperColor,
  });
}

/// 把一封邮件组装成可直接交给 WebView 的完整 HTML 文档。
///
/// 输出是纯函数结果，不依赖 Flutter 运行时，便于离线测试。页面里不启用
/// 脚本：CSP 只放行 data URI 图片，远程图片要用户显式允许后才进入白名单，
/// 附件与邮件动作走 `mychu://` 自定义协议回到原生处理。
class MailHtmlDocument {
  const MailHtmlDocument._();

  /// 内嵌图片转 base64 后的总量上限，避免单封邮件把文档撑到几十兆。
  static const maxInlineImageBytes = 4 * 1024 * 1024;

  static const _textEscape = HtmlEscape(HtmlEscapeMode.element);

  static String build({
    required String subject,
    required String senderName,
    required String senderAddress,
    required String senderInitial,
    required String dateText,
    required String recipientsText,
    required String bodyHtml,
    required String bodyText,
    required bool truncated,
    required bool allowRemoteImages,
    required bool showImageAction,
    required bool allowReplyAll,
    required List<MailAttachmentLabel> attachments,
    required Map<String, Uint8List> inlineImages,
    required MailDocumentTheme theme,
    required double availableWidth,
  }) {
    final prepared = _prepareBody(
      bodyHtml,
      allowRemoteImages: allowRemoteImages,
      inlineImages: inlineImages,
    );
    final body = prepared.html;
    final content =
        body.isNotEmpty
            ? body
            : bodyText.trim().isEmpty
            ? '<p class="empty">这封邮件没有可显示的正文</p>'
            : '<div class="plain">${_textEscape.convert(bodyText.trim())}</div>';
    final imgSources = allowRemoteImages ? 'data: https: http:' : 'data:';
    final paper = theme.paperColor != null;
    final sizing = _bodySizing(prepared.designWidth, availableWidth);

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src $imgSources; style-src 'unsafe-inline'; font-src data:; script-src 'none'; form-action 'none'; base-uri 'none'">
<style>
html, body { margin: 0; padding: 0; background: transparent; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", "PingFang SC", "Microsoft YaHei", "Noto Sans SC", sans-serif;
  font-size: 15px;
  line-height: 1.6;
  color: ${_hex(theme.textColor)};
  overflow-wrap: break-word;
  -webkit-text-size-adjust: 100%;
  -webkit-tap-highlight-color: transparent;
}
main.sheet { padding: 10px 20px 32px; box-sizing: border-box; max-width: 100%; }
main.sheet.paper {
  background: ${_hex(theme.paperColor ?? const Color(0xFFFFFFFF))};
  border-radius: 12px;
  margin: 8px 12px 24px;
  padding: 16px;
}
.subject { font-size: 22px; font-weight: 700; line-height: 1.3; margin: 0 0 14px; }
.meta { display: flex; align-items: flex-start; gap: 12px; }
.avatar {
  flex: 0 0 auto;
  width: 42px;
  height: 42px;
  border-radius: 12px;
  background: ${_hex(theme.avatarColor)};
  color: ${_hex(theme.onAvatarColor)};
  font-size: 16px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
}
.who { flex: 1 1 auto; min-width: 0; }
.name { display: block; font-size: 14px; font-weight: 700; }
.addr { display: block; font-size: 12px; color: ${_hex(theme.mutedColor)}; overflow-wrap: anywhere; }
.date { flex: 0 0 auto; font-size: 12px; color: ${_hex(theme.mutedColor)}; white-space: nowrap; }
.to { font-size: 12px; color: ${_hex(theme.mutedColor)}; margin: 10px 0 0; }
hr { border: 0; border-top: 1px solid ${_hex(theme.borderColor)}; margin: 14px 0; }
/* 正文自成一块：越界内容裁在正文里，不会盖住页头与操作区。 */
.body {
  overflow-x: auto;
  overflow-y: hidden;
  overflow-wrap: break-word;
}
$sizing
.body img { max-width: 100% !important; height: auto !important; }
.body table { border-collapse: collapse; }
.body a { color: ${_hex(theme.linkColor)}; }
.body pre, .body code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px;
  white-space: pre-wrap;
  word-break: break-word;
}
.body blockquote {
  margin: 0 0 8px;
  padding-left: 12px;
  border-left: 3px solid ${_hex(theme.borderColor)};
  color: ${_hex(theme.mutedColor)};
}
.plain { white-space: pre-wrap; }
.empty { color: ${_hex(theme.mutedColor)}; text-align: center; padding: 28px 0; }
.notice {
  font-size: 12px;
  color: ${_hex(theme.mutedColor)};
  background: ${_hex(theme.surfaceColor)};
  border-radius: 10px;
  padding: 10px 12px;
  margin: 0 0 12px;
}
.mychu-blocked {
  display: inline-block;
  padding: 2px 8px;
  border: 1px solid ${_hex(theme.borderColor)};
  border-radius: 6px;
  background: ${_hex(theme.surfaceColor)};
  color: ${_hex(theme.mutedColor)};
  font-size: 12px;
}
.files { margin-top: 24px; }
.files h2 { font-size: 14px; font-weight: 700; margin: 0 0 8px; }
.file {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px;
  margin-bottom: 8px;
  border-radius: 12px;
  background: ${_hex(theme.surfaceColor)};
  color: ${_hex(theme.textColor)};
  text-decoration: none;
}
.file-name { font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.file-size { flex: 0 0 auto; font-size: 12px; color: ${_hex(theme.mutedColor)}; }
.action {
  display: inline-block;
  padding: 10px 22px;
  border-radius: 20px;
  background: ${_hex(theme.accentColor)};
  color: ${_hex(theme.onAccentColor)};
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 24px;
}
.action.ghost {
  margin: 0 0 12px;
  padding: 6px 14px;
  border: 1px solid ${_hex(theme.borderColor)};
  background: transparent;
  color: ${_hex(theme.accentColor)};
  font-weight: 500;
}
</style>
</head>
<body>
<main class="sheet${paper ? ' paper' : ''}">
<h1 class="subject">${_textEscape.convert(subject)}</h1>
<div class="meta">
  <div class="avatar">${_textEscape.convert(senderInitial)}</div>
  <div class="who">
    <span class="name">${_textEscape.convert(senderName)}</span>
    ${senderAddress.isEmpty ? '' : '<span class="addr">${_textEscape.convert(senderAddress)}</span>'}
  </div>
  <span class="date">${_textEscape.convert(dateText)}</span>
</div>
${recipientsText.isEmpty ? '' : '<p class="to">收件人：${_textEscape.convert(recipientsText)}</p>'}
<hr>
${truncated ? '<p class="notice">内容较长，已截断显示</p>' : ''}
${showImageAction ? '<a class="action ghost" href="mychu://show-images">显示图片</a>' : ''}
<section class="body">$content</section>
${_attachments(attachments)}
<div class="actions">
<a class="action" href="mychu://reply">回复</a>
${allowReplyAll ? '<a class="action" href="mychu://reply-all">回复全部</a>' : ''}
<a class="action" href="mychu://forward">转发</a>
</div>
</main>
</body>
</html>
''';
  }

  static String _attachments(List<MailAttachmentLabel> attachments) {
    if (attachments.isEmpty) return '';
    final items = <String>[];
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      items.add(
        '<a class="file" href="mychu://attachment?index=$index">'
        '<span class="file-name">${_textEscape.convert(attachment.name)}</span>'
        '${attachment.size.isEmpty ? '' : '<span class="file-size">${_textEscape.convert(attachment.size)}</span>'}'
        '</a>',
      );
    }
    return '<section class="files"><h2>附件（${attachments.length}）</h2>'
        '${items.join()}</section>';
  }

  /// 内嵌图片转 data URI；远程图片在未允许时换成占位文字，避免破图标。
  static ({String html, double? designWidth}) _prepareBody(
    String html, {
    required bool allowRemoteImages,
    required Map<String, Uint8List> inlineImages,
  }) {
    if (html.trim().isEmpty) return (html: '', designWidth: null);
    final container = dom.Element.tag('div')..innerHtml = html;
    var budget = maxInlineImageBytes;

    // 邮件自带的样式表作用于整个文档，会改到页头、附件与回复区。
    // 统一加上 `.body` 前缀，把它的影响范围收回到正文容器内。
    for (final style in container.querySelectorAll('style')) {
      final scoped = _scopeCss(style.text);
      style.nodes.clear();
      style.append(dom.Text(scoped));
    }

    for (final image in container.querySelectorAll('img')) {
      final src = (image.attributes['src'] ?? '').trim();
      final alt = (image.attributes['alt'] ?? '').trim();
      String? placeholder;

      if (src.toLowerCase().startsWith('cid:')) {
        final bytes = inlineImages[normalizeMailCid(src)];
        if (bytes == null) {
          placeholder = alt.isEmpty ? '内嵌图片' : alt;
        } else if (bytes.length > budget) {
          placeholder = '图片过大';
        } else {
          budget -= bytes.length;
          image.attributes['src'] =
              'data:${imageMimeType(bytes)};base64,${base64Encode(bytes)}';
        }
      } else if (src.isEmpty) {
        placeholder = alt.isEmpty ? '图片' : alt;
      } else if (!allowRemoteImages) {
        placeholder = '图片已隐藏';
      }

      if (placeholder != null) {
        final span =
            dom.Element.tag('span')
              ..classes.add('mychu-blocked')
              ..text = placeholder;
        image.replaceWith(span);
      }
    }

    return (html: container.innerHtml, designWidth: _designWidth(container));
  }

  /// 取邮件自身的设计宽度（常见 600/640/750），用于整体缩放而不是强行 reflow。
  static double? _designWidth(dom.Element container) {
    var widest = 0.0;
    for (final element in container.querySelectorAll('table, div, center')) {
      final attribute = element.attributes['width'];
      if (attribute != null) {
        widest = math.max(widest, _pixelWidth(attribute));
      }
      final style = element.attributes['style'];
      if (style != null) {
        for (final match in _cssWidthPattern.allMatches(style)) {
          widest = math.max(widest, double.tryParse(match.group(1)!) ?? 0);
        }
      }
    }
    for (final style in container.querySelectorAll('style')) {
      for (final match in _cssWidthPattern.allMatches(style.text)) {
        widest = math.max(widest, double.tryParse(match.group(1)!) ?? 0);
      }
    }
    if (widest < 480 || widest > 1200) return null;
    return widest;
  }

  static final _cssWidthPattern = RegExp(
    r'(?:^|[;{])\s*(?:max-)?width\s*:\s*(\d{3,4})px',
    caseSensitive: false,
  );

  static double _pixelWidth(String value) {
    final match = RegExp(r'^\s*(\d{3,4})\s*(?:px)?\s*$').firstMatch(value);
    if (match == null) return 0;
    return double.tryParse(match.group(1)!) ?? 0;
  }

  /// 宽度够就按原宽度排；不够就按原宽度排好后整体缩放，避免把邮件挤变形。
  static String _bodySizing(double? designWidth, double availableWidth) {
    if (designWidth == null || availableWidth <= 0) {
      return '.body { max-width: 100%; }';
    }
    final scale = (availableWidth / designWidth).clamp(0.5, 1.0);
    if (scale >= 0.999) return '.body { max-width: 100%; }';
    return '.body { width: ${designWidth.round()}px; '
        'zoom: ${scale.toStringAsFixed(3)}; }';
  }

  /// 给邮件样式表的每条选择器加上 `.body` 前缀。
  ///
  /// 邮件模板普遍写 `body{...}`、`*{...}`、`table{width:750px}` 这类全局规则，
  /// 不隔离就会把页头、附件行和回复按钮一起改掉，出现错位。
  static String _scopeCss(String css) {
    final output = StringBuffer();
    var index = 0;
    while (index < css.length) {
      final brace = css.indexOf('{', index);
      if (brace < 0) break;
      final semicolon = css.indexOf(';', index);
      if (semicolon >= 0 && semicolon < brace) {
        // 独立的 at 语句（@import、@charset 等）没有规则块，直接丢弃。
        index = semicolon + 1;
        continue;
      }
      final close = _matchingBrace(css, brace);
      if (close < 0) break;
      final prelude = css.substring(index, brace).trim();
      final block = css.substring(brace + 1, close);
      index = close + 1;
      if (prelude.isEmpty) continue;

      if (prelude.startsWith('@')) {
        final name = prelude.toLowerCase();
        if (name.startsWith('@media') ||
            name.startsWith('@supports') ||
            name.startsWith('@layer') ||
            name.startsWith('@container')) {
          final inner = _scopeCss(block);
          if (inner.trim().isNotEmpty) output.write('$prelude{$inner}');
        } else if (name.startsWith('@keyframes')) {
          output.write('$prelude{$block}');
        }
        // @font-face、@page 等与邮件排版无关，丢弃。
        continue;
      }

      final selectors = prelude
          .split(',')
          .map(_scopeSelector)
          .where((selector) => selector.isNotEmpty)
          .join(',');
      if (selectors.isEmpty) continue;
      output.write('$selectors{$block}');
    }
    return output.toString();
  }

  static String _scopeSelector(String selector) {
    var value = selector.trim();
    if (value.isEmpty) return '';
    // 去掉 html/body/:root 前缀，否则会生成永远匹配不到的嵌套选择器。
    while (true) {
      final stripped = value.replaceFirst(
        RegExp(r'^(html|body|:root)(\s+|$)', caseSensitive: false),
        '',
      );
      if (stripped == value) break;
      value = stripped.trim();
    }
    if (value.isEmpty) return '.body';
    if (RegExp(r'^\.body(?![\w-])').hasMatch(value)) return value;
    return '.body $value';
  }

  static int _matchingBrace(String css, int open) {
    var depth = 0;
    var quote = '';
    for (var index = open; index < css.length; index++) {
      final char = css[index];
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return index;
      }
    }
    return -1;
  }

  /// 按文件头判断图片类型，data URI 缺少 MIME 时浏览器不会渲染。
  static String imageMimeType(Uint8List bytes) {
    if (bytes.length > 7 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    if (bytes.length > 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length > 11 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length > 1 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return 'image/png';
  }

  static String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }
}
