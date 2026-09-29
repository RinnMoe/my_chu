import "campus_places_models.dart";
import "campus_registry.dart";
import "place_code_rule_overrides.dart";
import "place_input_parser.dart";
import "place_normalizer.dart";
import "place_search_index.dart";

/// 统一地点请求（业务侧）。
class UnifiedPlaceRequest {
  final String? campusId;
  final String? placeId;
  final String? classroomId;
  final String? rawText;
  final bool openInfoCard;
  final bool allowCampusSwitch;
  final bool showExternalNavigation;

  const UnifiedPlaceRequest({
    this.campusId,
    this.placeId,
    this.classroomId,
    this.rawText,
    this.openInfoCard = true,
    this.allowCampusSwitch = true,
    this.showExternalNavigation = true,
  });

  UnifiedPlaceRequest copyWith({
    String? campusId,
    String? placeId,
    String? classroomId,
    String? rawText,
    bool? openInfoCard,
    bool? allowCampusSwitch,
    bool? showExternalNavigation,
  }) => UnifiedPlaceRequest(
    campusId: campusId ?? this.campusId,
    placeId: placeId ?? this.placeId,
    classroomId: classroomId ?? this.classroomId,
    rawText: rawText ?? this.rawText,
    openInfoCard: openInfoCard ?? this.openInfoCard,
    allowCampusSwitch: allowCampusSwitch ?? this.allowCampusSwitch,
    showExternalNavigation:
        showExternalNavigation ?? this.showExternalNavigation,
  );
}

/// 地点身份（campus_id + place_id）。
class CampusPlaceId {
  final String campusId;
  final String placeId;

  const CampusPlaceId({required this.campusId, required this.placeId});

  @override
  bool operator ==(Object other) =>
      other is CampusPlaceId &&
      other.campusId == campusId &&
      other.placeId == placeId;

  @override
  int get hashCode => Object.hash(campusId, placeId);

  @override
  String toString() => "CampusPlaceId($campusId/$placeId)";
}

/// 解析歧义时供用户选择的地点。
class PlaceCandidate {
  final String campusId;
  final String campusName;
  final String placeId;
  final String label;

  const PlaceCandidate({
    required this.campusId,
    required this.campusName,
    required this.placeId,
    required this.label,
  });
}

/// 解析状态。
enum PlaceResolutionStatus { resolved, ambiguous, unresolved, campusNotFound }

/// 统一地点解析结果。
class PlaceResolutionResult {
  final PlaceResolutionStatus status;
  final String? campusId;
  final CampusPlaceId? placeId;
  final CampusPlace? place;
  final CampusClassroom? classroom;
  final List<PlaceCandidate> candidates;
  final String? message;

  const PlaceResolutionResult({
    required this.status,
    this.campusId,
    this.placeId,
    this.place,
    this.classroom,
    this.candidates = const [],
    this.message,
  });

  factory PlaceResolutionResult.resolved({
    required CampusPlaceId placeId,
    String? campusId,
    CampusPlace? place,
    CampusClassroom? classroom,
  }) => PlaceResolutionResult(
    status: PlaceResolutionStatus.resolved,
    campusId: campusId ?? placeId.campusId,
    placeId: placeId,
    place: place,
    classroom: classroom,
  );

  /// 已识别到校区/逻辑教室，但该校区暂无地点主数据。
  factory PlaceResolutionResult.resolvedLogical({
    required String campusId,
    CampusClassroom? classroom,
  }) => PlaceResolutionResult(
    status: PlaceResolutionStatus.resolved,
    campusId: campusId,
    classroom: classroom,
  );

  factory PlaceResolutionResult.ambiguous({
    required List<PlaceCandidate> candidates,
  }) => PlaceResolutionResult(
    status: PlaceResolutionStatus.ambiguous,
    candidates: candidates,
  );

  factory PlaceResolutionResult.unresolved({String? message}) =>
      PlaceResolutionResult(
        status: PlaceResolutionStatus.unresolved,
        message: message ?? "未识别该地点",
      );

  factory PlaceResolutionResult.campusNotFound({required String campusId}) =>
      PlaceResolutionResult(
        status: PlaceResolutionStatus.campusNotFound,
        campusId: campusId,
        message: "校区未配置：$campusId",
      );
}

typedef _Scoped = (CampusEntry, CampusPlacesData);
typedef _Hit = ({CampusEntry campus, CampusPlace place});

/// 统一地点解析器：按任务书十三/十五优先级解析。
class PlaceResolver {
  final PlaceInputNormalizer normalizer;
  final PlaceInputParser inputParser;

  const PlaceResolver({
    this.normalizer = const PlaceInputNormalizer(),
    this.inputParser = const PlaceInputParser(),
  });

  PlaceResolutionResult resolve({
    required UnifiedPlaceRequest request,
    required CampusRegistry registry,
    required Map<String, CampusPlacesData> placesByCampus,
    String? currentCampusId,
    List<PlaceCodeRuleOverride> codeOverrides = const [],
    Map<String, PlaceSearchIndex>? searchIndexesByCampus,
  }) {
    final explicitClassroomId = request.classroomId?.trim();
    if (explicitClassroomId != null && explicitClassroomId.isNotEmpty) {
      final classroomCampusId =
          request.campusId ??
          _campusForPlaceId(request.placeId, registry, placesByCampus);
      final classroomScope = _scopedCampuses(
        classroomCampusId,
        registry,
        placesByCampus,
      );
      if (classroomScope == null) {
        return PlaceResolutionResult.campusNotFound(
          campusId: classroomCampusId ?? "",
        );
      }
      final normalizedClassroomId = normalizer.normalize(explicitClassroomId);
      final classroom = _resolveExactClassroom(
        normalizedClassroomId,
        classroomScope,
      );
      if (classroom != null) return classroom;

      // Schedule callers provide an explicit classroom ID, while some newer
      // buildings are represented by declarative code rules instead of an
      // enumerated classroom list. Resolve those IDs through classroom rules
      // without allowing a place-only rule to reinterpret the request.
      final classroomRules = codeOverrides
          .where((rule) => rule.kind == PlaceCodeRuleKind.classroom)
          .toList(growable: false);
      final ruleClassroom = _resolveCodeOverride(
        normalizedClassroomId,
        classroomScope,
        classroomRules,
      );
      if (ruleClassroom != null) return ruleClassroom;

      return PlaceResolutionResult.unresolved(message: "未识别该教室编号");
    }

    if (request.placeId != null && request.placeId!.isNotEmpty) {
      return _resolveDirect(request, registry, placesByCampus);
    }

    final scoped = _scopedCampuses(request.campusId, registry, placesByCampus);
    if (scoped == null) {
      return PlaceResolutionResult.campusNotFound(
        campusId: request.campusId ?? "",
      );
    }

    final input = request.rawText?.trim() ?? "";
    if (input.isNotEmpty) {
      final literalClassroom = _resolveExactClassroom(
        normalizer.normalize(input),
        scoped,
      );
      if (literalClassroom != null) return literalClassroom;
    }
    final parsed = inputParser.parse(input, codeOverrides: codeOverrides);
    if (parsed.canonicalText.isEmpty) {
      return PlaceResolutionResult.unresolved(message: "缺少地点信息");
    }

    for (final code in parsed.codeCandidates) {
      final result = _tryCodeCandidate(code, scoped, codeOverrides);
      if (result != null) return result;
    }

    final textResult = _tryTextCandidates(
      parsed.textCandidates,
      scoped,
      currentCampusId,
      searchIndexesByCampus: searchIndexesByCampus,
    );
    if (textResult != null) return textResult;

    return PlaceResolutionResult.unresolved(message: "未识别该地点，请检查输入或选择相近地点");
  }

  // ---- 内部工具 ----

  PlaceResolutionResult? _tryCodeCandidate(
    String candidate,
    List<_Scoped> scoped,
    List<PlaceCodeRuleOverride> codeOverrides,
  ) {
    // 人工确认的具体教室映射优先于编码规则。
    final classroomExact = _resolveExactClassroom(candidate, scoped);
    if (classroomExact != null) return classroomExact;

    // Configured rules resolve against the current campus place asset.
    final overrideResult = _resolveCodeOverride(
      candidate,
      scoped,
      codeOverrides,
    );
    if (overrideResult != null) return overrideResult;

    // 外部编码精确匹配。
    final codeHits = <_Hit>[];
    for (final (campus, data) in scoped) {
      for (final place in data.places) {
        if (!place.enabled || !place.searchable) continue;
        if (place.externalCodes.any((code) => _codeMatches(code, candidate))) {
          codeHits.add((campus: campus, place: place));
        }
      }
    }
    final codeResult = _fromHits(codeHits);
    if (codeResult != null) return codeResult;

    return null;
  }

  PlaceResolutionResult? _tryTextCandidates(
    List<String> textCandidates,
    List<_Scoped> scoped,
    String? currentCampusId, {
    Map<String, PlaceSearchIndex>? searchIndexesByCampus,
  }) {
    for (final candidate in textCandidates) {
      // 名称精确匹配。
      final nameHits = _matchWhere(
        scoped,
        (place) =>
            normalizer.normalize(place.name) == candidate ||
            (place.shortName != null &&
                place.shortName!.isNotEmpty &&
                normalizer.normalize(place.shortName!) == candidate),
      );
      final nameResult = _fromHits(nameHits);
      if (nameResult != null) return nameResult;

      // 别名精确匹配。
      final aliasHits = <_Hit>[];
      for (final (campus, data) in scoped) {
        for (final place in data.places) {
          if (!place.enabled || !place.searchable) continue;
          final matched =
              place.aliases
                  .where((a) => normalizer.normalize(a) == candidate)
                  .isNotEmpty;
          if (matched) {
            aliasHits.add((campus: campus, place: place));
          }
        }
      }
      final aliasResult = _fromHits(aliasHits);
      if (aliasResult != null) return aliasResult;

      final externalCodeHits = _matchWhere(
        scoped,
        (place) =>
            place.externalCodes.any((code) => _codeMatches(code, candidate)),
      );
      final externalCodeResult = _fromHits(externalCodeHits);
      if (externalCodeResult != null) return externalCodeResult;

      // 关键词搜索：当前校区优先，其次全部校区。
      final keywordHits = <_Hit>[];
      if (currentCampusId != null) {
        for (final (campus, data) in scoped) {
          if (campus.campusId != currentCampusId) continue;
          keywordHits.addAll(
            _keywordHits(
              campus,
              data,
              candidate,
              index: searchIndexesByCampus?[campus.campusId],
            ),
          );
        }
      }
      if (keywordHits.isEmpty) {
        for (final (campus, data) in scoped) {
          keywordHits.addAll(
            _keywordHits(
              campus,
              data,
              candidate,
              index: searchIndexesByCampus?[campus.campusId],
            ),
          );
        }
      }
      final keywordResult = _fromHits(keywordHits);
      if (keywordResult != null) return keywordResult;
    }
    return null;
  }

  bool _codeMatches(String storedCode, String candidate) =>
      normalizer.compactCode(storedCode) == normalizer.compactCode(candidate);

  List<_Scoped>? _scopedCampuses(
    String? campusId,
    CampusRegistry registry,
    Map<String, CampusPlacesData> placesByCampus,
  ) {
    if (campusId != null) {
      final campus = registry.byId(campusId);
      if (campus == null) return null;
      final data =
          placesByCampus[campusId] ?? CampusPlacesData(campusId: campusId);
      return [(campus, data)];
    }
    final result = <_Scoped>[];
    for (final campus in registry.enabledCampuses) {
      final data =
          placesByCampus[campus.campusId] ??
          CampusPlacesData(campusId: campus.campusId);
      result.add((campus, data));
    }
    return result;
  }

  String? _campusForPlaceId(
    String? placeId,
    CampusRegistry registry,
    Map<String, CampusPlacesData> placesByCampus,
  ) {
    if (placeId == null || placeId.isEmpty) return null;
    for (final campus in registry.enabledCampuses) {
      if (placesByCampus[campus.campusId]?.placeById(placeId) != null) {
        return campus.campusId;
      }
    }
    return null;
  }

  PlaceResolutionResult? _fromHits(List<_Hit> hits) {
    if (hits.isEmpty) return null;
    if (hits.length == 1) {
      final hit = hits.first;
      return PlaceResolutionResult.resolved(
        placeId: CampusPlaceId(
          campusId: hit.campus.campusId,
          placeId: hit.place.placeId,
        ),
        place: hit.place,
      );
    }
    return PlaceResolutionResult.ambiguous(
      candidates: [
        for (final hit in hits)
          PlaceCandidate(
            campusId: hit.campus.campusId,
            campusName: hit.campus.displayName,
            placeId: hit.place.placeId,
            label: hit.place.name,
          ),
      ],
    );
  }

  List<_Hit> _matchWhere(
    List<_Scoped> scoped,
    bool Function(CampusPlace) test,
  ) {
    final hits = <_Hit>[];
    for (final (campus, data) in scoped) {
      for (final place in data.places) {
        if (!place.enabled || !place.searchable) continue;
        if (test(place)) {
          hits.add((campus: campus, place: place));
        }
      }
    }
    return hits;
  }

  List<_Hit> _keywordHits(
    CampusEntry campus,
    CampusPlacesData data,
    String normalized, {
    PlaceSearchIndex? index,
  }) {
    final searchIndex = index ?? PlaceSearchIndex(data: data);
    return searchIndex
        .keywordMatches(normalized)
        .map((place) => (campus: campus, place: place))
        .toList(growable: false);
  }

  PlaceResolutionResult? _resolveCodeOverride(
    String candidate,
    List<_Scoped> scoped,
    List<PlaceCodeRuleOverride> overrides,
  ) {
    final matching =
        <({PlaceCodeRuleOverride rule, PlaceCodeRuleMatch match})>[];
    for (final rule in overrides) {
      if (!rule.enabled) continue;
      final match = rule.match(candidate);
      if (match != null) matching.add((rule: rule, match: match));
    }
    if (matching.isEmpty) return null;
    matching.sort(
      (a, b) =>
          b.rule.priority.compareTo(a.rule.priority) != 0
              ? b.rule.priority.compareTo(a.rule.priority)
              : b.rule.specificity.compareTo(a.rule.specificity) != 0
              ? b.rule.specificity.compareTo(a.rule.specificity)
              : a.rule.id.compareTo(b.rule.id),
    );

    for (final entry in matching) {
      final rule = entry.rule;
      final match = entry.match;
      for (final (campus, data) in scoped) {
        if (campus.campusId != rule.campusId) continue;
        if (rule.kind == PlaceCodeRuleKind.place) {
          final target = rule.placeTarget;
          final place = _findPlaceTarget(data, target);
          if (place != null) {
            return PlaceResolutionResult.resolved(
              placeId: CampusPlaceId(
                campusId: campus.campusId,
                placeId: place.placeId,
              ),
              place: place,
            );
          }
          return PlaceResolutionResult.resolvedLogical(
            campusId: campus.campusId,
          );
        }

        final buildingTarget = rule.buildingTarget;
        final building = _findPlaceTarget(data, buildingTarget);
        final zoneName = _captureValue(rule, match, "zone");
        final effectiveZoneName =
            zoneName ??
            (rule.zoneTargets.length == 1
                ? rule.zoneTargets.keys.single
                : null);
        final zoneTarget =
            effectiveZoneName == null
                ? null
                : rule.zoneTargets[effectiveZoneName] ??
                    rule.zoneTargets["${int.tryParse(effectiveZoneName) ?? -1}"];
        final zone = _findPlaceTarget(data, zoneTarget);
        final classroom = CampusClassroom(
          classroomId: match.code,
          campusId: rule.campusId,
          buildingPlaceId: building?.placeId ?? "",
          zonePlaceId: zone?.placeId,
          block: zoneTarget?.block ?? buildingTarget?.block,
          zone: int.tryParse(effectiveZoneName ?? ""),
          floor: int.tryParse(_captureValue(rule, match, "floor") ?? ""),
          roomNo: _captureValue(rule, match, "room") ?? "",
          roomLabel: rule.roomLabel,
          verified: true,
        );
        final highlight = zone ?? building;
        if (highlight != null) {
          return PlaceResolutionResult.resolved(
            placeId: CampusPlaceId(
              campusId: campus.campusId,
              placeId: highlight.placeId,
            ),
            place: highlight,
            classroom: classroom,
          );
        }
        return PlaceResolutionResult.resolvedLogical(
          campusId: campus.campusId,
          classroom: classroom,
        );
      }
    }
    return null;
  }

  String? _captureValue(
    PlaceCodeRuleOverride rule,
    PlaceCodeRuleMatch match,
    String field,
  ) {
    final name = rule.fieldCaptures[field] ?? field;
    return match.captures[name] ?? match.captures[field];
  }

  CampusPlace? _findPlaceTarget(
    CampusPlacesData data,
    PlaceCodeTargetRef? target,
  ) {
    if (target == null) return null;
    if (target.placeId != null && target.placeId!.isNotEmpty) {
      final byId = data.placeById(target.placeId!);
      if (byId != null) return byId;
    }
    if (target.name != null && target.name!.isNotEmpty) {
      final byName = _findPlaceByName(data, target.name!);
      if (byName != null) return byName;
      final byAlias = _findPlaceByAlias(data, target.name!);
      if (byAlias != null) return byAlias;
    }
    for (final alias in target.aliases) {
      final byAlias = _findPlaceByAlias(data, alias);
      if (byAlias != null) return byAlias;
    }
    return null;
  }

  PlaceResolutionResult? _resolveExactClassroom(
    String normalized,
    List<_Scoped> scoped,
  ) {
    for (final (_, data) in scoped) {
      final classroom = data.classroomByNormalizedCode(normalized);
      if (classroom == null) continue;
      return _resolveClassroomToPlace(classroom, data);
    }
    return null;
  }

  PlaceResolutionResult _resolveClassroomToPlace(
    CampusClassroom classroom,
    CampusPlacesData data,
  ) {
    final zone =
        classroom.zonePlaceId == null
            ? null
            : data.placeById(classroom.zonePlaceId!);
    final building =
        classroom.buildingPlaceId.isEmpty
            ? null
            : data.placeById(classroom.buildingPlaceId);
    final highlight = zone ?? building;
    if (highlight != null) {
      return PlaceResolutionResult.resolved(
        placeId: CampusPlaceId(
          campusId: classroom.campusId,
          placeId: highlight.placeId,
        ),
        place: highlight,
        classroom: classroom,
      );
    }
    // 地点主数据尚未配置时仍保留“已识别”状态，由控制器保留逻辑信息卡。
    return PlaceResolutionResult.resolvedLogical(
      campusId: classroom.campusId,
      classroom: classroom,
    );
  }

  CampusPlace? _findPlaceByName(CampusPlacesData data, String name) {
    final normalized = normalizer.normalize(name);
    for (final place in data.places) {
      if (!place.enabled) continue;
      if (normalizer.normalize(place.name) == normalized) return place;
    }
    return null;
  }

  CampusPlace? _findPlaceByAlias(CampusPlacesData data, String alias) {
    final normalized = normalizer.normalize(alias);
    for (final place in data.places) {
      if (!place.enabled) continue;
      if (place.aliases.any((a) => normalizer.normalize(a) == normalized)) {
        return place;
      }
    }
    return null;
  }

  PlaceResolutionResult _resolveDirect(
    UnifiedPlaceRequest request,
    CampusRegistry registry,
    Map<String, CampusPlacesData> placesByCampus,
  ) {
    final campusId = request.campusId;
    if (campusId != null) {
      final data = placesByCampus[campusId];
      if (data == null) {
        return PlaceResolutionResult.campusNotFound(campusId: campusId);
      }
      final place = data.placeById(request.placeId!);
      if (place == null) {
        return PlaceResolutionResult.unresolved(
          message: "地点不存在：${request.placeId}",
        );
      }
      return PlaceResolutionResult.resolved(
        placeId: CampusPlaceId(campusId: campusId, placeId: place.placeId),
        place: place,
      );
    }
    // 未知校区：在全部启用校区内查找 placeId。
    for (final campus in registry.enabledCampuses) {
      final data = placesByCampus[campus.campusId];
      if (data == null) continue;
      final place = data.placeById(request.placeId!);
      if (place != null) {
        return PlaceResolutionResult.resolved(
          placeId: CampusPlaceId(
            campusId: campus.campusId,
            placeId: place.placeId,
          ),
          place: place,
        );
      }
    }
    return PlaceResolutionResult.unresolved(
      message: "地点不存在：${request.placeId}",
    );
  }
}
