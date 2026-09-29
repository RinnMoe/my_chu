/// Shared text helpers for host pages and plugin modules.
extension TextFallback on String {
  /// Returns [fallback] when this string is empty.
  String ifEmpty(String fallback) => isEmpty ? fallback : this;

  /// Returns the trimmed string, or [fallback] when the trimmed string is
  /// empty.
  String ifBlank(String? fallback) =>
      trim().isEmpty ? (fallback ?? '') : trim();

  /// The trimmed string, or null when empty.
  String? get blankToNull {
    final value = trim();
    return value.isEmpty ? null : value;
  }
}

/// 校验语义化版本（主.次.修订，可带 `+构建号`）。非法格式返回 false。
bool isValidSemver(String value) {
  final core = value.split('+').first.trim();
  if (core.isEmpty) return false;
  final parts = core.split('.');
  if (parts.length > 3) return false;
  return parts.every((part) => part.isNotEmpty && int.tryParse(part) != null);
}

/// 比较两个语义化版本（忽略 `+构建号`）。
///
/// 返回：`a < b` 为负数；`a == b` 为 0；`a > b` 为正数。
/// 调用方应先经 [isValidSemver] 校验。
int compareSemver(String a, String b) {
  final pa = _semverParts(a);
  final pb = _semverParts(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

List<int> _semverParts(String value) {
  final core = value.split('+').first.trim();
  final parts = core.split('.');
  final out = <int>[];
  for (var i = 0; i < 3; i++) {
    out.add(i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
  return out;
}
