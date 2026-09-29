import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../capabilities/alert_center.dart';
import '../../capabilities/alert_models.dart';
import '../../capabilities/east8_time.dart';
import '../../capabilities/persistent_summary_cache.dart';
import '../../capabilities/text_utils.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/auth_service.dart';
import '../../services/campus_session.dart';
import '../../services/service_endpoints.dart';
import 'academic_affairs_html_parser.dart';
import 'academic_affairs_models.dart';
import 'academic_affairs_utils.dart';

typedef AcademicAffairsDocumentLoader =
    Future<Document> Function(Uri uri, {required String method, String? body});

class AcademicAffairsService {
  static const _gradesChangedProviderId = 'academic.grades.changed';
  static const _examsSoonProviderId = 'academic.exams.soon';

  /// 成绩更新提醒提供者（订阅制）：指纹变化时经 [AlertCenterService] 评估。
  static final AlertProvider gradeAlertProvider = AlertProvider(
    id: _gradesChangedProviderId,
    source: '教务',
    title: '成绩有更新',
    kind: AlertKind.event,
    severity: AlertSeverity.info,
    evaluate: (params, data) {
      final report = data;
      if (report is! AcademicGradeReport) return const [];
      if (report.majorGrades.isEmpty && report.minorGrades.isEmpty) {
        return const [];
      }
      return [
        AlertDraft(
          fingerprintKey: gradeFingerprint(report).toString(),
          title: '成绩有更新',
          body: '成绩单有新变化，打开教务系统查看详情',
          deeplinkAppId: 'feature.academic.grades',
        ),
      ];
    },
  );

  /// 考试临近提醒提供者（订阅制）：进入提醒窗口的考试才提醒。
  static final AlertProvider examsSoonAlertProvider = AlertProvider(
    id: _examsSoonProviderId,
    source: '教务',
    title: '考试临近',
    kind: AlertKind.deadline,
    severity: AlertSeverity.warning,
    params: const [
      AlertParamSpec(
        key: 'leadTimeHours',
        label: '提前提醒',
        type: AlertParamType.hours,
        defaultValue: 72,
        min: 1,
        max: 336,
        unit: '小时',
      ),
    ],
    evaluate: (params, data) {
      final exams =
          data is List
              ? data.whereType<AcademicExam>().toList()
              : const <AcademicExam>[];
      if (exams.isEmpty) return const [];
      final hours = (params['leadTimeHours'] as num?)?.toDouble() ?? 72;
      final lead = Duration(hours: hours.round());
      final now = east8Now();
      final windowEnd = now.add(lead);
      final drafts = <AlertDraft>[];
      for (final exam in exams) {
        final start = academicExamStart(exam, requireExplicitTime: true);
        if (start == null) continue;
        if (start.isBefore(now) || start.isAfter(windowEnd)) continue;
        drafts.add(
          AlertDraft(
            fingerprintKey: 'exam:${exam.courseSequence}:${exam.examDate}',
            title: '考试临近',
            body:
                '${exam.courseName.ifEmpty(exam.courseSequence)}'
                ' · ${start.month}月${start.day}日'
                '${exam.location.isNotEmpty ? ' · ${exam.location}' : ''}',
            deeplinkAppId: 'feature.academic.exams',
          ),
        );
      }
      return drafts;
    },
  );

  static final _client = CampusSession.client(CampusServices.academicAffairs);
  static final _graduateClient = CampusSession.client(
    CampusServices.graduateAcademicAffairs,
  );
  static const _gradeResourceKey = 'grades';
  static final _gradeCache = PersistentSummaryCache<AcademicGradeReport>(
    storageKey: 'academic.grades.v1',
    ttl: const Duration(minutes: 15),
    persistTtl: const Duration(days: 7),
    maxEntries: 4,
    fromJson: AcademicGradeReport.fromJson,
    toJson: (report) => report.toJson(),
    fingerprint: gradeFingerprint,
    onChanged: (accountKey, previous, fresh) {
      unawaited(
        AlertCenterService.evaluate(
          accountKey,
          _gradesChangedProviderId,
          fresh,
        ),
      );
    },
  );

  /// Test hook for [fetchGrades] to run with a fake account key instead of
  /// touching secure storage.
  @visibleForTesting
  static Future<String?> Function()? debugAccountKeyProvider;

  static const _desktopHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/150.0.0.0 Safari/537.36',
  };
  static final _historyGradeUri =
      CampusServiceEndpoints.academicHistoryGradeUri;
  static final _examUri = CampusServiceEndpoints.academicExamUri;
  static final _examDetailUri = CampusServiceEndpoints.academicExamDetailUri;
  static final _syllabusUri = CampusServiceEndpoints.academicSyllabusUri;
  static final _syllabusSearchUri =
      CampusServiceEndpoints.academicSyllabusSearchUri;
  static final _syllabusDataQueryUri =
      CampusServiceEndpoints.academicSyllabusDataQueryUri;
  static final _graduateGradesUri = CampusServiceEndpoints.graduateGradesUri;
  static final _graduateSyllabusUri =
      CampusServiceEndpoints.graduateSyllabusUri;
  static final _graduateScheduleUri =
      CampusServiceEndpoints.graduateScheduleUri;
  static final _graduateExamUri = CampusServiceEndpoints.graduateExamUri;

  final AcademicAffairsDocumentLoader? _documentLoader;
  final AcademicAffairsBackend? _backendOverride;

  AcademicAffairsService({
    AcademicAffairsDocumentLoader? documentLoader,
    AcademicAffairsBackend? backendOverride,
  }) : _documentLoader = documentLoader,
       _backendOverride = backendOverride;

  /// Bumped whenever the grade cache refreshes so pages can update.
  static ValueNotifier<int> get gradeCacheRevision => _gradeCache.revision;

  Future<AcademicAffairsBackend> _resolveBackend() async {
    // Existing parser tests use an injected document loader without account
    // storage. Preserve that seam as the undergraduate adapter.
    final override = _backendOverride;
    if (override != null) return override;
    if (_documentLoader != null) return AcademicAffairsBackend.undergraduate;
    return AcademicAffairsBackendResolver.resolveCurrent();
  }

  Future<AcademicGradeReport> fetchGrades({bool force = false}) async {
    final backend = await _resolveBackend();
    final accountKey = await _tryCurrentAccountKey();
    if (accountKey == null) {
      return _fetchGradesFromNetwork(backend);
    }
    return _gradeCache.load(
      accountKey,
      backend == AcademicAffairsBackend.undergraduate
          ? _gradeResourceKey
          : '$_gradeResourceKey.graduate',
      () => _fetchGradesFromNetwork(backend),
      force: force,
    );
  }

  Future<AcademicGradeReport> _fetchGradesFromNetwork(
    AcademicAffairsBackend backend,
  ) async {
    if (backend == AcademicAffairsBackend.graduate) {
      return AcademicAffairsHtmlParser.parseGraduateGrades(
        await _requestGraduateDocument(_graduateGradesUri),
      );
    }
    return AcademicAffairsHtmlParser.parseGrades(
      await _loadDocument(_historyGradeUri),
    );
  }

  /// 成绩指纹：规范化（排序）后的课程最终成绩与绩点，忽略易变字段。
  static Object? gradeFingerprint(AcademicGradeReport report) {
    final grades = [...report.majorGrades, ...report.minorGrades]
      ..sort((left, right) {
        final byTerm = left.term.compareTo(right.term);
        if (byTerm != 0) return byTerm;
        final byCode = left.courseCode.compareTo(right.courseCode);
        if (byCode != 0) return byCode;
        return left.courseSequence.compareTo(right.courseSequence);
      });
    return [
      for (final grade in grades)
        [
          grade.term,
          grade.courseCode,
          grade.courseSequence,
          grade.finalScore,
          grade.gradePoint,
          grade.makeupScore,
          grade.retakeStatus,
        ],
    ];
  }

  Future<List<AcademicSemesterOption>> fetchSyllabusSemesters() async {
    final backend = await _resolveBackend();
    if (backend == AcademicAffairsBackend.graduate) {
      return AcademicAffairsHtmlParser.graduateSemesterOptions(
        await _requestGraduateDocument(_graduateSyllabusUri),
      );
    }
    final overview = await _loadDocument(
      _withCacheBuster(_syllabusUri),
      extraHeaders: _desktopHeaders,
    );
    final tagId = AcademicAffairsHtmlParser.syllabusSemesterTagId(overview);
    if (tagId == null || tagId.isEmpty) {
      throw const AcademicAffairsException('未找到排课查询学期参数');
    }
    final calendar = await _loadDocument(
      _syllabusDataQueryUri,
      method: 'POST',
      body: _formBody({
        'tagId': tagId,
        'dataType': 'semesterCalendar',
        'value': AcademicAffairsHtmlParser.syllabusDefaultSemester(overview),
        'empty': 'false',
      }),
    );
    final options = AcademicAffairsHtmlParser.parseSemesterCalendar(calendar);
    if (options.isEmpty) {
      throw const AcademicAffairsException('未找到排课查询学期数据');
    }
    return options;
  }

  Future<SyllabusPageData> searchSyllabus(
    String semesterId,
    SyllabusSearchFilters filters,
    int pageNo,
  ) async {
    final backend = await _resolveBackend();
    if (backend == AcademicAffairsBackend.graduate) {
      final term = AcademicAffairsHtmlParser.parseGraduateSemesterId(
        semesterId,
      );
      final document = await _requestGraduateDocument(
        _graduateSyllabusUri,
        method: 'POST',
        body: _formBody({
          'kkxn': term.year,
          'kckkxj': term.term,
          'kcbh': filters.lessonNo,
          'kcmc': filters.courseName,
          'kcxz': filters.courseTypeName,
          'jsxm': filters.teacherName,
          'jsgh': '',
          'kkyx': '',
          'skyy': '',
          'tskc': '',
          'key': '',
          'operateType': 'search',
          'pageId': '$pageNo',
        }),
      );
      return AcademicAffairsHtmlParser.parseGraduateSyllabus(
        document,
        pageNo: pageNo,
      );
    }
    final document = await _loadDocument(
      _syllabusSearchUri,
      method: 'POST',
      body: _formBody({
        'lesson.no': filters.lessonNo,
        'lesson.course.code': filters.courseCode,
        'lesson.course.name': filters.courseName,
        'lesson.courseType.name': filters.courseTypeName,
        'lesson.teachClass.name': filters.teachClassName,
        'teacher.name': filters.teacherName,
        'lesson.teachClass.stdCount': '',
        'lesson.teachClass.limitCount': '',
        'lesson.course.credits': '',
        'lesson.coursePeriod': '',
        'lesson.project.id': '1',
        'lesson.semester.id': semesterId,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
        'pageNo': '$pageNo',
      }),
      extraHeaders: _desktopHeaders,
    );
    return AcademicAffairsHtmlParser.parseSyllabus(document);
  }

  /// Loads the graduate student's personal timetable from the `/py` weekly
  /// grid. The graduate page renders one selected week per response, so the
  /// adapter requests the bounded list of weeks exposed by the page and
  /// merges the typed entries before returning to the UI layer.
  Future<AcademicScheduleFetchResult> fetchGraduateSchedule([
    String? semesterId,
  ]) async {
    final backend = await _resolveBackend();
    if (backend != AcademicAffairsBackend.graduate) {
      throw const AcademicAffairsException('当前身份不支持研究生课表接口');
    }

    final requested = semesterId?.trim() ?? '';
    final selection =
        requested.isEmpty
            ? null
            : AcademicAffairsHtmlParser.parseGraduateStudentSemesterId(
              requested,
            );
    final firstUri =
        selection == null
            ? _graduateScheduleUri
            : _graduateScheduleUri.replace(
              queryParameters: {
                'xn': selection.year,
                'xj': selection.term,
                'zc': '1',
              },
            );
    final first = await _requestGraduateDocument(firstUri);
    final selected =
        selection ?? AcademicAffairsHtmlParser.graduateScheduleSelection(first);
    if (selected.year.isEmpty || selected.term.isEmpty) {
      throw const AcademicAffairsException('未找到研究生课表学期参数');
    }

    final semesters = AcademicAffairsHtmlParser.graduateScheduleSemesterOptions(
      first,
      selectedId: 'yjs:${selected.year}:${selected.term}',
    );
    final weekOptions = AcademicAffairsHtmlParser.graduateWeekOptions(first);
    final weeks = weekOptions.isEmpty ? const [1] : weekOptions;
    final firstWeekValue = AcademicAffairsHtmlParser.graduateSelectedWeek(
      first,
    );
    final firstWeek =
        weeks.contains(firstWeekValue) ? firstWeekValue! : weeks.first;
    final documents = <int, Document>{firstWeek: first};
    final remaining = weeks
        .where((week) => week != firstWeek)
        .toList(growable: false);
    for (var offset = 0; offset < remaining.length; offset += 4) {
      final batch = remaining.skip(offset).take(4).toList(growable: false);
      final loaded = await Future.wait(
        batch.map((week) {
          final query = <String, String>{
            'xn': selected.year,
            'xj': selected.term,
            'zc': '$week',
          };
          return _requestGraduateDocument(
            _graduateScheduleUri.replace(queryParameters: query),
          ).then((document) => (week: week, document: document));
        }),
      );
      for (final item in loaded) {
        documents[item.week] = item.document;
      }
    }

    final option = semesters.firstWhere(
      (item) => item.id == 'yjs:${selected.year}:${selected.term}',
      orElse:
          () => AcademicSemesterOption(
            id: 'yjs:${selected.year}:${selected.term}',
            label: '${selected.year}学年${selected.term}学期',
            selected: true,
          ),
    );
    final schedule = AcademicAffairsHtmlParser.parseGraduateSchedule(
      documents,
      semesterId: option.id,
      semesterLabel: option.label,
      maxWeek:
          weekOptions.isEmpty
              ? 0
              : weeks.reduce((left, right) => left > right ? left : right),
    );
    return AcademicScheduleFetchResult(
      schedule: schedule,
      semesters: semesters,
    );
  }

  Future<List<AcademicSemesterOption>> fetchExamSemesters() async {
    final backend = await _resolveBackend();
    if (backend == AcademicAffairsBackend.graduate) {
      return AcademicAffairsHtmlParser.graduateStudentSemesterOptions(
        await _requestGraduateDocument(_graduateExamUri),
      );
    }
    final overview = await _loadDocument(_withCacheBuster(_examUri));
    return AcademicAffairsHtmlParser.semesterOptions(overview);
  }

  /// 拉取指定学期**全部考试批次**（浏览器请求 `examBatch.id=0`），供考试页
  /// 的批次筛选使用。
  Future<List<AcademicExam>> fetchAllExams([
    String? semesterId,
    bool evaluateAlerts = true,
  ]) => fetchExamsByBatch(semesterId, '0', evaluateAlerts);

  /// 按指定考试批次（`examBatch.id`）拉取考试安排；`batchId` 为空时等同于
  /// 全部批次（`0`）。
  Future<List<AcademicExam>> fetchExamsByBatch(
    String? semesterId,
    String? batchId, [
    bool evaluateAlerts = true,
  ]) async {
    final backend = await _resolveBackend();
    if (backend == AcademicAffairsBackend.graduate) {
      final exams = await _fetchGraduateExams(semesterId);
      if (evaluateAlerts) _evaluateExamsSoon(exams);
      return exams;
    }
    final exams = await _fetchExams(
      semesterId: semesterId,
      batchId: batchId ?? '0',
    );
    if (evaluateAlerts) _evaluateExamsSoon(exams);
    return exams;
  }

  static Future<void> evaluateExamAlerts(
    String accountKey,
    List<AcademicExam> exams,
  ) async {
    await Future.wait<void>([
      AlertCenterService.evaluate(accountKey, _examsSoonProviderId, exams),
      AlertCenterService.rebuildScheduled(accountKey, _examsSoonProviderId, (
        params,
      ) {
        final hours = (params['leadTimeHours'] as num?)?.round() ?? 72;
        final lead = Duration(hours: hours.clamp(1, 336));
        final drafts = <ScheduledAlertDraft>[];
        for (final exam in exams) {
          final start = academicExamStart(exam, requireExplicitTime: true);
          if (start == null) continue;
          drafts.add(
            ScheduledAlertDraft(
              eventId: 'exam:${exam.courseSequence}:${exam.examDate}',
              triggerAt: east8WallClockToUtcInstant(start.subtract(lead)),
              title: '考试临近：${exam.courseName.ifEmpty(exam.courseSequence)}',
              body: [
                exam.arrangement,
                if (exam.location.isNotEmpty) exam.location,
              ].join(' · '),
              deeplinkAppId: 'feature.academic.exams',
              validUntil: east8WallClockToUtcInstant(start),
            ),
          );
        }
        return drafts;
      }),
    ]);
  }

  void _evaluateExamsSoon(List<AcademicExam> exams) {
    unawaited(() async {
      final accountKey = await _tryCurrentAccountKey();
      if (accountKey == null) return;
      await evaluateExamAlerts(accountKey, exams);
    }());
  }

  /// 考试批次选项（期末教务处/期中/期末学院等），供考试页批次筛选。
  Future<List<AcademicExamBatchOption>> fetchExamBatches() async {
    final backend = await _resolveBackend();
    if (backend == AcademicAffairsBackend.graduate) return const [];
    final overview = await _loadDocument(_withCacheBuster(_examUri));
    return AcademicAffairsHtmlParser.examBatchOptions(overview);
  }

  Future<List<AcademicExam>> _fetchGraduateExams(String? semesterId) async {
    final requested = semesterId?.trim() ?? '';
    Uri uri = _graduateExamUri;
    if (requested.isNotEmpty) {
      final selection =
          AcademicAffairsHtmlParser.parseGraduateStudentSemesterId(requested);
      uri = uri.replace(
        queryParameters: {'xn': selection.year, 'xj': selection.term},
      );
    }
    return AcademicAffairsHtmlParser.parseGraduateExams(
      await _requestGraduateDocument(uri),
    );
  }

  Future<List<AcademicExam>> _fetchExams({
    String? semesterId,
    required String batchId,
  }) async {
    // 查询页动作偶发整体 500（服务端异常）时，跳过查询页直接尝试明细接口，
    // 避免整个考试分区因为查询页失败而无法加载。
    Document overview;
    try {
      overview = await _loadDocument(_withCacheBuster(_examUri));
    } catch (overviewError) {
      final exams = await _tryExamsFromDetail(
        semesterId: semesterId,
        batchId: batchId,
      );
      if (exams != null) return exams;
      rethrow;
    }
    final fields = AcademicAffairsHtmlParser.formValues(overview);
    final targetSemester =
        semesterId == null || semesterId.isEmpty
            ? (fields['semester.id'] ?? '')
            : semesterId;

    final queryParameters = <String, String>{};
    if (targetSemester.isNotEmpty) {
      queryParameters['semester.id'] = targetSemester;
    }
    // 显式批次视图（含全部批次 examBatch.id=0）：不携带 examType.id，
    // 避免被服务端按单一考试类别过滤。
    queryParameters['examBatch.id'] = batchId;
    queryParameters['_'] = DateTime.now().millisecondsSinceEpoch.toString();
    Object? detailError;
    try {
      final detail = await _loadDocument(
        _examDetailUri.replace(queryParameters: queryParameters),
      );
      if (AcademicAffairsHtmlParser.hasExams(detail)) {
        return AcademicAffairsHtmlParser.parseExams(detail);
      }
    } catch (error) {
      // 明细接口不可用时，回退解析查询页自带的表格，避免整个考试分区报错。
      detailError = error;
    }
    if (AcademicAffairsHtmlParser.hasExams(overview)) {
      return AcademicAffairsHtmlParser.parseExams(overview);
    }
    if (detailError != null) throw detailError;
    return const <AcademicExam>[];
  }

  /// 直接从明细接口取考试安排；无数据时返回 null（错误同样返回 null，
  /// 由调用方决定回退或保留更完整的原始错误）。
  Future<List<AcademicExam>?> _tryExamsFromDetail({
    String? semesterId,
    required String batchId,
  }) async {
    final queryParameters = <String, String>{
      'examBatch.id': batchId,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    if (semesterId != null && semesterId.isNotEmpty) {
      queryParameters['semester.id'] = semesterId;
    }
    try {
      final detail = await _loadDocument(
        _examDetailUri.replace(queryParameters: queryParameters),
      );
      if (!AcademicAffairsHtmlParser.hasExams(detail)) return null;
      return AcademicAffairsHtmlParser.parseExams(detail);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _tryCurrentAccountKey() async {
    final override = debugAccountKeyProvider;
    if (override != null) return override();
    try {
      return (await AuthService.getCurrentAccount())?.accountKey;
    } catch (_) {
      return null;
    }
  }

  Uri _withCacheBuster(Uri uri) => uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    },
  );

  // EAMS expects empty HTML form controls as `name=`, not a bare `name`.
  String _formBody(Map<String, String> fields) => fields.entries
      .map((entry) {
        final encoded = Uri(queryParameters: {entry.key: entry.value}).query;
        return entry.value.isEmpty && !encoded.endsWith('=')
            ? '$encoded='
            : encoded;
      })
      .join('&');

  Future<Document> _loadDocument(
    Uri uri, {
    String method = 'GET',
    String? body,
    Map<String, String>? extraHeaders,
  }) =>
      _documentLoader?.call(uri, method: method, body: body) ??
      _requestDocument(
        uri,
        method: method,
        body: body,
        extraHeaders: extraHeaders,
      );

  Future<Document> _requestDocument(
    Uri uri, {
    String method = 'GET',
    String? body,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final response = await _client.request(
        method,
        uri.toString(),
        body: body,
        contentType:
            body == null
                ? null
                : ContentType(
                  'application',
                  'x-www-form-urlencoded',
                  charset: 'utf-8',
                ),
        followRedirects: false,
        throwOnHttpError: false,
        extraHeaders: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.6778.200 Mobile Safari/537.36',
          'Referer': CampusServiceEndpoints.academicAffairsHomeUri.toString(),
          'X-Requested-With': 'XMLHttpRequest',
          ...?extraHeaders,
        },
      );
      final responseBody = response.body;
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          (response.statusCode >= 300 && response.statusCode < 400) ||
          _looksLikeAuthenticationPage(responseBody)) {
        throw const AcademicAffairsAuthenticationException();
      }
      if (response.statusCode != 200) {
        throw AcademicAffairsException('教务服务返回 HTTP ${response.statusCode}');
      }
      return html_parser.parse(responseBody);
    } on FormatException {
      throw const AcademicAffairsException('教务服务返回了无法识别的数据');
    } on TimeoutException {
      throw const AcademicAffairsException('教务响应超时，请稍后重试');
    }
  }

  Future<Document> _requestGraduateDocument(
    Uri uri, {
    String method = 'GET',
    String? body,
  }) async {
    final loader = _documentLoader;
    if (loader != null) {
      return loader(uri, method: method, body: body);
    }
    try {
      final response = await _graduateClient.request(
        method,
        uri.toString(),
        body: body,
        contentType:
            body == null
                ? null
                : ContentType('application', 'x-www-form-urlencoded'),
        followRedirects: false,
        throwOnHttpError: false,
        extraHeaders: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer':
              CampusServiceEndpoints.graduateAcademicAffairsHomeUri.toString(),
        },
      );
      final responseBody = response.body;
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          (response.statusCode >= 300 && response.statusCode < 400) ||
          _looksLikeAuthenticationPage(responseBody)) {
        throw const AcademicAffairsAuthenticationException();
      }
      if (response.statusCode != 200) {
        throw AcademicAffairsException('教务服务返回 HTTP ${response.statusCode}');
      }
      return html_parser.parse(responseBody);
    } on FormatException {
      throw const AcademicAffairsException('教务服务返回了无法识别的数据');
    } on TimeoutException {
      throw const AcademicAffairsException('教务响应超时，请稍后重试');
    }
  }

  bool _looksLikeAuthenticationPage(String body) {
    final lower = body.toLowerCase();
    return lower.contains('authserver/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('cas login');
  }
}
