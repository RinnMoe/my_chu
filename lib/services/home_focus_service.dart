import '../apps/academic_affairs/academic_affairs_models.dart';
import '../apps/academic_affairs/academic_affairs_service.dart';
import '../apps/academic_affairs/academic_affairs_utils.dart';
import '../apps/academic_calendar/academic_calendar_models.dart';
import '../apps/academic_calendar/academic_calendar_service.dart';
import '../apps/portal_notices/mobile_campus_notice_service.dart';
import '../apps/portal_notices/portal_notices_models.dart';
import '../apps/tronclass/tronclass_models.dart';
import '../apps/tronclass/tronclass_service.dart';
import '../capabilities/academic_schedule/academic_schedule_store.dart';
import '../capabilities/academic_schedule/recent_schedule_loader.dart';
import '../capabilities/account_scoped_cache.dart';
import '../capabilities/east8_time.dart';
import '../capabilities/public_holidays/public_holidays.dart';
import '../capabilities/text_utils.dart';
import 'demo_data_service.dart';
import 'fenfa/fenfa_models.dart';
import 'fenfa/fenfa_service.dart';
import 'logger_service.dart';
import 'auth_service.dart';

typedef _CurrentTeachingWeekLoader =
    Future<CurrentTeachingWeek?> Function(String accountKey);
typedef _ScheduleLoader =
    Future<AcademicPersonalSchedule?> Function(String accountKey);
typedef _SourceAlertEvaluator =
    Future<void> Function(
      String accountKey,
      List<AcademicExam> exams,
      List<TronclassTodo> todos,
    );

/// 首页 Focus 类型。类型只用于图标、优先级和点击行为，不用于分栏展示。
enum HomeFocusKind {
  todo,
  campusNotice,
  appAnnouncement,
  exam,
  dataChange,
  serviceAlert,
  importantReminder,
  publicHoliday,
}

enum HomeFocusPriority { p0, p1, p2, p3 }

/// Focus 点击目标，由聚合层负责把内部来源收敛成首页可消费的动作。
sealed class HomeFocusDestination {
  const HomeFocusDestination();
}

class HomeFocusAppDestination extends HomeFocusDestination {
  final String? appId;

  const HomeFocusAppDestination({this.appId});
}

/// 学校公告的 Focus 点击目标：打开校园公告列表，不直达单条详情。
class HomeFocusNoticeDestination extends HomeFocusDestination {
  const HomeFocusNoticeDestination();
}

/// 当前 MyCHU 公告的正文，只能从对应的 Focus 行打开。
class HomeFocusAnnouncementDestination extends HomeFocusDestination {
  final String content;

  const HomeFocusAnnouncementDestination(this.content);
}

class HomeFocusItem {
  final String id;
  final HomeFocusKind kind;
  final String title;
  final String subtitle;
  final String? tertiaryText;
  final HomeFocusPriority priority;
  final DateTime? eventTime;
  final DateTime createdAt;
  final String source;
  final HomeFocusDestination destination;

  const HomeFocusItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.priority,
    required this.createdAt,
    required this.source,
    required this.destination,
    this.tertiaryText,
    this.eventTime,
  });
}

class HomeFocusSnapshot {
  final List<HomeFocusItem> items;
  final DateTime fetchedAt;
  final bool hasError;
  final DateTime? nextRefreshAt;

  const HomeFocusSnapshot({
    required this.items,
    required this.fetchedAt,
    this.hasError = false,
    this.nextRefreshAt,
  }) : assert(items.length <= 3);

  bool get isEmpty => items.isEmpty;
}

/// 聚合考试、待办、课程与公告，输出首页 Focus。
///
/// 聚合层负责 eligibility、优先级、基础去重与 Top 3；首页不再感知各来源
/// 的内部模型。
class HomeFocusService {
  HomeFocusService({
    Future<List<AcademicExam>> Function()? examsLoader,
    Future<List<TronclassTodo>> Function()? todosLoader,
    Future<CurrentTeachingWeek?> Function(String accountKey)? currentWeekLoader,
    Future<AcademicPersonalSchedule?> Function(String accountKey)?
    scheduleLoader,
    Future<void> Function(
      String accountKey,
      List<AcademicExam> exams,
      List<TronclassTodo> todos,
    )?
    alertEvaluator,
    Future<List<PortalNotice>> Function()? noticesLoader,
    Future<List<FenfaAnnouncement>> Function(bool force)? announcementsLoader,
    PublicHolidayProvider? publicHolidayProvider,
    DateTime Function()? clock,
  }) : _examsLoader =
           examsLoader ??
           (() => AcademicAffairsService().fetchAllExams(null, false)),
       _todosLoader =
           todosLoader ??
           (() => TronclassService().fetchTodos(evaluateAlerts: false)),
       _currentWeekLoader = currentWeekLoader ?? _defaultCurrentWeekLoader,
       _scheduleLoader = scheduleLoader ?? _defaultScheduleLoader,
       _alertEvaluator = alertEvaluator ?? _evaluateSourceAlerts,
       _noticesLoader =
           noticesLoader ?? (() => MobileCampusNoticeService().fetchNotices()),
       _announcementsLoader =
           announcementsLoader ??
           ((force) =>
               FenfaService.shared.loadFocusAnnouncements(force: force)),
       _publicHolidayProvider = publicHolidayProvider,
       _clock = clock ?? east8Now;

  static final AccountScopedCache<_FocusSourceSnapshot> _sourceCache =
      AccountScopedCache<_FocusSourceSnapshot>(
        ttl: const Duration(seconds: 60),
        allowStale: false,
      );

  final Future<List<AcademicExam>> Function() _examsLoader;
  final Future<List<TronclassTodo>> Function() _todosLoader;
  final _CurrentTeachingWeekLoader _currentWeekLoader;
  final _ScheduleLoader _scheduleLoader;
  final _SourceAlertEvaluator _alertEvaluator;
  final Future<List<PortalNotice>> Function() _noticesLoader;
  final Future<List<FenfaAnnouncement>> Function(bool force)
  _announcementsLoader;
  final PublicHolidayProvider? _publicHolidayProvider;
  final DateTime Function() _clock;

  Future<HomeFocusSnapshot> load(
    String accountKey, {
    bool force = false,
    bool evaluateAlerts = true,
  }) async {
    final demo = DemoDataService.instance;
    if (demo.enabled) {
      return _demoSnapshot();
    }
    final earlyClassTiming = await _resolveEarlyClassTiming(accountKey);
    final now = earlyClassTiming.evaluatedAt;
    final results = await Future.wait<Object?>([
      _capture(
        () => _loadSourceCandidates(
          accountKey,
          force: force,
          evaluateAlerts: evaluateAlerts,
          now: now,
          earlyClassTiming: earlyClassTiming,
        ),
        code: 'home.focus.today.failed',
        message: '首页今日焦点加载失败',
      ),
      _capture(
        _noticesLoader,
        code: 'home.focus.notices.failed',
        message: '首页公告焦点加载失败',
      ),
      _capture(
        () => _loadPublicHolidayItems(now, force: force),
        code: 'home.focus.public_holidays.failed',
        message: '首页公共节假日焦点加载失败',
      ),
      _capture(
        () => _announcementsLoader(force),
        code: 'home.focus.app_announcements.failed',
        message: '首页应用公告焦点加载失败',
      ),
    ]);
    final focus = results[0] as _FocusLoadResult<_FocusSourceSnapshot>;
    final notices = results[1] as _FocusLoadResult<List<PortalNotice>>;
    final publicHolidays = results[2] as _FocusLoadResult<List<HomeFocusItem>>;
    final announcements =
        results[3] as _FocusLoadResult<List<FenfaAnnouncement>>;
    final items = <HomeFocusItem>[
      if (focus.value != null) ...focus.value!.candidates,
      if (notices.value != null) ..._fromNotices(notices.value!, now),
      if (publicHolidays.value != null) ...publicHolidays.value!,
      if (announcements.value != null)
        ..._fromAppAnnouncements(announcements.value!, now),
    ];
    final unique = _deduplicate(items);
    final capped = _applyTypeCaps(unique);
    capped.sort(_compare);
    return HomeFocusSnapshot(
      items: capped.take(3).toList(growable: false),
      fetchedAt: now,
      hasError:
          focus.error != null ||
          notices.error != null ||
          announcements.error != null ||
          focus.value?.hasError == true,
      nextRefreshAt: earlyClassTiming.nextRefreshAt,
    );
  }

  Future<_FocusSourceSnapshot> _loadSourceCandidates(
    String accountKey, {
    required bool force,
    required bool evaluateAlerts,
    required DateTime now,
    required _EarlyClassFocusTiming earlyClassTiming,
  }) async {
    final previous = _sourceCache.peek(accountKey);
    try {
      return await _sourceCache.load(
        accountKey,
        () => _collectSourceCandidates(
          accountKey,
          evaluateAlerts: evaluateAlerts,
          now: now,
          earlyClassTiming: earlyClassTiming,
        ),
        force: force,
      );
    } catch (error) {
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.focus.today.aggregate_failed',
        message: '首页今日焦点聚合失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'aggregate'},
      );
      final now = _clock();
      if (previous == null) {
        return _FocusSourceSnapshot(
          candidates: const [],
          fetchedAt: now,
          hasError: true,
        );
      }
      final marked = _FocusSourceSnapshot(
        candidates: previous.candidates,
        fetchedAt: previous.fetchedAt,
        hasError: true,
      );
      _sourceCache.seed(accountKey, marked, fetchedAt: previous.fetchedAt);
      return marked;
    }
  }

  Future<_FocusSourceSnapshot> _collectSourceCandidates(
    String accountKey, {
    required bool evaluateAlerts,
    required DateTime now,
    required _EarlyClassFocusTiming earlyClassTiming,
  }) async {
    final session = AuthService.sessionRevision;
    final results = await Future.wait<Object?>([
      _examsLoader(),
      _todosLoader(),
      _loadNextDayFirstClass(accountKey, now, earlyClassTiming),
    ]);
    final exams = results[0] as List<AcademicExam>;
    final todos = results[1] as List<TronclassTodo>;
    final earlyClass = results[2] as HomeFocusItem?;
    if (evaluateAlerts && session == AuthService.sessionRevision) {
      await _alertEvaluator(accountKey, exams, todos);
    }
    return _FocusSourceSnapshot(
      candidates: _buildSourceCandidates(
        exams,
        todos,
        now,
        earlyClass: earlyClass,
      ),
      fetchedAt: now,
    );
  }

  static Future<void> _evaluateSourceAlerts(
    String accountKey,
    List<AcademicExam> exams,
    List<TronclassTodo> todos,
  ) async {
    await Future.wait<void>([
      AcademicAffairsService.scheduleExamReminders(accountKey, exams),
      TronclassService.scheduleTodoReminders(accountKey, todos),
    ]);
  }

  Future<_EarlyClassFocusTiming> _resolveEarlyClassTiming(
    String accountKey,
  ) async {
    try {
      final now = _clock();
      const reminderHour = 21;
      var nextRefreshAt = DateTime(now.year, now.month, now.day, reminderHour);
      if (!nextRefreshAt.isAfter(now)) {
        nextRefreshAt = DateTime(
          now.year,
          now.month,
          now.day + 1,
          reminderHour,
        );
      }
      return _EarlyClassFocusTiming(
        evaluatedAt: now,
        visibleNow: now.hour >= reminderHour,
        nextRefreshAt: nextRefreshAt,
      );
    } catch (error) {
      _recordEarlyClassFailure(error);
      return _EarlyClassFocusTiming(evaluatedAt: _clock());
    }
  }

  Future<HomeFocusItem?> _loadNextDayFirstClass(
    String accountKey,
    DateTime now,
    _EarlyClassFocusTiming timing,
  ) async {
    if (!timing.visibleNow) return null;
    try {
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final day =
          (await loadRecentScheduleDays(
            accountKey,
            [tomorrow],
            readSchedule: _scheduleLoader,
            readTeachingWeek: _currentWeekLoader,
            onAcademicFailure: _recordEarlyClassFailure,
          )).single;
      final first = day.courses.firstOrNull;
      if (first == null || !first.isFirstPeriod) return null;
      final startsAt = first.start;
      return HomeFocusItem(
        id: 'early-class:${_dateKey(tomorrow)}:${first.earlyClassKey}',
        kind: HomeFocusKind.serviceAlert,
        title: '明日早八',
        subtitle: '第${first.startPeriod}-${first.endPeriod}节 ${first.name}',
        tertiaryText: [
          '${_two(startsAt.hour)}:${_two(startsAt.minute)}',
          if (first.location.trim().isNotEmpty) first.location.trim(),
        ].join(' · '),
        priority: HomeFocusPriority.p1,
        eventTime: startsAt,
        createdAt: now,
        source: day.sourceLabel,
        destination: const HomeFocusAppDestination(
          appId: 'feature.academic.schedule',
        ),
      );
    } catch (error) {
      _recordEarlyClassFailure(error);
      return null;
    }
  }

  static void _recordEarlyClassFailure(Object error) {
    AppLogger.recordSafeFailure(
      level: 'WARN',
      code: 'home.focus.early_class.failed',
      message: '首页次日课程焦点加载失败',
      error: error,
      domain: 'home',
      fields: const {'source': 'academic.schedule'},
    );
  }

  static Future<CurrentTeachingWeek?> _defaultCurrentWeekLoader(
    String _,
  ) async {
    try {
      return (await AcademicCalendarService().fetchCurrentCalendarState())
          .teachingWeek;
    } catch (_) {
      return null;
    }
  }

  static Future<AcademicPersonalSchedule?> _defaultScheduleLoader(
    String accountKey,
  ) async {
    return AcademicScheduleStore().readCachedCurrentSchedule(accountKey);
  }

  List<HomeFocusItem> _buildSourceCandidates(
    List<AcademicExam> exams,
    List<TronclassTodo> todos,
    DateTime now, {
    HomeFocusItem? earlyClass,
  }) {
    final examWindowEnd = now.add(const Duration(days: 7));
    final todoWindowEnd = now.add(const Duration(hours: 72));
    final overdueWindowStart = now.subtract(const Duration(hours: 24));
    final items = <HomeFocusItem>[if (earlyClass != null) earlyClass];

    for (final exam in exams) {
      final start = academicExamStart(exam);
      if (start == null ||
          start.isBefore(now) ||
          start.isAfter(examWindowEnd)) {
        continue;
      }
      final examKey = 'exam:${exam.courseSequence}:${exam.examDate}';
      items.add(
        HomeFocusItem(
          id: examKey,
          kind: HomeFocusKind.exam,
          title: exam.courseName.ifEmpty(exam.courseSequence),
          subtitle: [
            _actionDeadline(start, now),
            if (exam.location.isNotEmpty) exam.location,
          ].join(' · '),
          priority: HomeFocusPriority.p1,
          eventTime: start,
          createdAt: start,
          source: '教务',
          destination: const HomeFocusAppDestination(
            appId: 'feature.academic.exams',
          ),
        ),
      );
    }

    for (final todo in todos) {
      final endTime = todo.endTime;
      if (endTime == null ||
          endTime.isBefore(overdueWindowStart) ||
          endTime.isAfter(todoWindowEnd) ||
          todo.submitRate >= 100) {
        continue;
      }
      items.add(
        HomeFocusItem(
          id: 'todo:${todo.id}',
          kind: HomeFocusKind.todo,
          title: todo.title,
          subtitle: [
            _actionDeadline(endTime, now),
            if (todo.courseName.isNotEmpty) _homeActivityLabel(todo.courseName),
          ].join(' · '),
          priority: _todoPriority(endTime, now),
          eventTime: endTime,
          createdAt: endTime,
          source: '畅课',
          destination: const HomeFocusAppDestination(
            appId: 'feature.portal.personal',
          ),
        ),
      );
    }

    return items;
  }

  static HomeFocusPriority _todoPriority(DateTime endTime, DateTime now) {
    final within24h = endTime.isBefore(now.add(const Duration(hours: 24)));
    if (!endTime.isAfter(now) || within24h) return HomeFocusPriority.p0;
    return HomeFocusPriority.p1;
  }

  static String _timeLabel(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _actionDeadline(DateTime time, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(time.year, time.month, time.day);
    final days = target.difference(today).inDays;
    final timeLabel = _timeLabel(time);
    if (days == 0) return '今天 $timeLabel';
    if (days == 1) return '明天 $timeLabel';
    return '${time.month}月${time.day}日 $timeLabel';
  }

  static String _homeActivityLabel(String raw) {
    var text = raw.trim();
    text = text.replaceFirst(
      RegExp(r'^\d{4}(暑期|寒假|春季学期|夏季学期|秋季学期|冬季学期|春|夏|秋|冬)?'),
      '',
    );
    text = text.replaceFirst(RegExp(r'^全国大学生'), '');
    return text.ifEmpty(raw.trim());
  }

  Future<List<HomeFocusItem>> _loadPublicHolidayItems(
    DateTime now, {
    bool force = false,
  }) async {
    final provider = _publicHolidayProvider;
    if (provider == null) return const [];
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final snapshot = await provider.loadRange(today, tomorrow, force: force);
    final todayHolidayNames =
        snapshot
            .daysFor(today)
            .where((day) => day.isOffDay)
            .map((day) => day.name.trim())
            .where((name) => name.isNotEmpty)
            .toSet();
    final days = snapshot.daysFor(tomorrow);
    final makeup = days.where((day) => !day.isOffDay).toList(growable: false);
    final holidays = days.where((day) => day.isOffDay).toList(growable: false);
    final holidayNames = _publicHolidayNames(holidays);
    final holidayStartsTomorrow = holidays.any(
      (holiday) => !todayHolidayNames.contains(holiday.name.trim()),
    );
    return [
      if (makeup.isNotEmpty)
        HomeFocusItem(
          id: _publicHolidayId(tomorrow, 'makeup'),
          kind: HomeFocusKind.publicHoliday,
          title: '明日调休上课',
          subtitle:
              '${_publicHolidayNames(makeup)}调休 · 星期${_weekdayLabel(tomorrow.weekday)}',
          priority: HomeFocusPriority.p1,
          eventTime: tomorrow,
          createdAt: now,
          source: '公共节假日',
          destination: const HomeFocusAppDestination(
            appId: 'feature.academic.calendar',
          ),
        ),
      if (holidays.isNotEmpty)
        HomeFocusItem(
          id: _publicHolidayId(tomorrow, 'holiday'),
          kind: HomeFocusKind.publicHoliday,
          title: '$holidayNames假期',
          subtitle: holidayStartsTomorrow ? '明天开始' : '假期中',
          priority: HomeFocusPriority.p1,
          eventTime: tomorrow,
          createdAt: now,
          source: '公共节假日',
          destination: const HomeFocusAppDestination(
            appId: 'feature.academic.calendar',
          ),
        ),
    ];
  }

  static String _publicHolidayId(DateTime date, String kind) =>
      'public-holiday:${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}:$kind';

  static String _publicHolidayNames(List<PublicHolidayDay> days) {
    final names = <String>[];
    final seen = <String>{};
    for (final day in days) {
      final name = day.name.trim();
      if (name.isEmpty || !seen.add(name)) continue;
      names.add(name);
    }
    return names.join('、');
  }

  static String _weekdayLabel(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  HomeFocusSnapshot _demoSnapshot() {
    final demo = DemoDataService.instance;
    final now = demo.now;
    const seeds = <(String, String, HomeFocusKind, HomeFocusPriority)>[
      (
        '考试：高等数学',
        '今天 14:00 · WM3101',
        HomeFocusKind.exam,
        HomeFocusPriority.p1,
      ),
      ('待办：提交课程作业', '剩余 3 小时', HomeFocusKind.todo, HomeFocusPriority.p0),
      (
        '校园卡余额不足',
        '当前余额 8.50 元',
        HomeFocusKind.serviceAlert,
        HomeFocusPriority.p1,
      ),
    ];
    final count = demo.config.focusCount.clamp(0, 3);
    return HomeFocusSnapshot(
      items: [
        for (var index = 0; index < count && index < seeds.length; index++)
          HomeFocusItem(
            id: 'demo-focus-$index',
            kind: seeds[index].$3,
            title: seeds[index].$1,
            subtitle: seeds[index].$2,
            priority: seeds[index].$4,
            createdAt: now,
            source: 'Demo',
            destination: const HomeFocusAppDestination(),
          ),
      ],
      fetchedAt: now,
      hasError: demo.config.focusError,
    );
  }

  Future<_FocusLoadResult<T>> _capture<T>(
    Future<T> Function() loader, {
    required String code,
    required String message,
  }) async {
    try {
      return _FocusLoadResult(value: await loader());
    } catch (error) {
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: code,
        message: message,
        error: error,
        domain: 'home',
      );
      return _FocusLoadResult(error: error);
    }
  }

  /// 普通学校公告统一为最低优先级（P3），只生成候选；最终“最多 1 条”的
  /// 配额由聚合层在 Top 3 之前执行。
  List<HomeFocusItem> _fromNotices(List<PortalNotice> notices, DateTime now) {
    final sorted = [...notices]
      ..sort((a, b) => _noticeTime(b, now).compareTo(_noticeTime(a, now)));
    return [
      for (final notice in sorted)
        HomeFocusItem(
          id: 'notice:${notice.id}',
          kind: HomeFocusKind.campusNotice,
          title: notice.title,
          subtitle: notice.department,
          tertiaryText: _formatNoticeTime(notice.publishedAt),
          priority: HomeFocusPriority.p3,
          createdAt: _noticeTime(notice, now),
          source: '校园通知',
          destination: const HomeFocusNoticeDestination(),
        ),
    ];
  }

  List<HomeFocusItem> _fromAppAnnouncements(
    List<FenfaAnnouncement> announcements,
    DateTime now,
  ) => [
    for (final announcement in announcements)
      HomeFocusItem(
        id: 'app-announcement:${announcement.id}',
        kind: HomeFocusKind.appAnnouncement,
        title: announcement.title,
        subtitle:
            announcement.content.trim().isEmpty
                ? 'MyCHU 应用公告'
                : announcement.content.trim().replaceAll(RegExp(r'\s+'), ' '),
        priority: HomeFocusPriority.p3,
        createdAt: now,
        source: 'MyCHU',
        destination: HomeFocusAnnouncementDestination(announcement.content),
      ),
  ];

  List<HomeFocusItem> _deduplicate(List<HomeFocusItem> items) {
    final result = <HomeFocusItem>[];
    final seenIds = <String>{};
    for (final item in items) {
      if (seenIds.contains(item.id)) continue;
      if (item.kind == HomeFocusKind.campusNotice &&
          result.any((existing) => existing.title == item.title)) {
        continue;
      }
      seenIds.add(item.id);
      result.add(item);
    }
    return result;
  }

  /// 普通学校公告和应用公告各最多 1 条，配额先于 Top 3 执行。
  static const _typeCaps = <HomeFocusKind, int>{
    HomeFocusKind.campusNotice: 1,
    HomeFocusKind.appAnnouncement: 1,
  };

  List<HomeFocusItem> _applyTypeCaps(List<HomeFocusItem> items) {
    final counts = <HomeFocusKind, int>{};
    final result = <HomeFocusItem>[];
    for (final item in items) {
      final count = counts[item.kind] ?? 0;
      final cap = _typeCaps[item.kind];
      if (cap != null && count >= cap) continue;
      counts[item.kind] = count + 1;
      result.add(item);
    }
    return result;
  }

  static int _compare(HomeFocusItem left, HomeFocusItem right) {
    final priorityCompare = left.priority.index.compareTo(right.priority.index);
    if (priorityCompare != 0) return priorityCompare;
    final leftTime = left.eventTime;
    final rightTime = right.eventTime;
    if (leftTime != null && rightTime != null) {
      final timeCompare = leftTime.compareTo(rightTime);
      if (timeCompare != 0) return timeCompare;
    } else if (leftTime == null && rightTime != null) {
      return 1;
    } else if (leftTime != null && rightTime == null) {
      return -1;
    }
    if (left.kind == HomeFocusKind.publicHoliday &&
        right.kind == HomeFocusKind.publicHoliday) {
      final leftOrder = left.title == '明日调休上课' ? 0 : 1;
      final rightOrder = right.title == '明日调休上课' ? 0 : 1;
      if (leftOrder != rightOrder) return leftOrder.compareTo(rightOrder);
    }
    return right.createdAt.compareTo(left.createdAt);
  }

  static DateTime _noticeTime(PortalNotice notice, DateTime fallback) {
    return parseEast8(notice.publishedAt) ?? fallback;
  }

  /// 展示时间统一为 `yyyy-MM-dd HH:mm`（不显示秒）；解析失败时保留原文，
  /// 由 UI 单行省略兜底。
  static String _formatNoticeTime(String raw) {
    final parsed = parseEast8(raw);
    if (parsed == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }
}

class _FocusSourceSnapshot {
  final List<HomeFocusItem> candidates;
  final DateTime fetchedAt;
  final bool hasError;

  const _FocusSourceSnapshot({
    required this.candidates,
    required this.fetchedAt,
    this.hasError = false,
  });
}

class _EarlyClassFocusTiming {
  final DateTime evaluatedAt;
  final bool visibleNow;
  final DateTime? nextRefreshAt;

  const _EarlyClassFocusTiming({
    required this.evaluatedAt,
    this.visibleNow = false,
    this.nextRefreshAt,
  });
}

class _FocusLoadResult<T> {
  final T? value;
  final Object? error;

  const _FocusLoadResult({this.value, this.error});
}
