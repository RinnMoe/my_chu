import "dart:convert";

import "package:flutter/services.dart";

import "place_normalizer.dart";

/// The kind of logical destination described by a code rule.
enum PlaceCodeRuleKind { classroom, place }

PlaceCodeRuleKind _ruleKind(Object? value) {
  return value is String && value.trim().toLowerCase() == "place"
      ? PlaceCodeRuleKind.place
      : PlaceCodeRuleKind.classroom;
}

String _kindWire(PlaceCodeRuleKind kind) =>
    kind == PlaceCodeRuleKind.place ? "place" : "classroom";

/// A campus prefix is kept in the catalog so new campuses can be added
/// without changing Dart code. Rules still carry their campus id explicitly;
/// the prefix list is primarily useful to the maintainer and diagnostics.
class PlaceCodeCampusPrefix {
  final String prefix;
  final String campusId;
  final String displayName;
  final List<String> aliases;

  const PlaceCodeCampusPrefix({
    required this.prefix,
    required this.campusId,
    required this.displayName,
    this.aliases = const [],
  });

  factory PlaceCodeCampusPrefix.fromJson(Map<String, dynamic> json) {
    return PlaceCodeCampusPrefix(
      prefix: _string(json["prefix"]).toUpperCase(),
      campusId: _string(json["campus_id"] ?? json["campusId"]),
      displayName: _string(json["display_name"] ?? json["displayName"]),
      aliases: _stringList(json["aliases"]),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    "prefix": prefix,
    "campus_id": campusId,
    "display_name": displayName,
    if (aliases.isNotEmpty) "aliases": aliases,
  };
}

/// A named place target. A target is allowed to omit [placeId] while OSM
/// data is incomplete; the resolver then returns a logical, pending result.
class PlaceCodeTargetRef {
  final String? placeId;
  final String? name;
  final List<String> aliases;
  final String? block;

  const PlaceCodeTargetRef({
    this.placeId,
    this.name,
    this.aliases = const [],
    this.block,
  });

  bool get isSpecified =>
      (placeId?.trim().isNotEmpty ?? false) ||
      (name?.trim().isNotEmpty ?? false) ||
      aliases.isNotEmpty;

  factory PlaceCodeTargetRef.fromJson(Object? value) {
    if (value is String) return PlaceCodeTargetRef(name: value.trim());
    if (value is! Map) return const PlaceCodeTargetRef();
    final json = Map<String, dynamic>.from(value);
    return PlaceCodeTargetRef(
      placeId: _nullableString(json["place_id"] ?? json["placeId"]),
      name: _nullableString(json["name"]),
      aliases: _stringList(json["aliases"]),
      block: _nullableString(json["block"]),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (placeId != null && placeId!.isNotEmpty) "place_id": placeId,
    if (name != null && name!.isNotEmpty) "name": name,
    if (aliases.isNotEmpty) "aliases": aliases,
    if (block != null && block!.isNotEmpty) "block": block,
  };
}

/// A numeric field declared by a structured template.
class PlaceCodeCaptureSpec {
  final String name;
  final int width;
  final int? min;
  final int? max;

  const PlaceCodeCaptureSpec({
    required this.name,
    required this.width,
    this.min,
    this.max,
  });

  factory PlaceCodeCaptureSpec.fromJson(
    String name,
    Object? value, {
    int? fallbackWidth,
  }) {
    if (value is num) {
      return PlaceCodeCaptureSpec(name: name, width: value.toInt());
    }
    if (value is Map) {
      final json = Map<String, dynamic>.from(value);
      return PlaceCodeCaptureSpec(
        name: name,
        width: _int(json["width"]) ?? fallbackWidth ?? 1,
        min: _int(json["min"]),
        max: _int(json["max"]),
      );
    }
    return PlaceCodeCaptureSpec(name: name, width: fallbackWidth ?? 1);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    "width": width,
    if (min != null) "min": min,
    if (max != null) "max": max,
  };
}

/// A successful structured-template match.
class PlaceCodeRuleMatch {
  final PlaceCodeRuleOverride rule;
  final String code;
  final Map<String, String> captures;

  const PlaceCodeRuleMatch({
    required this.rule,
    required this.code,
    required this.captures,
  });

  String? operator [](String name) => captures[name];

  int? intValue(String name) => int.tryParse(captures[name] ?? "");
}

/// One globally maintained code-to-place rule.
///
/// Rules use named numeric captures, for example
/// `WM{zone:1}{floor:1}{room:2}`. Only the v2 structured catalog format is
/// accepted at the data boundary.
class PlaceCodeRuleOverride {
  final String id;
  final String pattern;
  final PlaceCodeRuleKind kind;
  final String campusId;
  final PlaceCodeTargetRef? placeTarget;
  final PlaceCodeTargetRef? buildingTarget;
  final String? zoneCapture;
  final Map<String, PlaceCodeTargetRef> zoneTargets;
  final Map<String, String> fieldCaptures;
  final Map<String, PlaceCodeCaptureSpec> captures;

  final int priority;
  final bool enabled;
  final String? note;
  final String? roomLabel;

  const PlaceCodeRuleOverride({
    required this.id,
    required this.pattern,
    required this.campusId,
    this.kind = PlaceCodeRuleKind.classroom,
    this.placeTarget,
    this.buildingTarget,
    this.zoneCapture,
    this.zoneTargets = const {},
    this.fieldCaptures = const {},
    this.captures = const {},
    this.priority = 0,
    this.enabled = true,
    this.note,
    this.roomLabel,
  });

  factory PlaceCodeRuleOverride.fromJson(Map<String, dynamic> json) {
    final pattern = _string(json["pattern"]);
    if (pattern.isEmpty || _containsLegacyRuleFields(json, pattern)) {
      throw const FormatException("编码规则必须使用 v2 structured 格式");
    }
    final rawTarget = json["target"];
    if (rawTarget != null && rawTarget is! Map) {
      throw const FormatException("编码规则 target 格式无效");
    }
    final target =
        rawTarget is Map
            ? Map<String, dynamic>.from(rawTarget)
            : const <String, dynamic>{};

    final buildingValue = target["building"];
    final placeValue = target["place"];
    final building =
        buildingValue == null
            ? null
            : PlaceCodeTargetRef.fromJson(buildingValue);
    final place =
        placeValue == null ? null : PlaceCodeTargetRef.fromJson(placeValue);

    final rawZone = target["zone"];
    String? zoneCapture;
    Map<String, PlaceCodeTargetRef> zoneTargets = const {};
    if (rawZone is Map) {
      final zoneJson = Map<String, dynamic>.from(rawZone);
      zoneCapture = _nullableString(zoneJson["capture"]);
      final map = zoneJson["map"];
      if (map is Map) {
        zoneTargets = <String, PlaceCodeTargetRef>{
          for (final entry in map.entries)
            entry.key.toString(): PlaceCodeTargetRef.fromJson(entry.value),
        };
      }
    }

    final fields = <String, String>{};
    final rawFields = target["fields"];
    if (rawFields is Map) {
      for (final entry in rawFields.entries) {
        final value = _nullableString(entry.value);
        if (value != null) fields[entry.key.toString()] = value;
      }
    }
    if (zoneCapture != null) fields.putIfAbsent("zone", () => zoneCapture!);

    final parsedCaptures = _captureSpecsFromPattern(_string(json["pattern"]));
    final rawCaptureConfig = json["captures"];
    if (rawCaptureConfig is Map) {
      for (final entry in rawCaptureConfig.entries) {
        final name = entry.key.toString();
        final fallback = parsedCaptures[name]?.width;
        parsedCaptures[name] = PlaceCodeCaptureSpec.fromJson(
          name,
          entry.value,
          fallbackWidth: fallback,
        );
      }
    }

    return PlaceCodeRuleOverride(
      id: _string(json["id"]),
      pattern: pattern,
      kind: _ruleKind(json["kind"]),
      campusId: _string(json["campus_id"] ?? json["campusId"]),
      placeTarget: place,
      buildingTarget: building,
      zoneCapture: zoneCapture,
      zoneTargets: Map.unmodifiable(zoneTargets),
      fieldCaptures: Map.unmodifiable(fields),
      captures: Map.unmodifiable(parsedCaptures),
      priority: _int(json["priority"]) ?? 0,
      enabled: json["enabled"] is bool ? json["enabled"] as bool : true,
      note: _nullableString(json["note"]),
      roomLabel: _nullableString(json["room_label"] ?? json["roomLabel"]),
    );
  }

  Map<String, dynamic> toJson() {
    final target = <String, dynamic>{};
    if (placeTarget?.isSpecified ?? false) {
      target["place"] = placeTarget!.toJson();
    }
    if (buildingTarget?.isSpecified ?? false) {
      target["building"] = buildingTarget!.toJson();
    }
    if (zoneCapture != null || zoneTargets.isNotEmpty) {
      target["zone"] = <String, dynamic>{
        if (zoneCapture != null) "capture": zoneCapture,
        if (zoneTargets.isNotEmpty)
          "map": <String, dynamic>{
            for (final entry in zoneTargets.entries)
              entry.key: entry.value.toJson(),
          },
      };
    }
    if (fieldCaptures.isNotEmpty) target["fields"] = fieldCaptures;
    return <String, dynamic>{
      "id": id,
      "pattern": pattern,
      "kind": _kindWire(kind),
      "campus_id": campusId,
      if (target.isNotEmpty) "target": target,
      if (captures.isNotEmpty)
        "captures": <String, dynamic>{
          for (final entry in captures.entries) entry.key: entry.value.toJson(),
        },
      "priority": priority,
      "enabled": enabled,
      if (note != null && note!.isNotEmpty) "note": note,
      if (roomLabel != null && roomLabel!.isNotEmpty) "room_label": roomLabel,
    };
  }

  /// Match a compact or separator-containing code and return named fields.
  PlaceCodeRuleMatch? match(String candidate) {
    final value = const PlaceInputNormalizer().compactCode(candidate);
    final structured = _structuredPattern;
    if (structured != null) {
      final match = structured.firstMatch(value);
      if (match == null || match.group(0) != value) return null;
      final values = <String, String>{};
      final inferredCaptures = _captureSpecsFromPattern(pattern);
      var group = 1;
      for (final name in _captureNamesInPattern) {
        final spec = captures[name] ?? inferredCaptures[name];
        if (spec == null) continue;
        final captured = match.group(group++);
        if (captured == null || !_inRange(spec, captured)) return null;
        values[spec.name] = captured;
      }
      return PlaceCodeRuleMatch(rule: this, code: value, captures: values);
    }
    final literal = const PlaceInputNormalizer().compactCode(pattern);
    return value == literal
        ? PlaceCodeRuleMatch(rule: this, code: value, captures: const {})
        : null;
  }

  /// Returns true when this rule applies to a normalized code candidate.
  bool matches(String candidate) => match(candidate) != null;

  /// More literal characters and longer fixed templates are more specific.
  int get specificity {
    final literal = pattern.replaceAll(
      RegExp(r"\{[A-Za-z][A-Za-z0-9_]*\s*:\s*\d+\}"),
      "",
    );
    return const PlaceInputNormalizer().compactCode(literal).length;
  }

  RegExp? get _structuredPattern {
    if (!pattern.contains("{")) return null;
    final source = StringBuffer("^");
    var cursor = 0;
    final tokenPattern = RegExp(r"\{([A-Za-z][A-Za-z0-9_]*)\s*:\s*(\d+)\}");
    final matches = tokenPattern.allMatches(pattern);
    if (matches.isEmpty) return null;
    for (final token in matches) {
      final literal = const PlaceInputNormalizer().compactCode(
        pattern.substring(cursor, token.start),
      );
      source.write(RegExp.escape(literal));
      source.write(r"(\d{");
      source.write(token.group(2));
      source.write("})");
      cursor = token.end;
    }
    final tail = const PlaceInputNormalizer().compactCode(
      pattern.substring(cursor),
    );
    source.write(RegExp.escape(tail));
    source.write(r"$");
    return RegExp(source.toString(), caseSensitive: false);
  }

  List<String> get _captureNamesInPattern {
    final names = <String>[];
    final tokenPattern = RegExp(r"\{([A-Za-z][A-Za-z0-9_]*)\s*:\s*\d+\}");
    for (final match in tokenPattern.allMatches(pattern)) {
      final name = match.group(1)!.toLowerCase();
      if (!names.contains(name)) names.add(name);
    }
    return names;
  }

  static bool _inRange(PlaceCodeCaptureSpec spec, String value) {
    final number = int.tryParse(value);
    if (number == null) return false;
    if (spec.min != null && number < spec.min!) return false;
    if (spec.max != null && number > spec.max!) return false;
    return true;
  }
}

/// The complete v2 rules document. The public repository still exposes
/// [PlaceCodeRulesRepository.load] for callers that only need the rules.
class PlaceCodeRuleCatalog {
  final int schemaVersion;
  final List<PlaceCodeCampusPrefix> campusPrefixes;
  final List<PlaceCodeRuleOverride> rules;

  const PlaceCodeRuleCatalog({
    this.schemaVersion = 2,
    this.campusPrefixes = const [],
    this.rules = const [],
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    "schemaVersion": 2,
    "campusPrefixes": [for (final prefix in campusPrefixes) prefix.toJson()],
    "rules": [for (final rule in rules) rule.toJson()],
  };
}

/// Loads and decodes the bundled code-rule catalog.
///
/// Production code rules are part of the immutable semantic release. This
/// repository remains the bundled fallback loader and does not own a separate
/// network or cache distribution path.
class PlaceCodeRulesRepository {
  static const String assetPath = "assets/maps/place_code_rules.json";

  final Future<String> Function(String path) loadText;

  PlaceCodeRulesRepository({Future<String> Function(String path)? loadText})
    : loadText = loadText ?? rootBundle.loadString;

  Future<List<PlaceCodeRuleOverride>> load() async =>
      (await loadCatalog()).rules;

  Future<PlaceCodeRuleCatalog> loadCatalog() async {
    try {
      return decodeCatalog(await loadText(assetPath));
    } catch (_) {
      return const PlaceCodeRuleCatalog();
    }
  }

  /// Decodes a published release snapshot without consulting the local asset
  /// or a separate per-service distribution path.
  static PlaceCodeRuleCatalog decodeCatalog(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException("编码规则配置不是 JSON 对象");
    final json = Map<String, dynamic>.from(decoded);
    final version = _int(json["schemaVersion"]);
    if (version != 2) {
      throw const FormatException("编码规则仅支持 schemaVersion 2");
    }
    final rawRules = json["rules"];
    if (rawRules is! List) {
      throw const FormatException("编码规则列表格式无效");
    }
    final rules = <PlaceCodeRuleOverride>[];
    final seen = <String>{};
    for (final raw in rawRules) {
      if (raw is! Map) {
        throw const FormatException("编码规则条目格式无效");
      }
      final rule = PlaceCodeRuleOverride.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (rule.id.isEmpty || rule.pattern.isEmpty || rule.campusId.isEmpty) {
        throw const FormatException("编码规则缺少必要字段");
      }
      if (!seen.add(rule.id)) {
        throw const FormatException("编码规则 ID 重复");
      }
      rules.add(rule);
    }
    rules.sort(_compareRules);
    final prefixes = <PlaceCodeCampusPrefix>[];
    final rawPrefixes = json["campusPrefixes"] ?? json["campus_prefixes"];
    if (rawPrefixes is List) {
      for (final raw in rawPrefixes) {
        if (raw is Map) {
          final prefix = PlaceCodeCampusPrefix.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (prefix.prefix.isNotEmpty && prefix.campusId.isNotEmpty) {
            prefixes.add(prefix);
          }
        }
      }
    }
    return PlaceCodeRuleCatalog(
      schemaVersion: 2,
      campusPrefixes: List.unmodifiable(prefixes),
      rules: List.unmodifiable(rules),
    );
  }

  static int _compareRules(PlaceCodeRuleOverride a, PlaceCodeRuleOverride b) {
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    final specificity = b.specificity.compareTo(a.specificity);
    if (specificity != 0) return specificity;
    return a.id.compareTo(b.id);
  }
}

Map<String, PlaceCodeCaptureSpec> _captureSpecsFromPattern(String pattern) {
  final result = <String, PlaceCodeCaptureSpec>{};
  final regex = RegExp(r"\{([A-Za-z][A-Za-z0-9_]*)\s*:\s*(\d+)\}");
  for (final match in regex.allMatches(pattern)) {
    final name = match.group(1)!.toLowerCase();
    result.putIfAbsent(
      name,
      () => PlaceCodeCaptureSpec(
        name: name,
        width: int.tryParse(match.group(2)!) ?? 1,
      ),
    );
  }
  return result;
}

bool _containsLegacyRuleFields(Map<String, dynamic> json, String pattern) {
  const legacyKeys = <String>{
    "building_place_id",
    "buildingPlaceId",
    "zone_place_id",
    "zonePlaceId",
    "building_name",
    "buildingName",
    "zone_name",
    "zoneName",
    "zone",
    "block",
    "zone_capture",
    "zoneCapture",
    "fields",
  };
  if (legacyKeys.any(json.containsKey)) return true;
  return pattern.contains("*");
}

String _string(Object? value) => value is String ? value.trim() : "";

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return value is String ? int.tryParse(value.trim()) : null;
}

List<String> _stringList(Object? value) =>
    value is List
        ? value
            .map(_string)
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const [];
