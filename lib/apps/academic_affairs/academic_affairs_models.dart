import 'dart:convert';

enum CourseGradeScope { major, minor }

typedef AcademicGradeLoader = Future<AcademicGradeReport> Function();
typedef AcademicExamLoader =
    Future<List<AcademicExam>> Function(String? semesterId);
typedef AcademicExamSemesterLoader =
    Future<List<AcademicSemesterOption>> Function();
typedef AcademicExamBatchLoader =
    Future<List<AcademicExamBatchOption>> Function();

/// A semester option from an EAMS query page (`semester.id` select).
class AcademicSemesterOption {
  final String id;
  final String label;
  final bool selected;

  const AcademicSemesterOption({
    required this.id,
    required this.label,
    this.selected = false,
  });
}

/// 考试批次选项（`examBatch.id`），来自考试查询页下拉（如 期末考试(教务处)/
/// 期中考试/期末考试(学院)）。
class AcademicExamBatchOption {
  final String id;
  final String label;
  final bool selected;

  const AcademicExamBatchOption({
    required this.id,
    required this.label,
    this.selected = false,
  });
}

class AcademicEnrollmentSummary {
  final String courseCount;
  final String totalCredits;
  final String averageGpa;

  const AcademicEnrollmentSummary({
    required this.courseCount,
    required this.totalCredits,
    required this.averageGpa,
  });

  Map<String, dynamic> toJson() => {
    'courseCount': courseCount,
    'totalCredits': totalCredits,
    'averageGpa': averageGpa,
  };

  factory AcademicEnrollmentSummary.fromJson(Map<String, dynamic> json) {
    return AcademicEnrollmentSummary(
      courseCount: _stringField(json, 'courseCount'),
      totalCredits: _stringField(json, 'totalCredits'),
      averageGpa: _stringField(json, 'averageGpa'),
    );
  }
}

class AcademicTermSummary {
  final String academicYear;
  final String semester;
  final String courseCount;
  final String totalCredits;
  final String averageGpa;

  const AcademicTermSummary({
    required this.academicYear,
    required this.semester,
    required this.courseCount,
    required this.totalCredits,
    required this.averageGpa,
  });

  String get label => '$academicYear 学年$semester 学期';

  Map<String, dynamic> toJson() => {
    'academicYear': academicYear,
    'semester': semester,
    'courseCount': courseCount,
    'totalCredits': totalCredits,
    'averageGpa': averageGpa,
  };

  factory AcademicTermSummary.fromJson(Map<String, dynamic> json) {
    return AcademicTermSummary(
      academicYear: _stringField(json, 'academicYear'),
      semester: _stringField(json, 'semester'),
      courseCount: _stringField(json, 'courseCount'),
      totalCredits: _stringField(json, 'totalCredits'),
      averageGpa: _stringField(json, 'averageGpa'),
    );
  }
}

class AcademicCourseGrade {
  final CourseGradeScope scope;
  final String term;
  final String courseCode;
  final String courseSequence;
  final String courseName;
  final String category;
  final String credit;
  final String midtermScore;
  final String finalExamScore;
  final String usualScore;
  final String totalScore;
  final String labScore;
  final String finalScore;
  final String gradePoint;
  final String makeupScore;
  final String retakeStatus;
  final String teacher;
  final String scoreSystem;
  final String note;

  const AcademicCourseGrade({
    required this.scope,
    required this.term,
    required this.courseCode,
    required this.courseSequence,
    required this.courseName,
    required this.category,
    required this.credit,
    required this.midtermScore,
    required this.finalExamScore,
    required this.usualScore,
    required this.totalScore,
    required this.labScore,
    required this.finalScore,
    required this.gradePoint,
    this.makeupScore = '',
    this.retakeStatus = '',
    this.teacher = '',
    this.scoreSystem = '',
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'scope': scope.name,
    'term': term,
    'courseCode': courseCode,
    'courseSequence': courseSequence,
    'courseName': courseName,
    'category': category,
    'credit': credit,
    'midtermScore': midtermScore,
    'finalExamScore': finalExamScore,
    'usualScore': usualScore,
    'totalScore': totalScore,
    'labScore': labScore,
    'finalScore': finalScore,
    'gradePoint': gradePoint,
    if (makeupScore.isNotEmpty) 'makeupScore': makeupScore,
    if (retakeStatus.isNotEmpty) 'retakeStatus': retakeStatus,
    if (teacher.isNotEmpty) 'teacher': teacher,
    if (scoreSystem.isNotEmpty) 'scoreSystem': scoreSystem,
    if (note.isNotEmpty) 'note': note,
  };

  factory AcademicCourseGrade.fromJson(Map<String, dynamic> json) {
    final scopeName = _stringField(json, 'scope');
    return AcademicCourseGrade(
      scope: CourseGradeScope.values.firstWhere(
        (scope) => scope.name == scopeName,
        orElse: () => CourseGradeScope.major,
      ),
      term: _stringField(json, 'term'),
      courseCode: _stringField(json, 'courseCode'),
      courseSequence: _stringField(json, 'courseSequence'),
      courseName: _stringField(json, 'courseName'),
      category: _stringField(json, 'category'),
      credit: _stringField(json, 'credit'),
      midtermScore: _stringField(json, 'midtermScore'),
      finalExamScore: _stringField(json, 'finalExamScore'),
      usualScore: _stringField(json, 'usualScore'),
      totalScore: _stringField(json, 'totalScore'),
      labScore: _stringField(json, 'labScore'),
      finalScore: _stringField(json, 'finalScore'),
      gradePoint: _stringField(json, 'gradePoint'),
      makeupScore: _stringField(json, 'makeupScore'),
      retakeStatus: _stringField(json, 'retakeStatus'),
      teacher: _stringField(json, 'teacher'),
      scoreSystem: _stringField(json, 'scoreSystem'),
      note: _stringField(json, 'note'),
    );
  }
}

/// Calculates the ranking GPA described by the undergraduate grade report.
///
/// The academic system already supplies each course's grade point. This
/// calculator only applies the credit weighting and excludes the three
/// elective categories that do not count toward the ranking GPA.
class AcademicWeightedGpaCalculator {
  static const excludedCourseCategories = <String>{
    '科学探索与技术创新',
    '社会科学与公共责任',
    '经典阅读与写作沟通',
  };

  /// Returns whether a course belongs to one of the categories excluded from
  /// the ranking GPA. The academic system may append a catalog year or other
  /// suffix to the category, so the stable category name is matched as a
  /// prefix instead of requiring an exact string match.
  static bool isExcludedCategory(String category) {
    final normalized = category.trim();
    return excludedCourseCategories.any(normalized.startsWith);
  }

  static String? calculate(Iterable<AcademicCourseGrade> grades) {
    var weightedPoints = 0.0;
    var totalCredits = 0.0;

    for (final grade in grades) {
      if (isExcludedCategory(grade.category)) continue;

      final credit = double.tryParse(grade.credit.trim());
      final gradePoint = double.tryParse(grade.gradePoint.trim());
      if (credit == null || gradePoint == null || credit <= 0) return null;

      weightedPoints += gradePoint * credit;
      totalCredits += credit;
    }

    if (totalCredits <= 0) return null;
    // Keep decimal half-way cases (for example 2.675) on conventional
    // two-decimal rounding instead of exposing binary floating-point noise.
    final roundedHundredths =
        (weightedPoints / totalCredits * 100 + 1e-9).round();
    return (roundedHundredths / 100).toStringAsFixed(2);
  }
}

class AcademicGradeReport {
  final AcademicEnrollmentSummary? enrollmentSummary;
  final List<AcademicTermSummary> termSummaries;
  final List<AcademicCourseGrade> majorGrades;
  final List<AcademicCourseGrade> minorGrades;
  final String statisticsAt;

  const AcademicGradeReport({
    required this.enrollmentSummary,
    required this.termSummaries,
    required this.majorGrades,
    required this.minorGrades,
    required this.statisticsAt,
  });

  String? weightedGpaForTerm(String term) {
    return AcademicWeightedGpaCalculator.calculate(
      majorGrades.where((grade) => grade.term == term),
    );
  }

  Map<String, dynamic> toJson() => {
    'enrollmentSummary': enrollmentSummary?.toJson(),
    'termSummaries': [for (final term in termSummaries) term.toJson()],
    'majorGrades': [for (final grade in majorGrades) grade.toJson()],
    'minorGrades': [for (final grade in minorGrades) grade.toJson()],
    'statisticsAt': statisticsAt,
  };

  factory AcademicGradeReport.fromJson(Map<String, dynamic> json) {
    AcademicEnrollmentSummary? enrollmentSummary;
    final enrollmentRaw = json['enrollmentSummary'];
    if (enrollmentRaw is Map<String, dynamic>) {
      enrollmentSummary = AcademicEnrollmentSummary.fromJson(enrollmentRaw);
    }
    return AcademicGradeReport(
      enrollmentSummary: enrollmentSummary,
      termSummaries: _listField(
        json,
        'termSummaries',
      ).map(AcademicTermSummary.fromJson).toList(growable: false),
      majorGrades: _listField(
        json,
        'majorGrades',
      ).map(AcademicCourseGrade.fromJson).toList(growable: false),
      minorGrades: _listField(
        json,
        'minorGrades',
      ).map(AcademicCourseGrade.fromJson).toList(growable: false),
      statisticsAt: _stringField(json, 'statisticsAt'),
    );
  }
}

/// A normalized lesson block from the student's personal timetable.
/// The model keeps the fields needed by a native weekly timetable: course
/// identity, teacher, location, and the weeks in which the lesson is active.
class AcademicPersonalScheduleEntry {
  /// Stable identity of the source activity/arrangement slot, when the
  /// importer can provide one.  This is deliberately separate from the
  /// displayable course sequence: one lesson can have several slots.
  final String sourceId;
  final String courseSequence;
  final String courseCode;
  final String courseName;
  final String teacher;
  final String location;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final String weeksText;
  final List<int> weeks;
  final List<int> practiceWeeks;

  const AcademicPersonalScheduleEntry({
    this.sourceId = '',
    required this.courseSequence,
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.location,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeksText,
    required this.weeks,
    required this.practiceWeeks,
  });

  AcademicPersonalScheduleEntry copyWith({
    String? sourceId,
    String? courseSequence,
    String? courseCode,
    String? courseName,
    String? teacher,
    String? location,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    String? weeksText,
    List<int>? weeks,
    List<int>? practiceWeeks,
  }) {
    return AcademicPersonalScheduleEntry(
      sourceId: sourceId ?? this.sourceId,
      courseSequence: courseSequence ?? this.courseSequence,
      courseCode: courseCode ?? this.courseCode,
      courseName: courseName ?? this.courseName,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      weekday: weekday ?? this.weekday,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      weeksText: weeksText ?? this.weeksText,
      weeks: weeks ?? this.weeks,
      practiceWeeks: practiceWeeks ?? this.practiceWeeks,
    );
  }

  String get displayName => courseName.isNotEmpty ? courseName : courseSequence;

  bool isVisibleInWeek(int week) {
    if (weeks.isEmpty && practiceWeeks.isEmpty) return true;
    return weeks.contains(week) || practiceWeeks.contains(week);
  }

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'courseSequence': courseSequence,
    'courseCode': courseCode,
    'courseName': courseName,
    'teacher': teacher,
    'location': location,
    'weekday': weekday,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'weeksText': weeksText,
    'weeks': weeks,
    'practiceWeeks': practiceWeeks,
  };

  factory AcademicPersonalScheduleEntry.fromJson(Map<String, dynamic> json) {
    final rawCourseSequence = _stringField(json, 'courseSequence');
    final identity = normalizeScheduleCourseIdentity(
      courseName: _stringField(json, 'courseName'),
      courseCode: _stringField(json, 'courseCode'),
      courseSequence: rawCourseSequence,
    );
    return AcademicPersonalScheduleEntry(
      sourceId: _stringField(json, 'sourceId'),
      courseSequence: rawCourseSequence,
      courseCode: identity.code,
      courseName: identity.name,
      teacher: _stringField(json, 'teacher'),
      location: _stringField(json, 'location'),
      weekday: _intField(json, 'weekday'),
      startPeriod: _intField(json, 'startPeriod'),
      endPeriod: _intField(json, 'endPeriod'),
      weeksText: _stringField(json, 'weeksText'),
      weeks: _intListField(json, 'weeks'),
      practiceWeeks: _intListField(json, 'practiceWeeks'),
    );
  }
}

/// The canonical user-facing course identity used by timetable importers and
/// cache migration.  The source activity id is deliberately not folded into
/// either field: it is only an opaque identity for [sourceId].
class AcademicScheduleCourseIdentity {
  final String name;
  final String code;

  const AcademicScheduleCourseIdentity({
    required this.name,
    required this.code,
  });
}

/// Normalizes a timetable course name without touching ordinary parentheses.
///
/// Only a *trailing* parenthesized suffix that exactly matches a known course
/// sequence/code is removed.  This keeps names such as “高等数学（微积分）”
/// intact while migrating legacy snapshots such as
/// “学术英语(13TH1014.11)”.
AcademicScheduleCourseIdentity normalizeScheduleCourseIdentity({
  required String courseName,
  String courseCode = '',
  String courseSequence = '',
}) {
  final rawName = courseName.trim();
  final rawCode = courseCode.trim();
  final sequence = courseSequence.trim();
  final knownCodes = <String>{
    if (rawCode.isNotEmpty) rawCode,
    if (sequence.isNotEmpty) sequence,
  };
  for (final value in [rawCode, sequence]) {
    final match = RegExp(r'^[^（）()]+[（(]([^（）()]+)[）)]$').firstMatch(value);
    final inner = match?.group(1)?.trim() ?? '';
    if (inner.isNotEmpty) knownCodes.add(inner);
  }

  String? suffix;
  int? suffixStart;
  final trailing = RegExp(
    r'\s*[（(]\s*([^（）()]+?)\s*[）)]\s*$',
  ).firstMatch(rawName);
  if (trailing != null) {
    final candidate = trailing.group(1)?.trim() ?? '';
    if (candidate.isNotEmpty && knownCodes.contains(candidate)) {
      suffix = candidate;
      suffixStart = trailing.start;
    }
  }

  final normalizedName =
      suffixStart == null ? rawName : rawName.substring(0, suffixStart).trim();
  var normalizedCode = rawCode;
  // A legacy cache could have stored an opaque EAMS id in courseCode while
  // courseSequence retained the visible Shuwei lesson number. Prefer that
  // visible sequence when the suffix proves the two belong together.
  if (suffix != null && sequence == suffix) {
    normalizedCode = sequence;
  } else if (normalizedCode.isEmpty && suffix != null) {
    normalizedCode = suffix;
  } else if (normalizedCode.isEmpty &&
      sequence.isNotEmpty &&
      sequence != rawName) {
    normalizedCode = sequence;
  }
  return AcademicScheduleCourseIdentity(
    name: normalizedName,
    code: normalizedCode,
  );
}

/// Convenience used by importers that already know the visible code.
String normalizeScheduleCourseName(
  String value, {
  String courseCode = '',
  String courseSequence = '',
}) =>
    normalizeScheduleCourseIdentity(
      courseName: value,
      courseCode: courseCode,
      courseSequence: courseSequence,
    ).name;

/// Stable identity for one raw timetable slot.
///
/// Importers provide [AcademicPersonalScheduleEntry.sourceId] from the raw
/// activity/arrangement identity and assign a stable segment identity when a
/// source activity is split into multiple slots.  Hand-created records use
/// their full normalized structure as a deterministic fallback.
String academicScheduleEntryKey(AcademicPersonalScheduleEntry entry) {
  final sourceId = entry.sourceId.trim();
  final sequence = entry.courseSequence.trim();
  final code = entry.courseCode.trim();
  final identity =
      sourceId.isNotEmpty
          ? <Object?>['source', sourceId]
          : <Object?>[
            'fallback',
            sequence,
            code,
            entry.courseName.trim(),
            entry.teacher.trim(),
            entry.location.trim(),
            entry.weekday,
            entry.startPeriod,
            entry.endPeriod,
            [...entry.weeks]..sort(),
            [...entry.practiceWeeks]..sort(),
          ];
  return base64UrlEncode(utf8.encode(jsonEncode(identity)));
}

/// Key format used by the first user-layer implementation.  It is retained
/// only so a previously saved, unambiguous override can be read after the
/// source identity model is upgraded.  Colliding legacy keys are ignored by
/// the store instead of being applied to several entries.
String academicScheduleLegacyEntryKey(AcademicPersonalScheduleEntry entry) {
  final sequence = entry.courseSequence.trim();
  final code = entry.courseCode.trim();
  final identity =
      sequence.isNotEmpty
          ? <Object?>['sequence', sequence]
          : code.isNotEmpty
          ? <Object?>['code', code]
          : <Object?>[
            'fallback',
            entry.courseName.trim(),
            entry.weekday,
            entry.startPeriod,
            entry.endPeriod,
            [...entry.weeks]..sort(),
            [...entry.practiceWeeks]..sort(),
          ];
  return base64UrlEncode(utf8.encode(jsonEncode(identity)));
}

/// A complete normalized timetable snapshot for one semester.
class AcademicPersonalSchedule {
  final String semesterId;
  final String semesterLabel;
  final List<AcademicPersonalScheduleEntry> entries;
  final int maxWeek;
  final DateTime fetchedAt;

  const AcademicPersonalSchedule({
    required this.semesterId,
    required this.semesterLabel,
    required this.entries,
    required this.maxWeek,
    required this.fetchedAt,
  });

  AcademicPersonalSchedule copyWith({
    String? semesterId,
    String? semesterLabel,
    List<AcademicPersonalScheduleEntry>? entries,
    int? maxWeek,
    DateTime? fetchedAt,
  }) {
    return AcademicPersonalSchedule(
      semesterId: semesterId ?? this.semesterId,
      semesterLabel: semesterLabel ?? this.semesterLabel,
      entries: entries ?? this.entries,
      maxWeek: maxWeek ?? this.maxWeek,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'semesterId': semesterId,
    'semesterLabel': semesterLabel,
    'entries': [for (final entry in entries) entry.toJson()],
    'maxWeek': maxWeek,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory AcademicPersonalSchedule.fromJson(Map<String, dynamic> json) {
    return AcademicPersonalSchedule(
      semesterId: _stringField(json, 'semesterId'),
      semesterLabel: _stringField(json, 'semesterLabel'),
      entries: _listField(
        json,
        'entries',
      ).map(AcademicPersonalScheduleEntry.fromJson).toList(growable: false),
      maxWeek: _intField(json, 'maxWeek', fallback: 26),
      fetchedAt:
          DateTime.tryParse(_stringField(json, 'fetchedAt')) ?? DateTime.now(),
    );
  }
}

/// A schedule snapshot returned by a feature-specific academic adapter.
///
/// The page and home module share the same result shape for undergraduate
/// WebView imports and the graduate HTML adapter without exposing credentials
/// or raw response documents to UI code.
class AcademicScheduleFetchResult {
  final AcademicPersonalSchedule schedule;
  final List<AcademicSemesterOption> semesters;

  const AcademicScheduleFetchResult({
    required this.schedule,
    required this.semesters,
  });
}

/// The schedule population rendered by the academic schedule app.
///
/// The administrative class view is available only for undergraduate EAMS
/// accounts and is intentionally kept separate from the personal schedule
/// cache and reminder pipeline.
enum AcademicScheduleScope { personal, administrativeClass }

class AcademicExam {
  final String courseSequence;
  final String courseName;
  final String examType;
  final String examDate;
  final String arrangement;
  final String location;
  final String seat;
  final String status;
  final String note;

  const AcademicExam({
    required this.courseSequence,
    required this.courseName,
    required this.examType,
    required this.examDate,
    required this.arrangement,
    required this.location,
    required this.seat,
    required this.status,
    required this.note,
  });

  bool get isScheduled =>
      examDate.isNotEmpty &&
      !examDate.contains('未安排') &&
      arrangement.isNotEmpty &&
      !arrangement.contains('未安排');
}

/// 排课查询筛选条件。空字符串表示不筛选；服务端筛选字段仍全部提交。
class SyllabusSearchFilters {
  final String lessonNo;
  final String courseCode;
  final String courseName;
  final String courseTypeName;
  final String teachClassName;
  final String teacherName;

  const SyllabusSearchFilters({
    this.lessonNo = '',
    this.courseCode = '',
    this.courseName = '',
    this.courseTypeName = '',
    this.teachClassName = '',
    this.teacherName = '',
  });

  SyllabusSearchFilters copyWith({
    String? lessonNo,
    String? courseCode,
    String? courseName,
    String? courseTypeName,
    String? teachClassName,
    String? teacherName,
  }) {
    return SyllabusSearchFilters(
      lessonNo: lessonNo ?? this.lessonNo,
      courseCode: courseCode ?? this.courseCode,
      courseName: courseName ?? this.courseName,
      courseTypeName: courseTypeName ?? this.courseTypeName,
      teachClassName: teachClassName ?? this.teachClassName,
      teacherName: teacherName ?? this.teacherName,
    );
  }
}

typedef SyllabusSemesterLoader =
    Future<List<AcademicSemesterOption>> Function();
typedef SyllabusSearchLoader =
    Future<SyllabusPageData> Function(
      String semesterId,
      SyllabusSearchFilters filters,
      int pageNo,
    );

/// 单条全校开课记录。
class SyllabusCourseRow {
  final String lessonId;
  final String courseSequence;
  final String courseCode;
  final String courseName;
  final String category;
  final String teachClass;
  final String teachers;
  final String actualCount;
  final String limitCount;
  final String credits;
  final String periodPerWeek;
  final String weekState;
  final String language;
  final String campus;
  final List<SyllabusScheduleEntry> scheduleEntries;

  const SyllabusCourseRow({
    required this.lessonId,
    required this.courseSequence,
    required this.courseCode,
    required this.courseName,
    required this.category,
    required this.teachClass,
    required this.teachers,
    required this.actualCount,
    required this.limitCount,
    required this.credits,
    required this.periodPerWeek,
    required this.weekState,
    this.language = '',
    this.campus = '',
    this.scheduleEntries = const [],
  });
}

/// 一门课的一条排课安排，字段来自响应中的 `contents[lessonId]` 文本。
class SyllabusScheduleEntry {
  final String teachers;
  final String weekdayLabel;
  final String periodText;
  final String weeksText;
  final String location;
  final String rawText;

  const SyllabusScheduleEntry({
    required this.teachers,
    required this.weekdayLabel,
    required this.periodText,
    required this.weeksText,
    required this.location,
    required this.rawText,
  });
}

/// 排课查询一页结果。
class SyllabusPageData {
  final int pageNo;
  final int pageSize;
  final int total;
  final bool hasMore;
  final List<SyllabusCourseRow> rows;

  const SyllabusPageData({
    required this.pageNo,
    required this.pageSize,
    required this.total,
    required this.hasMore,
    required this.rows,
  });
}

class AcademicAffairsAuthenticationException implements Exception {
  final String message;

  const AcademicAffairsAuthenticationException([
    this.message = '教务系统登录状态已失效，请重新登录后重试。',
  ]);

  @override
  String toString() => message;
}

class AcademicAffairsException implements Exception {
  final String message;

  const AcademicAffairsException(this.message);

  @override
  String toString() => message;
}

String _stringField(Map<String, dynamic> json, String key) =>
    json[key] is String ? json[key] as String : '';

int _intField(Map<String, dynamic> json, String key, {int fallback = 0}) {
  final value = json[key];
  return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}

List<int> _intListField(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! List) return const [];
  return raw
      .map((value) => value is num ? value.toInt() : int.tryParse('$value'))
      .whereType<int>()
      .toList(growable: false);
}

List<Map<String, dynamic>> _listField(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().toList(growable: false);
}
