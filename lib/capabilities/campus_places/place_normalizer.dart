/// 输入安全标准化：小写、全角→半角、空白统一。
///
/// 本层只做无业务语义的文本标准化；地点编码提取与压实由
/// [PlaceInputParser] 独立完成，避免普通地点名称中的符号被破坏。
class PlaceInputNormalizer {
  const PlaceInputNormalizer();

  /// 轻度规范化后的完整文本，保留括号、星号、中文标签等语义内容。
  String normalize(String input) {
    var s = input.trim().toLowerCase();
    s = s.replaceAll("　", " ");
    final fullWidth = RegExp(r"[\uFF01-\uFF5E]");
    s = s.replaceAllMapped(
      fullWidth,
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
    );
    s = s.replaceAll(RegExp(r"[\s\u00A0\u2007\u202F\u3000]+"), " ");
    return s.trim();
  }

  /// 编码候选压实：仅移除编码内部常见的空白、连字符与下划线。
  String compactCode(String input) =>
      normalize(input).replaceAll(RegExp(r"[\s_-]+"), "");
}
