import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 归一化 Content-ID：去掉 `cid:` 前缀与尖括号，统一小写。
String normalizeMailCid(String value) {
  var text = value.trim();
  if (text.toLowerCase().startsWith('cid:')) {
    text = text.substring(4);
  }
  if (text.length > 2 && text.startsWith('<') && text.endsWith('>')) {
    text = text.substring(1, text.length - 1);
  }
  return text.trim().toLowerCase();
}

/// 邮件 HTML 净化。
///
/// 保留排版（`style` 属性、`<style>` 块、`class` 与表格呈现属性），删除脚本、
/// 表单、外链样式与所有事件属性。图片默认不在这里移除：渲染层会先阻断远程
/// 图片，用户显式允许后才加载。
class MailHtmlSanitizer {
  static const maxHtmlLength = 2 * 1024 * 1024;

  static const allowedTags = {
    'a',
    'b',
    'blockquote',
    'br',
    'caption',
    'code',
    'col',
    'colgroup',
    'dd',
    'div',
    'dl',
    'dt',
    'em',
    'font',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'i',
    'img',
    'li',
    'ol',
    'p',
    'pre',
    's',
    'small',
    'span',
    'strong',
    'style',
    'sub',
    'sup',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'u',
    'ul',
  };

  static const _blockedTags = {
    'applet',
    'audio',
    'base',
    'button',
    'embed',
    'form',
    'frame',
    'frameset',
    'head',
    'iframe',
    'input',
    'link',
    'meta',
    'noscript',
    'object',
    'script',
    'select',
    'textarea',
    'title',
    'video',
  };

  /// 所有元素都保留的属性：排版与语义所需，均不承载可执行内容。
  static const _globalAttributes = {
    'class',
    'style',
    'align',
    'valign',
    'dir',
    'title',
    'width',
    'height',
    'bgcolor',
  };

  /// 仅个别标签需要的属性。
  static const _tagAttributes = {
    'a': {'href'},
    'font': {'color', 'face', 'size'},
    'img': {'src', 'alt', 'border'},
    'table': {'border', 'cellpadding', 'cellspacing', 'summary'},
    'td': {'colspan', 'rowspan', 'nowrap'},
    'th': {'colspan', 'rowspan', 'nowrap'},
    'col': {'span'},
    'colgroup': {'span'},
    'ol': {'start', 'type'},
    'ul': {'type'},
    'blockquote': {'cite'},
  };

  static String sanitize(String html) {
    if (html.trim().isEmpty) return '';
    final document = html_parser.parse(html);

    // 邮件常把排版放在 head 的 <style> 里，先提到正文再统一净化。
    final body = document.body;
    if (body != null) {
      for (final style in document.querySelectorAll('head style').toList()) {
        style.remove();
        body.append(style);
      }
    }

    for (final element in document.querySelectorAll(_blockedTags.join(','))) {
      element.remove();
    }

    for (final element in document.querySelectorAll('*')) {
      final tag = element.localName ?? '';
      if (tag == 'html' || tag == 'body') continue;
      if (!allowedTags.contains(tag)) {
        _unwrap(element);
        continue;
      }
      _cleanAttributes(element, tag);
    }

    final result = body?.innerHtml.trim() ?? '';
    if (result.length <= maxHtmlLength) return result;
    final cut = result.lastIndexOf('>', maxHtmlLength);
    return cut > 0
        ? result.substring(0, cut + 1)
        : result.substring(0, maxHtmlLength);
  }

  /// 把不认识的容器标签替换为其子节点，保留内部可读内容。
  static void _unwrap(dom.Element element) {
    final parent = element.parent;
    if (parent == null) {
      element.remove();
      return;
    }
    final index = parent.nodes.indexOf(element);
    if (index < 0) return;
    final children = element.nodes.toList(growable: false);
    element.nodes.clear();
    parent.nodes.insertAll(index, children);
    element.remove();
  }

  static void _cleanAttributes(dom.Element element, String tag) {
    if (tag == 'style') {
      // 样式表标签只保留选择器与声明文本。
      final css = sanitizeCss(element.text);
      element.nodes.clear();
      element.append(dom.Text(css));
      return;
    }
    final allowed = {..._globalAttributes, ...?_tagAttributes[tag]};
    for (final name in element.attributes.keys.toList(growable: false)) {
      final lower = name.toString().toLowerCase();
      if (lower.startsWith('on') || !allowed.contains(lower)) {
        element.attributes.remove(name);
      }
    }
    if (tag == 'a') {
      final href = element.attributes['href'];
      if (href != null && !isSafeLink(href)) {
        element.attributes.remove('href');
      }
    }
    if (tag == 'img') {
      final src = element.attributes['src'];
      if (src != null && !isSafeImageSource(src)) {
        element.attributes.remove('src');
      }
    }
    final style = element.attributes['style'];
    if (style != null) {
      final cleaned = sanitizeCss(style);
      if (cleaned.trim().isEmpty) {
        element.attributes.remove('style');
      } else {
        element.attributes['style'] = cleaned;
      }
    }
  }

  /// CSS 净化：去掉可执行与可外联的写法，保留常规排版声明。
  ///
  /// 网络请求另有 CSP 兜底，这里只处理最明显的注入面。
  static String sanitizeCss(String css) {
    if (css.trim().isEmpty) return '';
    var result = css.replaceAll(
      RegExp(r'@import[^;]*(;|$)', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'expression\s*\(', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'behavior\s*:', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'-moz-binding\s*:', caseSensitive: false),
      '',
    );
    // 固定定位会让邮件内容盖住页头与操作区，一律降级为普通流。
    result = result.replaceAll(
      RegExp(r'position\s*:\s*(fixed|sticky)', caseSensitive: false),
      'position:static',
    );
    result = result.replaceAllMapped(
      RegExp(r'''url\(\s*['"]?([^)'"]*)['"]?\s*\)''', caseSensitive: false),
      (match) {
        final target = (match.group(1) ?? '').trim();
        return _isSafeCssUrl(target) ? match.group(0)! : 'none';
      },
    );
    return result;
  }

  static bool _isSafeCssUrl(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('data:image/')) return true;
    if (lower.startsWith('cid:')) return true;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  /// 只允许 http/https 与邮件内联图片。
  static bool isSafeLink(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    return uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'mailto';
  }

  static bool isSafeImageSource(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().startsWith('cid:')) return true;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }
}
