import 'dart:async';

import 'package:flutter/material.dart';

import '../east8_time.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/auth_service.dart';
import '../../services/campus_settings_service.dart';
import '../../services/demo_data_service.dart';
import '../../services/teaching_schedule_service.dart';
import '../../services/temporal_change_service.dart';
import '../../services/logger_service.dart';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_affairs/academic_affairs_service.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import '../../apps/academic_affairs/academic_affairs_widgets.dart';
import '../../apps/academic_web/shuwei_schedule_importer.dart';
import 'academic_schedule_navigation.dart';
import 'academic_schedule_store.dart';
import 'academic_schedule_utils.dart';
import '../public_holidays/public_holidays.dart';

typedef AcademicScheduleHomeAccountKeyLoader = Future<String?> Function();
typedef AcademicScheduleHomeCalendarStateLoader =
    Future<AcademicCalendarState> Function();
typedef AcademicScheduleHomeGraduateLoader =
    Future<AcademicScheduleFetchResult> Function(String? semesterId);
typedef AcademicScheduleHomeCourseTap =
    Future<void> Function(
      BuildContext context,
      AcademicPersonalScheduleEntry entry,
    );

const _courseRowHeight = 72.0;
const _courseListHeight = _courseRowHeight * 3;

/// `AcademicScheduleCapability` 直接创建的固定首页模块。
class AcademicScheduleHomeModule extends StatefulWidget {
  final AcademicScheduleStore? store;
  final ShuweiScheduleImporter? importer;
  final AcademicScheduleHomeGraduateLoader? graduateLoader;
  final AcademicScheduleHomeAccountKeyLoader? accountKeyLoader;
  final AcademicScheduleHomeCalendarStateLoader? calendarStateLoader;
  final bool useSharedCalendarState;
  final AcademicCalendarState? calendarState;
  final bool calendarStateLoading;
  final Future<void> Function()? onRetryCalendarState;
  final PublicHolidayProvider? publicHolidayProvider;
  final DateTime Function()? clock;
  final AcademicScheduleHomeCourseTap? onOpenCourse;

  const AcademicScheduleHomeModule({
    super.key,

    this.store,
    this.importer,
    this.graduateLoader,
    this.accountKeyLoader,
    this.calendarStateLoader,
    this.useSharedCalendarState = false,
    this.calendarState,
    this.calendarStateLoading = false,
    this.onRetryCalendarState,
    this.publicHolidayProvider,
    this.clock,
    this.onOpenCourse,
  });

  @override
  State<AcademicScheduleHomeModule> createState() =>
      _AcademicScheduleHomeModuleState();
}

class _AcademicScheduleHomeModuleState
    extends State<AcademicScheduleHomeModule> {
  late final AcademicScheduleStore _store;
  late final ShuweiScheduleImporter _importer;
  late final AcademicScheduleHomeGraduateLoader _graduateLoader;
  late final AcademicScheduleHomeAccountKeyLoader _accountKeyLoader;
  late final AcademicScheduleHomeCalendarStateLoader _calendarStateLoader;
  late final PublicHolidayProvider _publicHolidayProvider;
  PublicHolidayRevisionSource? _publicHolidayRevisionSource;
  late final DateTime Function() _clock;
  List<AcademicPersonalScheduleEntry> _courses = const [];
  TeachingScheduleMode _scheduleMode = TeachingScheduleMode.weishui;
  Object? _error;
  bool _loading = true;
  bool _holiday = false;
  bool _calendarUnavailable = false;
  DateTime? _projectionNow;
  bool _expanded = false;
  int _generation = 0;
  int _publicHolidayGeneration = 0;
  PublicHolidaySnapshot? _publicHolidaySnapshot;
  Object? _publicHolidayError;
  bool _publicHolidayLoading = false;
  bool _publicHolidayPartial = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? AcademicScheduleStore();
    _importer = widget.importer ?? ShuweiScheduleImporter();
    _graduateLoader =
        widget.graduateLoader ??
        ((semesterId) =>
            AcademicAffairsService().fetchGraduateSchedule(semesterId));
    _accountKeyLoader =
        widget.accountKeyLoader ??
        (() async => (await AuthService.getCurrentAccount())?.accountKey);
    _calendarStateLoader =
        widget.calendarStateLoader ??
        (() => AcademicCalendarService().fetchCurrentCalendarState());
    _publicHolidayProvider =
        widget.publicHolidayProvider ?? PublicHolidayCapability();
    final revisionSource = _publicHolidayProvider;
    if (revisionSource is PublicHolidayRevisionSource) {
      final source = revisionSource as PublicHolidayRevisionSource;
      _publicHolidayRevisionSource = source;
      source.revision.addListener(_onPublicHolidayRevision);
    }
    _clock = widget.clock ?? east8Now;
    AcademicScheduleStore.revision.addListener(_onStoreChanged);
    if (!widget.useSharedCalendarState) {
      TemporalChangeService.revision.addListener(_onTemporalChange);
    }
    DemoDataService.revision.addListener(_onDemoChanged);
    if (!widget.useSharedCalendarState || !widget.calendarStateLoading) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _publicHolidayRevisionSource?.revision.removeListener(
      _onPublicHolidayRevision,
    );
    AcademicScheduleStore.revision.removeListener(_onStoreChanged);
    if (!widget.useSharedCalendarState) {
      TemporalChangeService.revision.removeListener(_onTemporalChange);
    }
    DemoDataService.revision.removeListener(_onDemoChanged);
    if (widget.publicHolidayProvider == null) {
      final provider = _publicHolidayProvider;
      if (provider is PublicHolidayCapability) provider.close();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AcademicScheduleHomeModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.useSharedCalendarState &&
        (oldWidget.calendarState != widget.calendarState ||
            oldWidget.calendarStateLoading != widget.calendarStateLoading)) {
      unawaited(_load());
    }
  }

  void _onPublicHolidayRevision() {
    if (!mounted) return;
    unawaited(_loadPublicHolidays(_generation, _clock()));
  }

  void _onDemoChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  void _onStoreChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  void _onTemporalChange() {
    // This module remains mounted in the home layout across midnight.  Reload
    // the cache-backed projection so “today” is derived from the new date.
    if (!mounted) return;
    unawaited(_load(forceWeek: true, forcePublic: true));
  }

  void _clearPublicHolidayState() {
    _publicHolidayGeneration++;
    _publicHolidaySnapshot = null;
    _publicHolidayError = null;
    _publicHolidayLoading = false;
    _publicHolidayPartial = false;
  }

  Future<void> _loadPublicHolidays(
    int scheduleGeneration,
    DateTime now, {
    bool force = false,
  }) async {
    final publicGeneration = ++_publicHolidayGeneration;
    final date = DateTime(now.year, now.month, now.day);
    if (mounted && scheduleGeneration == _generation) {
      setState(() {
        _publicHolidaySnapshot = null;
        _publicHolidayError = null;
        _publicHolidayLoading = true;
        _publicHolidayPartial = false;
      });
    }
    try {
      final snapshot = await _publicHolidayProvider.loadRange(
        date,
        date,
        force: force,
      );
      if (!mounted ||
          scheduleGeneration != _generation ||
          publicGeneration != _publicHolidayGeneration) {
        return;
      }
      setState(() {
        _publicHolidaySnapshot = snapshot;
        _publicHolidayError = null;
        _publicHolidayLoading = false;
        _publicHolidayPartial = snapshot.hasUnavailableYears;
      });
    } catch (error) {
      if (!mounted ||
          scheduleGeneration != _generation ||
          publicGeneration != _publicHolidayGeneration) {
        return;
      }
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.schedule.public_holidays.failed',
        message: '首页今日课表公共节假日加载失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'public_holidays'},
      );
      setState(() {
        _publicHolidayError = error;
        _publicHolidayLoading = false;
        _publicHolidayPartial = false;
      });
    }
  }

  Future<void> _load({bool forceWeek = false, bool forcePublic = false}) async {
    final generation = ++_generation;
    var calendarUnavailable = false;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _calendarUnavailable = false;
        _clearPublicHolidayState();
      });
    }
    if (widget.useSharedCalendarState && widget.calendarStateLoading) {
      if (mounted && generation == _generation) {
        setState(() {
          _courses = const [];
          _holiday = false;
        });
      }
      return;
    }
    try {
      final demo = DemoDataService.instance;
      if (demo.enabled) {
        final holiday = demo.config.holiday;
        final courses = demo.todayCourses() ?? const [];
        if (!mounted || generation != _generation) return;
        setState(() {
          _courses = holiday ? const [] : courses;
          _scheduleMode = TeachingScheduleMode.weishui;
          _holiday = holiday;
          _calendarUnavailable = false;
          _projectionNow = demo.now;
          _loading = false;
          _error =
              demo.config.scheduleError
                  ? const AcademicAffairsException('Demo 课程加载失败')
                  : null;
        });
        unawaited(
          _loadPublicHolidays(generation, _clock(), force: forcePublic),
        );
        return;
      }
      if (widget.useSharedCalendarState) {
        final state = widget.calendarState;
        if (state == null || (state.teachingWeek == null && !state.isHoliday)) {
          calendarUnavailable = true;
          throw const AcademicCalendarException('当前教学周暂不可用');
        }
      }
      final accountKey = await _accountKeyLoader();
      if (accountKey == null || accountKey.trim().isEmpty) {
        throw const AcademicAffairsException('请先登录后查看我的课表');
      }
      final backend = await AcademicAffairsBackendResolver.resolveCurrent();
      var schedule = await _store.readCachedCurrentSchedule(accountKey);
      if (schedule == null) {
        late final AcademicScheduleFetchResult imported;
        if (backend == AcademicAffairsBackend.graduate) {
          imported = await _graduateLoader(null);
        } else {
          imported = await _importer.importSemester();
        }
        final persisted = await _store.saveFetchedSchedule(
          accountKey,
          imported,
        );
        schedule = persisted.schedule;
      }

      CurrentTeachingWeek? currentWeek;
      var holiday = false;
      late final AcademicCalendarState state;
      try {
        if (widget.useSharedCalendarState) {
          state = widget.calendarState!;
        } else {
          state = forceWeek && widget.calendarStateLoader == null
              ? await AcademicCalendarService().fetchCurrentCalendarState(
                  force: true,
                )
              : await _calendarStateLoader();
        }
        currentWeek = state.teachingWeek;
        holiday = state.isHoliday;
        if (currentWeek == null && !holiday) {
          throw const AcademicCalendarException('当前教学周暂不可用');
        }
      } catch (error) {
        calendarUnavailable = true;
        if (mounted && generation == _generation) {
          AppLogger.recordSafeFailure(
            level: 'WARN',
            code: 'home.schedule.teaching_week.failed',
            message: '首页课表教学周加载失败',
            error: error,
            domain: 'home',
            fields: const {'stage': 'teaching_week'},
          );
        }
        throw const AcademicCalendarException('当前教学周暂不可用');
      }
      final scheduleMode = await campusSettingsService.scheduleModeFor(
        accountKey,
      );
      final now = state.fetchedAt;
      final scheduleWeek = currentWeek == null
          ? null
          : scheduleWeekForTeachingWeek(schedule, currentWeek);
      final courses = holiday || (currentWeek != null && scheduleWeek == null)
          ? const <AcademicPersonalScheduleEntry>[]
          : filterScheduleEntriesForDay(
              schedule.entries,
              weekday: now.weekday,
              week: scheduleWeek,
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        _courses = courses;
        _scheduleMode = scheduleMode;
        _holiday = holiday;
        _calendarUnavailable = false;
        _projectionNow = now;
        _loading = false;
        _error = null;
      });
      unawaited(_loadPublicHolidays(generation, now, force: forcePublic));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (!calendarUnavailable) {
        AppLogger.recordSafeFailure(
          code: 'home.schedule.failed',
          message: '首页课表加载失败',
          error: error,
          domain: 'home',
          fields: const {'stage': 'module'},
        );
      }
      setState(() {
        _courses = const [];
        _loading = false;
        _calendarUnavailable = calendarUnavailable;
        _error = error;
      });
      unawaited(_loadPublicHolidays(generation, _clock(), force: forcePublic));
    }
  }

  Future<void> _retry() async {
    if (_calendarUnavailable &&
        widget.useSharedCalendarState &&
        widget.onRetryCalendarState != null) {
      await widget.onRetryCalendarState!();
      return;
    }
    await _load(forceWeek: true);
  }

  Future<void> _openCourse(
    BuildContext context,
    AcademicPersonalScheduleEntry entry,
  ) async {
    final handler = widget.onOpenCourse;
    if (handler != null) {
      await handler(context, entry);
    } else {
      await _defaultOpenCourse(context, entry);
    }
    if (mounted) unawaited(_load());
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  List<AcademicPersonalScheduleEntry> _visibleCourses(DateTime now) {
    if (_expanded || _courses.length <= 2) return _courses;
    final teaching = teachingScheduleFor(_scheduleMode);
    final today = DateTime(now.year, now.month, now.day);
    final active = <AcademicPersonalScheduleEntry>[];
    for (final entry in _courses) {
      final time = teaching.range(entry.startPeriod, entry.endPeriod);
      if (time == null) continue;
      if (time.endAt(today).isAfter(now)) active.add(entry);
    }
    if (active.isNotEmpty) {
      active.sort((left, right) {
        final leftTime = teaching.range(left.startPeriod, left.endPeriod)!;
        final rightTime = teaching.range(right.startPeriod, right.endPeriod)!;
        return leftTime.startAt(today).compareTo(rightTime.startAt(today));
      });
      return active.take(2).toList(growable: false);
    }
    return _courses.length > 2
        ? _courses.sublist(_courses.length - 2)
        : _courses;
  }

  Future<void> _defaultOpenCourse(
    BuildContext context,
    AcademicPersonalScheduleEntry _,
  ) async {
    await openAcademicSchedule(context);
  }

  Future<void> _openSchedule(BuildContext context) async {
    await openAcademicSchedule(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _projectionNow ?? _clock();
    final visibleCourses = _visibleCourses(now);
    late final Widget content;
    if (_loading) {
      content = const _AcademicScheduleHomeLoading();
    } else if (_error case final error?) {
      content = _AcademicScheduleHomeError(error: error, onRetry: _retry);
    } else if (_holiday) {
      content = const _AcademicScheduleHomeHoliday();
    } else if (_courses.isEmpty) {
      content = const _AcademicScheduleHomeEmpty();
    } else {
      content = _AcademicScheduleCourseList(
        courses: visibleCourses,
        scheduleMode: _scheduleMode,
        now: now,
        expanded: _expanded,
        onToggle: _courses.length > 2 ? _toggleExpanded : null,
        onTap: (entry) => unawaited(_openCourse(context, entry)),
      );
    }
    final contentWithPublicHoliday = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_publicHolidayLoading ||
            _publicHolidayError != null ||
            _publicHolidayPartial ||
            _publicHolidaySnapshot?.days.isNotEmpty == true)
          _AcademicScheduleHomePublicHolidayNotice(
            snapshot: _publicHolidaySnapshot,
            loading: _publicHolidayLoading,
            error: _publicHolidayError,
            partial: _publicHolidayPartial,

            onRetry:
                () => unawaited(
                  _loadPublicHolidays(_generation, now, force: true),
                ),
          ),
        content,
      ],
    );
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final weekStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final card = Card.outlined(
      key: const ValueKey('academic-schedule-home-card'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: contentWithPublicHoliday,
    );
    final tappableCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_openSchedule(context)),
      child: card,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(child: Text('今日课表', style: headingStyle)),
              if (!_loading && _error == null)
                Text('共${_courses.length}节', style: weekStyle),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(width: double.infinity, child: tappableCard),
      ],
    );
  }
}

class _AcademicScheduleHomePublicHolidayNotice extends StatelessWidget {
  final PublicHolidaySnapshot? snapshot;
  final bool loading;
  final Object? error;
  final bool partial;

  final VoidCallback onRetry;

  const _AcademicScheduleHomePublicHolidayNotice({
    required this.snapshot,
    required this.loading,
    required this.error,
    required this.partial,

    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final textStyle = TextStyle(
      color: secondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final days = snapshot?.days ?? const <PublicHolidayDay>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Semantics(
        container: true,
        label: '今日公共节假日提示',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_available_outlined, size: 16, color: secondary),
            const SizedBox(width: 6),
            Expanded(
              child:
                  loading
                      ? Text('公共节假日加载中…', style: textStyle)
                      : error != null
                      ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          Text('公共节假日暂不可用', style: textStyle),
                          TextButton(
                            onPressed: onRetry,
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('重试'),
                          ),
                        ],
                      )
                      : Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final day in days)
                            PublicHolidayLabel(
                              day: day,
                              showName: false,

                              style: textStyle,
                            ),
                          if (partial) Text('部分数据暂不可用', style: textStyle),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcademicScheduleHomeLoading extends StatelessWidget {
  const _AcademicScheduleHomeLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('academic-schedule-home-loading'),
      height: _courseRowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '加载中…',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _AcademicScheduleHomeError extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const _AcademicScheduleHomeError({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _courseListHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                academicErrorMessage(error),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => unawaited(onRetry()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademicScheduleHomeEmpty extends StatelessWidget {
  const _AcademicScheduleHomeEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('academic-schedule-home-empty'),
      height: _courseRowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '今天暂无课程安排',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _AcademicScheduleHomeHoliday extends StatelessWidget {
  const _AcademicScheduleHomeHoliday();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('academic-schedule-home-holiday'),
      height: _courseRowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '假期中',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _AcademicScheduleCourseList extends StatelessWidget {
  final List<AcademicPersonalScheduleEntry> courses;
  final TeachingScheduleMode scheduleMode;
  final DateTime now;
  final bool expanded;
  final VoidCallback? onToggle;
  final ValueChanged<AcademicPersonalScheduleEntry> onTap;

  const _AcademicScheduleCourseList({
    required this.courses,
    required this.scheduleMode,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('academic-schedule-home-courses'),
      children: [
        for (var index = 0; index < courses.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          SizedBox(
            height: _courseRowHeight,
            child: AcademicScheduleCourseRow(
              entry: courses[index],
              scheduleMode: scheduleMode,
              now: now,
              onTap: () => onTap(courses[index]),
            ),
          ),
        ],
        if (onToggle != null) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          _AcademicScheduleHomeToggle(expanded: expanded, onTap: onToggle!),
        ],
      ],
    );
  }
}

class _AcademicScheduleHomeToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _AcademicScheduleHomeToggle({
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            expanded ? '收起' : '展开全部',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );

    return InkWell(
      key: const ValueKey('academic-schedule-home-toggle'),
      onTap: onTap,
      child: child,
    );
  }
}

class AcademicScheduleCourseRow extends StatelessWidget {
  final AcademicPersonalScheduleEntry entry;
  final TeachingScheduleMode scheduleMode;
  final DateTime now;
  final VoidCallback onTap;

  const AcademicScheduleCourseRow({
    super.key,
    required this.entry,
    required this.scheduleMode,
    required this.now,
    required this.onTap,
  });

  bool get ended => _isEnded(entry, now);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final ended = this.ended;
    final inactive = ended ? muted.withValues(alpha: 0.55) : null;
    final location = cleanScheduleLocation(entry.location);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color:
                  ended
                      ? (theme.colorScheme.outlineVariant)
                      : (theme.colorScheme.primary),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: inactive,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  location.isEmpty ? '未安排教室' : location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.2,
                    color: inactive ?? muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _durationLabel(entry, scheduleMode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    height: 1.2,
                    color: inactive ?? muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return InkWell(onTap: onTap, child: child);
  }

  String _durationLabel(
    AcademicPersonalScheduleEntry entry,
    TeachingScheduleMode scheduleMode,
  ) {
    final time = teachingScheduleFor(
      scheduleMode,
    ).range(entry.startPeriod, entry.endPeriod);
    final periodLabel =
        entry.startPeriod == entry.endPeriod
            ? '第${entry.startPeriod}节'
            : '第${entry.startPeriod}-${entry.endPeriod}节';
    return time == null ? periodLabel : '$periodLabel ${time.rangeText}';
  }

  bool _isEnded(AcademicPersonalScheduleEntry entry, DateTime now) {
    final time = teachingScheduleFor(
      scheduleMode,
    ).range(entry.startPeriod, entry.endPeriod);
    if (time == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    return !time.endAt(today).isAfter(now);
  }
}
