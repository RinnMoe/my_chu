import "place_code_rule_overrides.dart";
import "place_normalizer.dart";

/// 统一地点输入解析结果。
///
/// [canonicalText] 保留输入语义；[codeCandidates] 是可靠的校园地点编码
/// 候选；[textCandidates] 用于名称、别名与关键词搜索。
class NormalizedPlaceInput {
  final String canonicalText;
  final List<String> codeCandidates;
  final List<String> textCandidates;

  const NormalizedPlaceInput({
    required this.canonicalText,
    this.codeCandidates = const [],
    this.textCandidates = const [],
  });
}

/// 统一地点输入兼容层：从任意业务原始文本中提取结构化候选。
///
/// 考试、课表和地图搜索都通过本解析器进入 [PlaceResolver]。
class PlaceInputParser {
  final PlaceInputNormalizer normalizer;

  const PlaceInputParser({this.normalizer = const PlaceInputNormalizer()});

  // This deliberately has no campus/business prefix list. It only extracts
  // plausible code tokens; the configured v2 rules decide whether a token is
  // a real location code. The rule-token variant also permits Chinese literal
  // markers such as the 阶 in Y阶4.
  static final RegExp _codePattern = RegExp(
    r"(?<![A-Za-z0-9])([A-Za-z]{1,8}(?:[\s_-]*\d){1,10})(?![A-Za-z0-9])",
    caseSensitive: false,
  );
  static final RegExp _ruleTokenPattern = RegExp(
    r"(?<![A-Za-z0-9])([A-Za-z]{1,8}(?:[\s_-]*[A-Za-z0-9\u4e00-\u9fff]){0,12})(?![A-Za-z0-9])",
    caseSensitive: false,
  );

  static const Set<String> _locationLabels = {"地点", "教室", "考场", "考试地点"};
  static final RegExp _textSplitPattern = RegExp(
    r"[\s,，;；:：()（）\[\]【】<>《》/\\|*#]+",
  );

  NormalizedPlaceInput parse(
    String input, {
    Iterable<PlaceCodeRuleOverride> codeOverrides = const [],
  }) {
    final raw = input.trim();
    final canonical = normalizer.normalize(raw);
    final codes = <String>[..._extractCodes(canonical)];
    for (final match in _ruleTokenPattern.allMatches(canonical)) {
      final token = normalizer.compactCode(match.group(1)!);
      if (token.isEmpty) continue;
      if (codeOverrides.any((rule) => rule.enabled && rule.matches(token)) &&
          !codes.contains(token)) {
        codes.add(token);
      }
    }
    final initialTexts = _extractTextCandidates(canonical, codes);
    for (final candidate in initialTexts) {
      if (codeOverrides.any(
        (rule) => rule.enabled && rule.matches(candidate),
      )) {
        final compact = normalizer.compactCode(candidate);
        if (compact.isNotEmpty && !codes.contains(compact)) codes.add(compact);
      }
    }
    final texts = _extractTextCandidates(canonical, codes);
    return NormalizedPlaceInput(
      canonicalText: canonical,
      codeCandidates: codes,
      textCandidates: texts,
    );
  }

  /// 判断一段文本是否含可提取的校园地点编码，供课表地点行识别使用。
  bool hasCodeCandidate(
    String input, {
    Iterable<PlaceCodeRuleOverride> codeOverrides = const [],
  }) => parse(input, codeOverrides: codeOverrides).codeCandidates.isNotEmpty;

  List<String> _extractCodes(String canonical) {
    final codes = <String>[];
    for (final match in _codePattern.allMatches(canonical)) {
      final compact = normalizer.compactCode(match.group(0)!);
      if (compact.isNotEmpty && !codes.contains(compact)) codes.add(compact);
    }
    return List.unmodifiable(codes);
  }

  List<String> _extractTextCandidates(String canonical, List<String> codes) {
    final texts = <String>[];
    if (canonical.isNotEmpty) texts.add(canonical);
    for (final rawToken in canonical.split(_textSplitPattern)) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;
      if (token.length < 2) continue;
      if (_locationLabels.contains(token)) continue;
      if (codes.contains(token) ||
          codes.contains(normalizer.compactCode(token))) {
        continue;
      }
      if (!texts.contains(token)) texts.add(token);
    }
    return List.unmodifiable(texts);
  }
}
