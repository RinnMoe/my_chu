import 'dart:convert';
import 'dart:io';

import '../../capabilities/east8_time.dart';
import '../../capabilities/persistent_summary_cache.dart';
import '../../services/account_network_session_service.dart';
import '../../services/auth_service.dart';
import '../../services/campus_session.dart';
import '../../services/demo_data_service.dart';
import '../../services/mobile_campus_request_signer.dart';
import '../../services/service_endpoints.dart';
import 'academic_calendar_models.dart';

typedef AcademicCalendarRequestLoader =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, Object?> param);
typedef AcademicCalendarAccountKeyLoader = Future<String?> Function();
typedef AcademicCalendarCredentialRefresher = Future<bool> Function();

class AcademicCalendarException implements Exception {
  final String message;

  const AcademicCalendarException(this.message);

  @override
  String toString() => message;
}

class AcademicCalendarAuthenticationException
    extends AcademicCalendarException {
  const AcademicCalendarAuthenticationException()
    : super('移动校园登录状态已失效，请重新登录后重试。');
}

/// Mobile-campus school calendar adapter.
///
/// The adapter owns request signing, account-scoped caching and the one-shot
/// mobile-campus credential refresh. Pages only receive typed calendar data.
class AcademicCalendarService {
  static const _timeout = Duration(seconds: 12);
  static const _termsResourceKey = 'terms';
  static const _currentResourceKey = 'current';

  static final _client = CampusSession.client(CampusServices.mobileCampus);

  static final _termsCache = PersistentSummaryCache<List<AcademicCalendarTerm>>(
    storageKey: 'academic.calendar.terms.v1',
    ttl: const Duration(minutes: 30),
    persistTtl: const Duration(days: 30),
    maxEntries: 8,
    fromJson: (json) {
      final raw = json['terms'];
      if (raw is! List) throw const FormatException('校历学期缓存字段缺失');
      return raw
          .map((item) {
            if (item is! Map) throw const FormatException('校历学期缓存无效');
            return AcademicCalendarTerm.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .toList(growable: false);
    },
    toJson:
        (terms) => {
          'terms': [for (final term in terms) term.toJson()],
        },
  );

  static final _calendarCache = PersistentSummaryCache<AcademicCalendarData>(
    storageKey: 'academic.calendar.data.v1',
    ttl: const Duration(minutes: 5),
    persistTtl: const Duration(days: 30),
    maxEntries: 32,
    fromJson: AcademicCalendarData.fromJson,
    toJson: (calendar) => calendar.toJson(),
  );

  final AcademicCalendarRequestLoader? _requestLoader;
  final AcademicCalendarAccountKeyLoader _accountKeyLoader;
  final AcademicCalendarCredentialRefresher _credentialRefresher;
  final DateTime Function() _clock;
  final bool _useCache;

  AcademicCalendarService({
    AcademicCalendarRequestLoader? requestLoader,
    AcademicCalendarAccountKeyLoader? accountKeyLoader,
    AcademicCalendarCredentialRefresher? credentialRefresher,
    DateTime Function()? clock,
    bool useCache = true,
  }) : _requestLoader = requestLoader,
       _accountKeyLoader =
           accountKeyLoader ??
           (() async => (await AuthService.getCurrentAccount())?.accountKey),
       _credentialRefresher = credentialRefresher ?? _client.refresh,
       _clock = clock ?? east8Now,
       _useCache = useCache;

  Future<List<AcademicCalendarTerm>> fetchTerms({bool force = false}) async {
    final accountKey = await _accountKey();
    if (!_useCache) {
      return AcademicCalendarParser.parseTerms(
        await _post(
          CampusServiceEndpoints.mobileCampusCalendarTermsUri,
          const {},
        ),
      );
    }
    return _termsCache.load(
      accountKey,
      _termsResourceKey,
      () async => AcademicCalendarParser.parseTerms(
        await _post(
          CampusServiceEndpoints.mobileCampusCalendarTermsUri,
          const {},
        ),
      ),
      force: force,
    );
  }

  /// Fetches the server-selected current term.  The request deliberately has
  /// no `xn`, `xq` or `isChange` fields.
  /// Reads a matching calendar already held in the account-scoped cache.
  /// This method never starts a campus request.
  Future<AcademicCalendarData?> readCachedCalendarForSemester(
    String accountKey,
    String semesterLabel,
  ) async {
    final current =
        _calendarCache.peek(accountKey, _currentResourceKey) ??
        await _calendarCache.readFromDisk(accountKey, _currentResourceKey);
    if (current != null &&
        _calendarLabelMatches(current.term.label, semesterLabel)) {
      return current;
    }

    final terms =
        _termsCache.peek(accountKey, _termsResourceKey) ??
        await _termsCache.readFromDisk(accountKey, _termsResourceKey);
    if (terms == null) return null;
    AcademicCalendarTerm? selectedTerm;
    for (final term in terms) {
      if (_calendarLabelMatches(term.label, semesterLabel)) {
        selectedTerm = term;
        break;
      }
    }
    if (selectedTerm == null) return null;
    final resourceKey = _termResourceKey(selectedTerm);
    return _calendarCache.peek(accountKey, resourceKey) ??
        await _calendarCache.readFromDisk(accountKey, resourceKey);
  }

  /// Reads a semester start date from the local calendar or term directory.
  /// This method never starts a campus request.
  Future<DateTime?> readCachedTermStartDateForSemester(
    String accountKey,
    String semesterLabel,
  ) async {
    final calendar = await readCachedCalendarForSemester(
      accountKey,
      semesterLabel,
    );
    if (calendar?.term.startDate != null) return calendar!.term.startDate;

    final terms =
        _termsCache.peek(accountKey, _termsResourceKey) ??
        await _termsCache.readFromDisk(accountKey, _termsResourceKey);
    if (terms == null) return null;
    for (final term in terms) {
      if (_calendarLabelMatches(term.label, semesterLabel)) {
        return term.startDate;
      }
    }
    return null;
  }

  /// Resolves a semester start date from local data, loading the term directory
  /// when the schedule's semester is not represented in the current calendar
  /// cache. Callers run this from the foreground host, never from a widget
  /// rendering process.
  Future<DateTime?> ensureTermStartDateForSemester(String semesterLabel) async {
    final accountKey = await _accountKey();
    final cached = await readCachedTermStartDateForSemester(
      accountKey,
      semesterLabel,
    );
    if (cached != null) return cached;

    final terms = await fetchTerms();
    for (final term in terms) {
      if (_calendarLabelMatches(term.label, semesterLabel)) {
        return term.startDate;
      }
    }
    return null;
  }

  Future<AcademicCalendarData> fetchCurrentCalendar({
    bool force = false,
  }) async {
    final accountKey = await _accountKey();
    if (!_useCache) {
      return AcademicCalendarParser.parseCalendar(
        await _post(
          CampusServiceEndpoints.mobileCampusCalendarDataUri,
          const {},
        ),
      );
    }
    return _calendarCache.load(
      accountKey,
      _currentResourceKey,
      () async => AcademicCalendarParser.parseCalendar(
        await _post(
          CampusServiceEndpoints.mobileCampusCalendarDataUri,
          const {},
        ),
      ),
      force: force,
    );
  }

  /// Fetches a selected historical term with the mobile-campus change flag.
  Future<AcademicCalendarData> fetchCalendar(
    AcademicCalendarTerm term, {
    bool force = false,
  }) async {
    final accountKey = await _accountKey();
    if (!_useCache) {
      return _fetchHistoricalCalendar(term);
    }
    return _calendarCache.load(accountKey, _termResourceKey(term), () async {
      return _fetchHistoricalCalendar(term);
    }, force: force);
  }

  Future<AcademicCalendarData> _fetchHistoricalCalendar(
    AcademicCalendarTerm term,
  ) async {
    final calendar = AcademicCalendarParser.parseCalendar(
      await _post(CampusServiceEndpoints.mobileCampusCalendarDataUri, {
        'xn': term.academicYear,
        'xq': term.semester,
        'isChange': true,
      }),
    );
    // The historical endpoint sometimes omits descriptive fields even
    // though the term directory contains them.
    return calendar.copyWith(
      term: AcademicCalendarTerm(
        academicYear: calendar.term.academicYear,
        semester: calendar.term.semester,
        description: term.description,
        startDate: term.startDate ?? calendar.term.startDate,
        color: term.color,
      ),
    );
  }

  /// Resolves the current term and teaching-week state from the school
  /// calendar. A date outside all intervals is unknown, not a holiday.
  Future<AcademicCalendarState> fetchCurrentCalendarState({
    bool force = false,
  }) async {
    final demo = DemoDataService.instance;
    if (demo.enabled) {
      const term = '2026-2027学年第1学期';
      if (demo.config.holiday) {
        return AcademicCalendarState(
          teachingWeek: null,
          calendarWeek: 5,
          term: term,
          termStartDate: null,
          fetchedAt: demo.now,
          isHoliday: true,
        );
      }
      return AcademicCalendarState(
        teachingWeek: CurrentTeachingWeek(
          term: term,
          week: 5,
          termStartDate: DateTime(2026, 8, 10),
        ),
        calendarWeek: 5,
        term: term,
        termStartDate: DateTime(2026, 8, 10),
        fetchedAt: demo.now,
        isHoliday: false,
      );
    }

    final calendar = await fetchCurrentCalendar(force: force);
    final now = _clock();
    final current = calendar.weekFor(now);
    final termStartDate = calendar.term.startDate;
    final term = calendar.term.label;
    final teachingWeek =
        current?.isHoliday == false
            ? CurrentTeachingWeek(
              week: current!.week,
              term: term,
              termStartDate: termStartDate,
            )
            : null;
    return AcademicCalendarState(
      teachingWeek: teachingWeek,
      calendarWeek: current?.week,
      term: term,
      termStartDate: termStartDate,
      fetchedAt: now,
      isHoliday: current?.isHoliday == true,
    );
  }

  Future<String> _accountKey() async {
    final accountKey = await _accountKeyLoader();
    if (accountKey == null || accountKey.trim().isEmpty) {
      // Injected loaders are test seams and do not have access to the host
      // account store. Production requests always go through CampusSession
      // and therefore still require a real account.
      if (_requestLoader != null) return '__injected-calendar-account__';
      throw StateError('请先登录后再读取校历');
    }
    return accountKey.trim();
  }

  bool _calendarLabelMatches(String calendarLabel, String requestedLabel) {
    final requested = requestedLabel.trim();
    if (requested == '当前学期' || requested == '本学期') {
      return true;
    }
    if (requested.isEmpty) return false;
    return academicCalendarTermLabelsMatch(calendarLabel, requested);
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, Object?> business,
  ) async {
    final param = <String, Object?>{
      'campusType': 1,
      ...business,
      'wxCode': null,
      'client': null,
      'openId': null,
    };
    try {
      return await _postOnce(uri, param);
    } on AcademicCalendarAuthenticationException {
      final refreshed = await _credentialRefresher();
      if (!refreshed) rethrow;
      return _postOnce(uri, param);
    }
  }

  Future<Map<String, dynamic>> _postOnce(
    Uri uri,
    Map<String, Object?> param,
  ) async {
    final loader = _requestLoader;
    if (loader != null) {
      return AcademicCalendarParser.validateEnvelope(await loader(uri, param));
    }

    final response = await _client.request(
      'POST',
      uri.toString(),
      body: MobileCampusRequestSigner.signedBody(param),
      contentType: ContentType.json,
      requestTimeout: _timeout,
      responseTimeout: _timeout,
      throwOnHttpError: false,
      // Mobile-campus business failures are JSON-level token failures.  The
      // calendar adapter must own exactly one refresh/retry for that case.
      autoExchangeService: false,
      extraHeaders: const {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    return AcademicCalendarParser.decodeResponse(response);
  }

  static String _termResourceKey(AcademicCalendarTerm term) =>
      'term.${term.academicYear}.${term.semester}';
}

class AcademicCalendarParser {
  static Map<String, dynamic> decodeResponse(AccountNetworkResponse response) {
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden ||
        (response.statusCode >= HttpStatus.multipleChoices &&
            response.statusCode < HttpStatus.badRequest)) {
      throw const AcademicCalendarAuthenticationException();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw AcademicCalendarException('移动校园校历服务返回 HTTP ${response.statusCode}');
    }
    final raw =
        response.body.startsWith('\uFEFF')
            ? response.body.substring(1)
            : response.body;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      if (looksLikeAuthenticationPage(raw)) {
        throw const AcademicCalendarAuthenticationException();
      }
      throw const AcademicCalendarException('移动校园校历返回了无法识别的数据');
    }
    return validateEnvelope(Map<String, dynamic>.from(decoded));
  }

  static Map<String, dynamic> validateEnvelope(Object? raw) {
    if (raw is! Map) {
      throw const AcademicCalendarException('移动校园校历响应格式异常');
    }
    final map = Map<String, dynamic>.from(raw);
    if (_isAuthenticationFailure(map)) {
      throw const AcademicCalendarAuthenticationException();
    }
    return map;
  }

  static List<AcademicCalendarTerm> parseTerms(Object? raw) {
    final map = _successfulMap(raw);
    final rows = map['xnXqList'];
    if (rows is! List) {
      throw const AcademicCalendarException('校历学期列表格式异常');
    }
    final terms = <AcademicCalendarTerm>[];
    for (final item in rows) {
      if (item is! Map) {
        throw const AcademicCalendarException('校历学期条目格式异常');
      }
      try {
        terms.add(_parseTerm(Map<String, dynamic>.from(item)));
      } on FormatException {
        throw const AcademicCalendarException('校历学期字段无效');
      }
    }
    return List.unmodifiable(terms);
  }

  static AcademicCalendarData parseCalendar(Object? raw) {
    final map = _successfulMap(raw);
    final academicYear = _text(map['xn']);
    final semester = _int(map['xq']);
    if (academicYear.isEmpty || semester < 1) {
      throw const AcademicCalendarException('校历学年学期字段缺失');
    }

    final weekRows = map['schoolTimeList'];
    if (weekRows is! List) {
      throw const AcademicCalendarException('校历周数据格式异常');
    }
    final weeks = <AcademicCalendarWeek>[];
    for (final item in weekRows) {
      if (item is! Map) {
        throw const AcademicCalendarException('校历周条目格式异常');
      }
      weeks.add(_parseWeek(Map<String, dynamic>.from(item)));
    }
    weeks.sort((left, right) {
      final byStart = left.startDate.compareTo(right.startDate);
      return byStart == 0 ? left.week.compareTo(right.week) : byStart;
    });

    final events = <AcademicCalendarEvent>[
      ..._parseEvents(
        map['schoolTimeListCommon'],
        AcademicCalendarEventKind.commonHoliday,
      ),
      ..._parseEvents(
        map['schoolTimeListSpe'],
        AcademicCalendarEventKind.special,
      ),
    ]..sort((left, right) => left.date.compareTo(right.date));

    return AcademicCalendarData(
      term: AcademicCalendarTerm(
        academicYear: academicYear,
        semester: semester,
        startDate: _firstWeekStart(weeks),
      ),
      weeks: List.unmodifiable(weeks),
      events: List.unmodifiable(events),
    );
  }

  static AcademicCalendarTerm _parseTerm(Map<String, dynamic> row) {
    final academicYear = _text(row['xn']);
    final semester = _int(row['xq']);
    if (academicYear.isEmpty || semester < 1) {
      throw const FormatException('校历学期字段缺失');
    }
    return AcademicCalendarTerm(
      academicYear: academicYear,
      semester: semester,
      description: _text(row['describe'] ?? row['description']),
      startDate:
          row.containsKey('startTime')
              ? _requiredTimestamp(row['startTime'])
              : null,
      color: _nullableText(row['colorCode'] ?? row['color']),
    );
  }

  static AcademicCalendarWeek _parseWeek(Map<String, dynamic> row) {
    final week = _int(row['zc']);
    final type = _int(row['type']);
    final start = _requiredTimestamp(row['startTime']);
    final end = _requiredTimestamp(row['endTime']);
    if (week < 1 || (type != 1 && type != 2) || end.isBefore(start)) {
      throw const AcademicCalendarException('校历周字段无效');
    }
    return AcademicCalendarWeek(
      week: week,
      startDate: start,
      endDate: end,
      isHoliday: type == 2,
      event: _text(row['event']),
      eventColor: _nullableText(row['zCode'] ?? row['colorCode']),
    );
  }

  static Iterable<AcademicCalendarEvent> _parseEvents(
    Object? raw,
    AcademicCalendarEventKind kind,
  ) sync* {
    if (raw == null) return;
    if (raw is! List) {
      throw const AcademicCalendarException('校历事件格式异常');
    }
    for (final item in raw) {
      if (item is! Map) {
        throw const AcademicCalendarException('校历事件条目格式异常');
      }
      final row = Map<String, dynamic>.from(item);
      final title = _text(row['event'] ?? row['title']);
      if (title.isEmpty) {
        throw const AcademicCalendarException('校历事件字段缺失');
      }
      final sourceType = _int(row['type']);
      if (sourceType < 1) {
        throw const AcademicCalendarException('校历事件类型无效');
      }
      yield AcademicCalendarEvent(
        date: _requiredTimestamp(row['date']),
        title: title,
        color: _nullableText(row['colorCode'] ?? row['color']),
        kind: kind,
        sourceType: sourceType,
      );
    }
  }

  static Map<String, dynamic> _successfulMap(Object? raw) {
    final map = validateEnvelope(raw);
    if (_int(map['msgState']) != 1) {
      throw const AcademicCalendarException('移动校园校历服务请求失败');
    }
    return map;
  }

  static DateTime _requiredTimestamp(Object? value) {
    final date = _optionalTimestamp(value);
    if (date == null) {
      throw const AcademicCalendarException('校历日期字段无效');
    }
    return date;
  }

  static DateTime? _optionalTimestamp(Object? value) {
    if (value is bool || value == null) return null;
    final milliseconds = value is num ? value.toInt() : int.tryParse('$value');
    if (milliseconds == null || milliseconds <= 0) return null;
    try {
      final east8 = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).add(east8Offset);
      return DateTime(east8.year, east8.month, east8.day);
    } on ArgumentError {
      return null;
    }
  }

  static DateTime? _firstWeekStart(List<AcademicCalendarWeek> weeks) {
    for (final week in weeks) {
      if (week.week == 1) return week.startDate;
    }
    return null;
  }

  static bool looksLikeAuthenticationPage(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('authserver/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('cas login') ||
        lower.contains('protocol/openid-connect') ||
        (lower.contains('<html') && lower.contains('登录'));
  }

  static bool _isAuthenticationFailure(Map<String, dynamic> map) {
    final state = _int(map['msgState']);
    if (state == 401 || state == 403) return true;
    if (state == 1) return false;
    final message = [
      map['msg'],
      map['msgContent'],
      map['message'],
      map['error'],
      map['errorMsg'],
    ].map(_text).join(' ');
    final lower = message.toLowerCase();
    return lower.contains('login') ||
        lower.contains('session') ||
        lower.contains('token') ||
        message.contains('登录') ||
        message.contains('未登录') ||
        message.contains('凭证') ||
        message.contains('认证') ||
        message.contains('无权限') ||
        message.contains('无权');
  }

  static int _int(Object? value) {
    if (value is bool || value == null) return 0;
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  static String _text(Object? value) => '${value ?? ''}'.trim();

  static String? _nullableText(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }
}
