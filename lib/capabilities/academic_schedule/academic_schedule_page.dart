import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../campus_map/campus_map_capability.dart';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_affairs/academic_affairs_service.dart';
import '../../apps/academic_affairs/academic_affairs_widgets.dart';
import '../../services/auth_service.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/user_error_message.dart';
import '../../services/campus_settings_service.dart';
import '../../services/guide_preferences.dart';
import '../../services/onboarding_flow_service.dart';
import '../../services/file_save_service.dart';
import '../../services/host_permission_service.dart';
import '../../services/live_update_service.dart';
import '../../services/logger_service.dart';
import '../../services/teaching_schedule_service.dart';
import '../../services/temporal_change_service.dart';
import '../east8_time.dart';
import '../../services/platform_environment.dart';
import '../../widgets/adaptive_action_sheet.dart';
import '../../widgets/adaptive_confirmation_dialog.dart';
import '../../widgets/adaptive_feedback.dart';
import '../../widgets/coach_mark_presenter.dart';
import '../../widgets/root_destination_active_scope.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import '../desktop_widgets/desktop_widget_bridge.dart';
import '../../apps/academic_web/shuwei_schedule_importer.dart';
import 'academic_schedule_live_update.dart';
import 'academic_schedule_alerts.dart';
import 'academic_schedule_editor.dart';
import 'academic_schedule_export.dart';
import 'academic_schedule_store.dart';
import 'academic_schedule_utils.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

typedef AcademicScheduleAccountKeyLoader = Future<String?> Function();
typedef AcademicScheduleCalendarLoader =
    Future<AcademicScheduleCalendarSelection?> Function(
      AcademicPersonalSchedule schedule, {
      bool force,
    });
typedef AcademicScheduleCurrentCalendarLoader =
    Future<AcademicCalendarData?> Function({bool force});
typedef AcademicScheduleAcquisitionLoader =
    Future<AcademicScheduleFetchResult> Function(
      String? semesterId,
      AcademicScheduleScope scope,
    );

bool _isLoginRequired(Object error) =>
    error is AcademicAffairsAuthenticationException ||
    (error is AcademicAffairsException && error.message == '请先登录后查看我的课表');

class AcademicScheduleCalendarSelection {
  final AcademicCalendarData calendar;
  final bool isCurrentTerm;

  const AcademicScheduleCalendarSelection({
    required this.calendar,
    required this.isCurrentTerm,
  });
}

const _scheduleLeftWidth = 28.0;

class AcademicSchedulePage extends StatefulWidget {
  final AcademicScheduleStore? store;
  final AcademicScheduleAccountKeyLoader? accountKeyLoader;
  final AcademicScheduleCalendarLoader? calendarLoader;
  final AcademicScheduleCurrentCalendarLoader? currentCalendarLoader;
  final AcademicScheduleAcquisitionLoader? acquisitionLoader;
  final DateTime Function()? clock;

  final AcademicAffairsBackend? backendOverride;

  const AcademicSchedulePage({
    super.key,
    this.store,
    this.accountKeyLoader,
    this.calendarLoader,
    this.currentCalendarLoader,
    this.acquisitionLoader,
    this.clock,
    this.backendOverride,
  });

  @override
  State<AcademicSchedulePage> createState() => _AcademicSchedulePageState();
}

class _AcademicSchedulePageState extends State<AcademicSchedulePage> {
  late final AcademicScheduleStore _store;
  late final AcademicScheduleAccountKeyLoader _accountKeyLoader;
  late final AcademicScheduleCalendarLoader _calendarLoader;
  late final AcademicScheduleCurrentCalendarLoader? _currentCalendarLoader;
  late final DateTime Function() _clock;
  final _scheduleImporter = ShuweiScheduleImporter();
  PageController _weekController = PageController();
  int _controllerGeneration = 0;

  AcademicPersonalSchedule? _schedule;
  List<AcademicSemesterOption> _semesters = const [];
  AcademicScheduleScope _scope = AcademicScheduleScope.personal;
  String? _accountKey;
  AcademicAffairsBackend? _academicBackend;
  AcademicCalendarData? _calendar;
  AcademicCalendarWeek? _currentCalendarWeek;
  bool _isHoliday = false;
  AcademicPersonalScheduleEntry? _selectedInspectorEntry;
  List<AcademicPersonalScheduleEntry>? _selectedInspectorSources;
  final Map<String, String> _personalConflictSelections = {};
  int _visiblePage = 0;
  bool _showNonCurrent = true;
  bool _hideWeekend = false;
  TeachingScheduleMode _scheduleMode = TeachingScheduleMode.weishui;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _exporting = false;
  bool _liveUpdateEnabled = false;
  bool _liveUpdateWorking = false;
  int _loadGeneration = 0;
  final GlobalKey _firstCourseKey = GlobalKey();
  final GlobalKey _scheduleScopeKey = GlobalKey();
  final GlobalKey _scheduleOptionsKey = GlobalKey();
  final GuidePreferences _guidePreferences = GuidePreferences();
  bool _featureTourScheduled = false;
  bool _featureTourRunning = false;
  bool _unavailableAdvanceScheduled = false;

  bool get _supportsLiveUpdate => LiveUpdateService.isSupported;

  @override
  void initState() {
    super.initState();
    CampusSettingsService.revision.addListener(_onCampusSettingsChanged);
    TemporalChangeService.revision.addListener(_onTemporalChange);
    AcademicScheduleDisplayPreferences.revision.addListener(
      _onDisplayPreferencesChanged,
    );
    _store = widget.store ?? AcademicScheduleStore();
    _accountKeyLoader =
        widget.accountKeyLoader ??
        (() async => (await AuthService.getCurrentAccount())?.accountKey);
    _calendarLoader =
        widget.calendarLoader ??
        ((schedule, {force = false}) =>
            _fetchCalendarForSchedule(schedule, force: force));
    _currentCalendarLoader =
        widget.currentCalendarLoader ??
        ({bool force = false}) =>
            AcademicCalendarService().fetchCurrentCalendar(force: force);
    _clock = widget.clock ?? east8Now;
    unawaited(_loadInitial());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleFeatureTour();
  }

  bool get _destinationActive =>
      RootDestinationActiveScope.activeOf(context) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _scheduleFeatureTour() {
    if (OnboardingFlowService.step != OnboardingFlowStep.schedule ||
        _featureTourScheduled ||
        _featureTourRunning ||
        _loading ||
        _refreshing ||
        !_destinationActive) {
      return;
    }
    if (_schedule == null || _error != null) {
      if (_unavailableAdvanceScheduled) return;
      _unavailableAdvanceScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _unavailableAdvanceScheduled = false;
        if (mounted &&
            !_loading &&
            !_refreshing &&
            (_schedule == null || _error != null) &&
            _destinationActive) {
          unawaited(OnboardingFlowService.finish());
        }
      });
      return;
    }
    _featureTourScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _featureTourScheduled = false;
      unawaited(_maybeShowFeatureTour());
    });
  }

  Future<void> _maybeShowFeatureTour() async {
    if (!mounted ||
        OnboardingFlowService.step != OnboardingFlowStep.schedule ||
        _featureTourRunning ||
        _loading ||
        _refreshing ||
        _schedule == null ||
        _error != null ||
        !_destinationActive) {
      return;
    }
    _featureTourRunning = true;
    var presented = false;
    try {
      const id = GuidePreferences.scheduleFeatureTourHintId;
      const version = GuidePreferences.currentHintVersion;
      if (!mounted ||
          OnboardingFlowService.step != OnboardingFlowStep.schedule ||
          !_destinationActive ||
          _scheduleOptionsKey.currentContext == null) {
        return;
      }

      final steps = <CoachMarkStep>[];
      if (_firstCourseKey.currentContext != null) {
        steps.add(
          CoachMarkStep(
            targetKey: _firstCourseKey,
            title: '查看课程详情',
            message: '点击展开该课程详情信息',
            contentAlign: ContentAlign.bottom,
          ),
        );
      }
      if (_scheduleScopeKey.currentContext != null) {
        steps.add(
          CoachMarkStep(
            targetKey: _scheduleScopeKey,
            title: '切换个人/班级课表',
            message: '点击标题旁的“个人”或“班级”，切换课表范围。',
            contentAlign: ContentAlign.bottom,
          ),
        );
      }
      final isPersonal = _scope == AcademicScheduleScope.personal;
      steps.add(
        CoachMarkStep(
          targetKey: _scheduleOptionsKey,
          title: '课表选项',
          message:
              isPersonal
                  ? '这里可导出、添加课程或恢复原始课表；点击课程后还可进入详情编辑。'
                  : '导出、刷新和课程显示选项都在这里；切换到个人课表后还可添加或编辑课程。',
          contentAlign: ContentAlign.bottom,
        ),
      );
      presented = CoachMarkPresenter.show(
        context,

        onFinished: () {
          _featureTourRunning = false;
          unawaited(_guidePreferences.markHintSeen(id, version));
          unawaited(OnboardingFlowService.finish());
        },
        steps: steps,
      );
    } finally {
      if (!presented) {
        _featureTourRunning = false;
        if (mounted &&
            OnboardingFlowService.step == OnboardingFlowStep.schedule &&
            _destinationActive &&
            _scheduleOptionsKey.currentContext != null) {
          unawaited(OnboardingFlowService.finish());
        }
      }
    }
  }

  void _onCampusSettingsChanged() {
    final accountKey = _accountKey;
    if (!mounted || accountKey == null) return;
    unawaited(_refreshScheduleMode(accountKey));
  }

  void _onTemporalChange() {
    final schedule = _schedule;
    if (!mounted || schedule == null || _loading || _refreshing) return;
    final generation = _loadGeneration;
    unawaited(_loadCalendar(generation, schedule, force: true));
    if (_scope == AcademicScheduleScope.personal) {
      _refreshPersonalSurfaces();
    }
  }

  Future<void> _refreshScheduleMode(String accountKey) async {
    final mode = await campusSettingsService.scheduleModeFor(accountKey);
    if (!mounted || _accountKey != accountKey || _scheduleMode == mode) return;
    setState(() => _scheduleMode = mode);
    if (_liveUpdateEnabled && _supportsLiveUpdate) {
      unawaited(
        LiveUpdateService.refreshDefinition(
          academicScheduleLiveUpdateDefinition.id,
        ),
      );
    }
  }

  void _onDisplayPreferencesChanged() {
    final accountKey = _accountKey;
    if (!mounted || accountKey == null) return;
    unawaited(() async {
      final values = await Future.wait([
        AcademicScheduleDisplayPreferences.readShowNonCurrent(accountKey),
        AcademicScheduleDisplayPreferences.readHideWeekend(accountKey),
      ]);
      if (!mounted) return;
      final showNonCurrent = values[0];
      final hideWeekend = values[1];
      if (showNonCurrent != _showNonCurrent || hideWeekend != _hideWeekend) {
        setState(() {
          _showNonCurrent = showNonCurrent;
          _hideWeekend = hideWeekend;
        });
      }
    }());
  }

  @override
  void dispose() {
    CampusSettingsService.revision.removeListener(_onCampusSettingsChanged);
    TemporalChangeService.revision.removeListener(_onTemporalChange);
    AcademicScheduleDisplayPreferences.revision.removeListener(
      _onDisplayPreferencesChanged,
    );
    _weekController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (widget.acquisitionLoader == null) {
        _academicBackend =
            widget.backendOverride ??
            await AcademicAffairsBackendResolver.resolveCurrent();
      } else {
        _academicBackend = widget.backendOverride;
      }
      final accountKey = await _accountKeyLoader();
      if (accountKey == null || accountKey.trim().isEmpty) {
        throw const AcademicAffairsException('请先登录后查看我的课表');
      }
      final scheduleMode = await campusSettingsService.scheduleModeFor(
        accountKey,
      );
      if (!mounted || generation != _loadGeneration) return;
      _scheduleMode = scheduleMode;

      final catalog = await _store.readCachedSemesterCatalog(accountKey);
      var semesters = academicSemestersNewestFirst(
        catalog?.semesters ?? const <AcademicSemesterOption>[],
      );
      AcademicPersonalSchedule? schedule;
      AcademicScheduleCalendarSelection? initialCalendarSelection;
      final currentCalendar = await _readCurrentCalendar();
      if (currentCalendar != null) {
        final currentSemesterId =
            semesters
                .where(
                  (semester) => academicSemesterLabelsMatch(
                    currentCalendar.term.label,
                    semester.label,
                  ),
                )
                .map((semester) => semester.id.trim())
                .where((id) => id.isNotEmpty)
                .firstOrNull;
        if (currentSemesterId != null) {
          schedule = await _store.readCachedSchedule(
            accountKey,
            currentSemesterId,
          );
        }
        if (schedule == null) {
          final cachedCurrent = await _store.readCachedCurrentSchedule(
            accountKey,
          );
          if (cachedCurrent != null &&
              _scheduleMatchesCalendar(cachedCurrent, currentCalendar)) {
            schedule = cachedCurrent;
          }
        }
        if (schedule == null) {
          try {
            final imported = await _acquireSchedule(
              accountKey,
              currentSemesterId,
              AcademicScheduleScope.personal,
            );
            schedule = imported.schedule;
            semesters = imported.semesters;
          } catch (_) {
            schedule = null;
          }
        }
        if (schedule != null &&
            _scheduleMatchesCalendar(schedule, currentCalendar)) {
          initialCalendarSelection = AcademicScheduleCalendarSelection(
            calendar: currentCalendar,
            isCurrentTerm: true,
          );
        } else {
          schedule = null;
        }
      }
      if (schedule == null) {
        for (final semester in semesters) {
          final id = semester.id.trim();
          if (id.isEmpty) continue;
          schedule = await _store.readCachedSchedule(accountKey, id);
          if (schedule != null) break;
        }
      }
      schedule ??= await _store.readCachedCurrentSchedule(accountKey);
      if (schedule == null) {
        final imported = await _acquireSchedule(
          accountKey,
          null,
          AcademicScheduleScope.personal,
        );
        schedule = imported.schedule;
        semesters = imported.semesters;
      }
      semesters = academicSemestersNewestFirst(semesters);

      final displayPreferences = await Future.wait([
        AcademicScheduleDisplayPreferences.readShowNonCurrent(accountKey),
        AcademicScheduleDisplayPreferences.readHideWeekend(accountKey),
      ]);
      final showNonCurrent = displayPreferences[0];
      final hideWeekend = displayPreferences[1];
      final liveUpdateEnabled =
          _supportsLiveUpdate &&
          await LiveUpdatePreferences.isEnabled(
            accountKey,
            academicScheduleLiveUpdateDefinition.id,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _accountKey = accountKey;
        _scope = AcademicScheduleScope.personal;
        _schedule = schedule;
        _semesters = semesters;
        _resetCalendarAndPager();
        _showNonCurrent = showNonCurrent;
        _hideWeekend = hideWeekend;
        _liveUpdateEnabled = liveUpdateEnabled;
        _loading = false;
        _error = null;
      });
      scheduleAcademicCourseAlerts(accountKey, schedule);
      if (initialCalendarSelection == null && currentCalendar != null) {
        if (_scheduleMatchesCalendar(schedule, currentCalendar)) {
          initialCalendarSelection = AcademicScheduleCalendarSelection(
            calendar: currentCalendar,
            isCurrentTerm: true,
          );
        }
      }
      unawaited(
        _loadCalendar(
          generation,
          schedule,
          selection: initialCalendarSelection,
        ),
      );
      if (liveUpdateEnabled && _supportsLiveUpdate) {
        unawaited(
          LiveUpdateService.refreshDefinition(
            academicScheduleLiveUpdateDefinition.id,
          ),
        );
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      if (!_isLoginRequired(error)) {
        logUserFacingError(
          UserErrorContext.academic,
          error,
          operationId: UserOperationId.academicSchedule,
        );
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadCalendar(
    int generation,
    AcademicPersonalSchedule schedule, {
    bool force = false,
    AcademicScheduleCalendarSelection? selection,
  }) async {
    try {
      selection ??= await _calendarLoader(schedule, force: force);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'academic.schedule.calendar.failed',
        message: '课表校历加载失败',
        error: error,
        domain: 'academic',
        fields: const {'stage': 'calendar'},
      );
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    final calendar = selection?.calendar;
    final currentWeek =
        selection?.isCurrentTerm == true ? calendar?.weekFor(_clock()) : null;
    final isHoliday = currentWeek?.isHoliday == true;
    // The calendar loader already decides which calendar belongs to the
    // selected schedule. Keep opening its current week for the pager, while
    // schedule↔teaching-week membership for highlights uses the shared
    // [scheduleWeekForTeachingWeek] helper below.
    final autoWeek =
        currentWeek == null || currentWeek.isHoliday
            ? null
            : currentWeek.week >= 1 && currentWeek.week <= schedule.maxWeek
            ? currentWeek.week
            : null;
    final wasSelectedHoliday = _selectedHoliday;
    final shouldAutoSelect = _visiblePage == 0 || (force && wasSelectedHoliday);
    setState(() {
      _calendar = calendar;
      _currentCalendarWeek = currentWeek;
      _isHoliday = isHoliday;
    });
    if (isHoliday) {
      _setVisiblePage(_holidayPageIndex, jump: true);
    } else if (autoWeek != null && shouldAutoSelect) {
      _setVisiblePage(autoWeek, jump: true);
    }
    if (calendar != null) unawaited(DesktopWidgetSyncService.refresh());
  }

  Future<AcademicCalendarData?> _readCurrentCalendar() async {
    final loader = _currentCalendarLoader;
    if (loader == null) return null;
    try {
      return await loader(force: false);
    } catch (error) {
      if (!mounted) return null;
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'academic.schedule.calendar_cache.failed',
        message: '课表当前校历读取失败',
        error: error,
        domain: 'academic',
        fields: const {'stage': 'calendar_cache'},
      );
      return null;
    }
  }

  /// Recreates the week pager so it opens at [initialPage]. The outgoing
  /// controller is disposed after the frame, once the PageView has detached
  /// from it.
  void _recreateWeekController(int initialPage) {
    final maxPage = math.max(0, _pageCount - 1);
    final old = _weekController;
    _weekController = PageController(
      initialPage: initialPage.clamp(0, maxPage),
    );
    _controllerGeneration++;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Updates the single pager selection owner and optionally moves the
  /// existing controller to the selected page.
  void _setVisiblePage(int page, {bool jump = false}) {
    if (!mounted) return;
    final maxPage = math.max(0, _pageCount - 1);
    final next = page.clamp(0, maxPage).toInt();
    if (_visiblePage != next) {
      setState(() => _visiblePage = next);
    }
    if (!jump) return;
    if (_weekController.hasClients) {
      _weekController.jumpToPage(next);
    } else {
      _recreateWeekController(next);
    }
  }

  int get _pageCount {
    final maxWeek = math.max(1, _schedule?.maxWeek ?? 1);
    return 1 + maxWeek + (_isHoliday ? 1 : 0);
  }

  int get _holidayPageIndex {
    final maxWeek = math.max(1, _schedule?.maxWeek ?? 1);
    return maxWeek + 1;
  }

  int? get _currentPageIndex {
    if (_isHoliday) return _holidayPageIndex;
    return _currentScheduleWeek;
  }

  int get _selectedPageIndex => _visiblePage;

  bool get _selectedHoliday => _isHoliday && _visiblePage == _holidayPageIndex;

  int? get _selectedWeek {
    if (_visiblePage == 0 || _selectedHoliday) return null;
    return _visiblePage;
  }

  /// The current teaching week number from the selected school calendar.
  int? get _currentScheduleWeek {
    final schedule = _schedule;
    final currentWeek = _currentCalendarWeek;
    if (schedule == null || currentWeek == null || currentWeek.isHoliday) {
      return null;
    }
    final term = _calendar?.term.label;
    if (term == null) return null;
    return scheduleWeekForTeachingWeek(
      schedule,
      CurrentTeachingWeek(
        week: currentWeek.week,
        term: term,
        termStartDate: _calendar?.term.startDate,
      ),
    );
  }

  /// Returns the exact start date of [week] from the mobile-campus calendar.
  DateTime? _weekStartDate(int week) {
    return _calendar?.weeks
        .where((item) => item.week == week)
        .firstOrNull
        ?.startDate;
  }

  Future<AcademicScheduleCalendarSelection?> _fetchCalendarForSchedule(
    AcademicPersonalSchedule schedule, {
    bool force = false,
  }) async {
    final service = AcademicCalendarService();
    final current = await service.fetchCurrentCalendar(force: force);
    if (_scheduleMatchesCalendar(schedule, current)) {
      return AcademicScheduleCalendarSelection(
        calendar: current,
        isCurrentTerm: true,
      );
    }

    final terms = await service.fetchTerms(force: force);
    final term =
        terms
            .where(
              (candidate) => academicSemesterLabelsMatch(
                candidate.label,
                schedule.semesterLabel,
              ),
            )
            .firstOrNull;
    if (term == null) return null;
    return AcademicScheduleCalendarSelection(
      calendar: await service.fetchCalendar(term, force: force),
      isCurrentTerm: false,
    );
  }

  bool _scheduleMatchesCalendar(
    AcademicPersonalSchedule schedule,
    AcademicCalendarData calendar,
  ) => academicScheduleSemesterMatches(schedule, calendar.term.label);

  Future<AcademicScheduleFetchResult> _acquireSchedule(
    String accountKey,
    String? semesterId,
    AcademicScheduleScope scope,
  ) async {
    late final AcademicScheduleFetchResult imported;
    final acquisitionLoader = widget.acquisitionLoader;
    if (acquisitionLoader != null) {
      imported = await acquisitionLoader(semesterId, scope);
    } else {
      final backend =
          _academicBackend ??
          await AcademicAffairsBackendResolver.resolveCurrent();
      if (scope == AcademicScheduleScope.administrativeClass &&
          backend != AcademicAffairsBackend.undergraduate) {
        throw const AcademicAffairsException('当前身份暂不支持班级课表');
      }
      if (backend == AcademicAffairsBackend.graduate) {
        imported = await AcademicAffairsService().fetchGraduateSchedule(
          semesterId,
        );
      } else {
        imported = await _scheduleImporter.importSchedule(
          semesterId: semesterId,
          scope: scope,
        );
      }
    }
    return _store.saveFetchedSchedule(accountKey, imported, scope: scope);
  }

  /// Replaces the calendar context together with the pager's selection.
  ///
  /// This is intentionally a small page transition helper: the schedule has
  /// already been installed by the caller, so the pager is recreated against
  /// the new schedule's page count.
  void _resetCalendarAndPager() {
    _calendar = null;
    _currentCalendarWeek = null;
    _isHoliday = false;
    _visiblePage = 0;
    _recreateWeekController(0);
  }

  Future<void> _refreshSchedule() async {
    final scope = _scope;
    final accountKey = _accountKey ?? await _accountKeyLoader();
    if (accountKey == null || accountKey.trim().isEmpty) {
      if (mounted) {
        setState(() => _error = const AcademicAffairsException('请先登录后查看我的课表'));
      }
      return;
    }
    setState(() {
      _accountKey = accountKey;
      _refreshing = true;
      _error = null;
    });
    try {
      final selectedSemester = _schedule?.semesterId.trim();
      final result = await _acquireSchedule(
        accountKey,
        selectedSemester?.isNotEmpty == true ? selectedSemester : null,
        scope,
      );
      final schedule = result.schedule;
      final generation = ++_loadGeneration;
      if (!mounted) return;
      setState(() {
        _accountKey = accountKey;
        _schedule = schedule;
        _semesters = academicSemestersNewestFirst(result.semesters);
        _resetCalendarAndPager();
        _refreshing = false;
        _error = null;
      });
      unawaited(_loadCalendar(generation, schedule, force: true));
      if (scope == AcademicScheduleScope.personal) {
        _refreshPersonalSurfaces();
      }
    } catch (error) {
      if (!mounted) return;
      if (!_isLoginRequired(error)) {
        logUserFacingError(
          UserErrorContext.academic,
          error,
          operationId: UserOperationId.academicSchedule,
        );
      }
      setState(() {
        _refreshing = false;
        _error = error;
      });
    }
  }

  void _refreshPersonalSurfaces() {
    if (_liveUpdateEnabled) {
      unawaited(
        LiveUpdateService.refreshDefinition(
          academicScheduleLiveUpdateDefinition.id,
          forceRefresh: true,
        ),
      );
    }
  }

  Future<void> _changeSemester(String? semesterId) async {
    final scope = _scope;
    final targetSemester = semesterId?.trim() ?? '';
    if (targetSemester.isEmpty ||
        targetSemester == _schedule?.semesterId.trim() ||
        _loading ||
        _refreshing) {
      return;
    }
    final accountKey = _accountKey ?? await _accountKeyLoader();
    if (accountKey == null || accountKey.trim().isEmpty) return;

    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await _store.activateCachedSchedule(
            accountKey,
            targetSemester,
            scope: scope,
          ) ??
          await _acquireSchedule(accountKey, targetSemester, scope);
      final schedule = result.schedule;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _schedule = schedule;
        _semesters = academicSemestersNewestFirst(result.semesters);
        _personalConflictSelections.clear();
        _resetCalendarAndPager();
        _loading = false;
        _error = null;
      });
      unawaited(_loadCalendar(generation, schedule));
      if (scope == AcademicScheduleScope.personal) {
        _refreshPersonalSurfaces();
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      if (!_isLoginRequired(error)) {
        logUserFacingError(
          UserErrorContext.academic,
          error,
          operationId: UserOperationId.academicSchedule,
        );
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _changeScope(AcademicScheduleScope scope) async {
    if (scope == _scope || _loading || _refreshing) return;
    if (scope == AcademicScheduleScope.administrativeClass &&
        _academicBackend != AcademicAffairsBackend.undergraduate) {
      return;
    }
    final accountKey = _accountKey ?? await _accountKeyLoader();
    if (accountKey == null || accountKey.trim().isEmpty) return;

    final requestedSemester = _schedule?.semesterId.trim() ?? '';
    final previousSemesters = _semesters;
    final generation = ++_loadGeneration;
    setState(() {
      _scope = scope;
      _schedule = null;
      _personalConflictSelections.clear();
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _store.readCachedSemesterCatalog(
        accountKey,
        scope: scope,
      );
      var semesters =
          catalog?.semesters.isNotEmpty == true
              ? catalog!.semesters
              : previousSemesters;
      final semesterId =
          requestedSemester.isNotEmpty
              ? requestedSemester
              : catalog?.selectedSemesterId.trim() ?? '';
      AcademicScheduleFetchResult? result;
      if (semesterId.isNotEmpty) {
        result = await _store.activateCachedSchedule(
          accountKey,
          semesterId,
          scope: scope,
        );
        if (result != null) semesters = result.semesters;
      }
      var schedule = result?.schedule;
      schedule ??= await _store.readCachedSchedule(
        accountKey,
        semesterId.isEmpty ? null : semesterId,
        scope: scope,
      );
      schedule ??= await _store.readCachedCurrentSchedule(
        accountKey,
        scope: scope,
      );
      if (schedule == null) {
        result = await _acquireSchedule(
          accountKey,
          semesterId.isEmpty ? null : semesterId,
          scope,
        );
        schedule = result.schedule;
        semesters = result.semesters;
      } else if (result == null) {
        final activated = await _store.activateCachedSchedule(
          accountKey,
          schedule.semesterId,
          scope: scope,
        );
        if (activated != null) {
          result = activated;
          schedule = activated.schedule;
          semesters = activated.semesters;
        }
      }
      final resolvedSchedule = schedule;
      if (!mounted || generation != _loadGeneration || _scope != scope) return;
      setState(() {
        _schedule = resolvedSchedule;
        _semesters = academicSemestersNewestFirst(semesters);
        _resetCalendarAndPager();
        _loading = false;
        _error = null;
      });
      unawaited(_loadCalendar(generation, resolvedSchedule));
    } catch (error) {
      if (!mounted || generation != _loadGeneration || _scope != scope) return;
      if (!_isLoginRequired(error)) {
        logUserFacingError(
          UserErrorContext.academic,
          error,
          operationId: UserOperationId.academicSchedule,
        );
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleFeatureTour();

    final body = _buildBody(context);
    late final Widget page;
    {
      page = Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(
            title: _buildAppBarTitle(context),
            actions: [
              _buildMaterialSemesterButton(),
              _buildMaterialWeekButton(),
              if (_refreshing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                SizedBox(
                  key: _scheduleOptionsKey,
                  child: PopupMenuButton<String>(
                    tooltip: '课表选项',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'currentWeek') {
                        _returnToCurrentWeek();
                      } else if (value == 'showNonCurrent') {
                        _toggleShowNonCurrent();
                      } else if (value == 'hideWeekend') {
                        _toggleHideWeekend();
                      } else if (value == 'refresh') {
                        unawaited(_refreshSchedule());
                      } else if (value == 'liveUpdate') {
                        unawaited(_toggleLiveUpdate());
                      } else if (value == 'export') {
                        unawaited(_showExportMenu());
                      } else if (value == 'addCourse') {
                        unawaited(_openCourseEditor());
                      } else if (value == 'restoreOriginal') {
                        unawaited(_restoreOriginalSchedule());
                      }
                    },
                    itemBuilder:
                        (context) => [
                          PopupMenuItem<String>(
                            value: 'currentWeek',
                            enabled: _currentPageIndex != null,
                            child: const Text('返回当前周'),
                          ),
                          const PopupMenuDivider(),
                          CheckedPopupMenuItem<String>(
                            value: 'showNonCurrent',
                            checked: _showNonCurrent,
                            child: const Text('显示非本周课程'),
                          ),
                          CheckedPopupMenuItem<String>(
                            value: 'hideWeekend',
                            checked: _hideWeekend,
                            child: const Text('不显示周末'),
                          ),
                          if (_scope == AcademicScheduleScope.personal &&
                              _supportsLiveUpdate)
                            CheckedPopupMenuItem<String>(
                              value: 'liveUpdate',
                              checked: _liveUpdateEnabled,
                              enabled: !_liveUpdateWorking,
                              child: Text(
                                _liveUpdateWorking ? '正在更新实时动态' : '课程实时动态',
                              ),
                            ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'export',
                            child: Text('导出'),
                          ),
                          if (_scope == AcademicScheduleScope.personal)
                            const PopupMenuItem<String>(
                              value: 'addCourse',
                              child: Text('添加课程'),
                            ),
                          if (_scope == AcademicScheduleScope.personal)
                            const PopupMenuItem<String>(
                              value: 'restoreOriginal',
                              child: Text('恢复原始课表'),
                            ),
                          PopupMenuItem<String>(
                            value: 'refresh',
                            child: Text(
                              _scope ==
                                      AcademicScheduleScope.administrativeClass
                                  ? '重新获取班级课表'
                                  : '重新获取课程',
                            ),
                          ),
                        ],
                  ),
                ),
            ],
          ),
        ),
        body: body,
      );
    }
    return page;
  }

  Widget _buildBody(BuildContext context) {
    final environment = PlatformEnvironment.fromContext(context);
    final expandedTablet =
        environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded;
    Widget buildScheduleStack() {
      return KeyedSubtree(
        key: const ValueKey('academic-schedule-canvas'),
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent(context)),
            if (_loading && _schedule != null)
              Positioned.fill(
                child: _ScheduleLoadingOverlay(
                  label:
                      _scope == AcademicScheduleScope.administrativeClass
                          ? '正在加载班级课表…'
                          : '正在加载课表…',
                ),
              ),
          ],
        ),
      );
    }

    final showInspector = expandedTablet && _selectedInspectorEntry != null;
    Widget buildExpandedTabletBody() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final inspectorWidth =
              (constraints.maxWidth * 0.30).clamp(320.0, 360.0).toDouble();
          return Row(
            children: [
              Expanded(child: buildScheduleStack()),
              const VerticalDivider(width: 1),
              SizedBox(
                width: inspectorWidth,
                child: KeyedSubtree(
                  key: const ValueKey('academic-schedule-inspector'),
                  child: _buildTabletInspector(context),
                ),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        if (_loading && _schedule == null)
          Expanded(
            child: _ScheduleLoadingState(
              label:
                  _scope == AcademicScheduleScope.administrativeClass
                      ? '正在加载班级课表…'
                      : '正在加载课表…',
            ),
          )
        else ...[
          Expanded(
            child:
                showInspector
                    ? buildExpandedTabletBody()
                    : buildScheduleStack(),
          ),
        ],
      ],
    );
  }

  Widget _buildTabletInspector(BuildContext context) {
    final entry = _selectedInspectorEntry;
    if (entry == null) {
      final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 36, color: secondary),
              const SizedBox(height: 12),
              Text('选择一门课程查看详情', style: TextStyle(color: secondary)),
            ],
          ),
        ),
      );
    }
    final isClassSchedule = _scope == AcademicScheduleScope.administrativeClass;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '课程详情',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '关闭详情',
                onPressed:
                    () => setState(() {
                      _selectedInspectorEntry = null;
                      _selectedInspectorSources = null;
                    }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._buildGroupedCourseDetails(
            context,
            entry,

            isClassSchedule: isClassSchedule,
            sources: _selectedInspectorSources ?? [entry],
            closeOverlay: false,
          ),
        ],
      ),
    );
  }

  void _toggleScope() {
    final nextScope =
        _scope == AcademicScheduleScope.personal
            ? AcademicScheduleScope.administrativeClass
            : AcademicScheduleScope.personal;
    unawaited(_changeScope(nextScope));
  }

  Widget _buildAppBarTitle(BuildContext context) {
    final supportsClassSchedule =
        _academicBackend == AcademicAffairsBackend.undergraduate;
    if (!supportsClassSchedule) return const Text('我的课表');

    final colors = Theme.of(context).colorScheme;
    final currentScopeLabel =
        _scope == AcademicScheduleScope.personal ? '个人' : '班级';
    final nextScopeLabel =
        _scope == AcademicScheduleScope.personal ? '班级' : '个人';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('我的课表'),
        const SizedBox(width: 4),
        SizedBox(
          key: _scheduleScopeKey,
          child: Semantics(
            button: true,
            label: '当前为$currentScopeLabel课表，点击切换到$nextScopeLabel课表',
            child: Tooltip(
              message: '切换到$nextScopeLabel课表',
              child: Material(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  key: const ValueKey('academic-schedule-scope-selector'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: _loading || _refreshing ? null : _toggleScope,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentScopeLabel,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.swap_horiz,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialSemesterButton() {
    final label = _semesterDisplayLabel;
    return IconButton(
      key: const ValueKey('academic-schedule-semester-selector'),
      tooltip: '选择学期：${label.inline}',
      onPressed: _loading || _refreshing ? null : _showSemesterPicker,
      icon: _ScheduleTopBarLabel(
        primary: label.primary,
        secondary: label.secondary,
      ),
    );
  }

  Widget _buildMaterialWeekButton() {
    final label = _weekDisplayLabel;
    return IconButton(
      key: const ValueKey('academic-schedule-week-selector'),
      tooltip: '选择周次：${label.semanticLabel}',
      onPressed: _schedule == null ? null : _showWeekPicker,
      icon: _ScheduleTopBarLabel(
        primary: label.primary,
        secondary: label.secondary,
      ),
    );
  }

  _ScheduleTopBarLabelData get _semesterDisplayLabel {
    final schedule = _schedule;
    final source =
        schedule == null
            ? ''
            : schedule.semesterLabel.trim().isNotEmpty
            ? schedule.semesterLabel
            : schedule.semesterId;
    return _compactSemesterLabel(source);
  }

  _ScheduleTopBarLabelData get _weekDisplayLabel {
    if (_selectedHoliday) {
      return const _ScheduleTopBarLabelData(primary: '假期', semanticLabel: '假期');
    }
    final week = _selectedWeek;
    if (week == null) {
      return const _ScheduleTopBarLabelData(primary: '全部', semanticLabel: '全部');
    }
    return _ScheduleTopBarLabelData(
      primary: '$week',
      secondary: '周',
      semanticLabel: '第$week周',
    );
  }

  void _toggleShowNonCurrent() {
    final accountKey = _accountKey;
    if (accountKey == null) return;
    final value = !_showNonCurrent;
    setState(() => _showNonCurrent = value);
    unawaited(
      AcademicScheduleDisplayPreferences.setShowNonCurrent(accountKey, value),
    );
  }

  void _toggleHideWeekend() {
    final accountKey = _accountKey;
    if (accountKey == null) return;
    final value = !_hideWeekend;
    setState(() => _hideWeekend = value);
    unawaited(
      AcademicScheduleDisplayPreferences.setHideWeekend(accountKey, value),
    );
  }

  bool get _supportsWakeUpExport =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Map<int, DateTime> _exportWeekStartDates(AcademicPersonalSchedule schedule) {
    final maxWeek = schedule.maxWeek;
    return {
      for (final item in _calendar?.weeks ?? const <AcademicCalendarWeek>[])
        if (item.week >= 1 && item.week <= maxWeek) item.week: item.startDate,
    };
  }

  String _exportBaseName(AcademicPersonalSchedule schedule) {
    final semester =
        schedule.semesterLabel.trim().isEmpty
            ? '课表'
            : schedule.semesterLabel.trim();
    return 'MyCHU-$semester-全部周';
  }

  Future<void> _runExport(Future<void> Function() action) async {
    if (_exporting || !mounted) return;
    setState(() => _exporting = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showExportMenu() async {
    final schedule = _schedule;
    if (schedule == null || !mounted) return;
    if (schedule.entries.isEmpty) {
      await _showExportMessage('导出失败：本学期没有课程，请检查后重试');
      return;
    }

    final selected = await showAdaptiveActionSheet<String>(
      context,
      title: '导出',

      options: [
        if (_supportsWakeUpExport)
          const AdaptiveActionSheetOption<String>(
            label: 'WakeUp课程表',
            value: 'wakeup',
          ),
        const AdaptiveActionSheetOption<String>(
          label: '日历(.ics)',
          value: 'ics',
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'wakeup') {
      await _exportWakeUp(schedule);
    } else if (selected == 'ics') {
      await _exportIcs(schedule);
    }
  }

  Future<void> _exportIcs(AcademicPersonalSchedule schedule) async {
    if (_exporting) return;
    final weekStartDates = _exportWeekStartDates(schedule);
    late final String content;
    try {
      content = AcademicScheduleExportService.buildIcs(
        schedule: schedule,
        teachingSchedule: teachingScheduleFor(_scheduleMode),
        weekStartDates: weekStartDates,
      );
    } on AcademicScheduleExportDateMappingException catch (error) {
      await _showExportMessage(error.message);
      return;
    }
    if (!mounted) return;
    await _runExport(() async {
      final fileName = '${_exportBaseName(schedule)}.ics';
      try {
        final path = await FileSaveService.saveToDownloads(
          fileName: fileName,
          bytes: utf8.encode(content),
        );
        if (!mounted) return;
        if (path == null) {
          await _showExportMessage('ICS 保存失败');
          return;
        }
        final opened = await FileSaveService.openFile(
          path: path,
          fileName: fileName,
        );
        if (!mounted) return;
        await _showExportMessage(
          opened ? 'ICS 已保存，正在打开日历应用' : 'ICS 已保存，但未找到可导入日历的应用',
        );
      } catch (_) {
        if (mounted) await _showExportMessage('ICS 导出失败，请重试');
      }
    });
  }

  Future<void> _exportWakeUp(AcademicPersonalSchedule schedule) async {
    if (_exporting) return;
    final weekStartDates = _exportWeekStartDates(schedule);
    final firstWeekMonday = weekStartDates[1];
    if (firstWeekMonday == null) {
      await _showExportMessage('第一周日期尚未加载，暂时无法生成 WakeUp 课表。');
      return;
    }
    if (!mounted) return;
    await _runExport(() async {
      final fileName = '${_exportBaseName(schedule)}.wakeup_schedule';
      try {
        final content = AcademicScheduleExportService.buildWakeUpSchedule(
          schedule: schedule,
          teachingSchedule: teachingScheduleFor(_scheduleMode),
          firstWeekMonday: firstWeekMonday,
        );
        final path = await FileSaveService.saveToDownloads(
          fileName: fileName,
          bytes: utf8.encode(content),
        );
        if (!mounted) return;
        if (path == null) {
          await _showExportMessage('WakeUp 课表保存失败');
          return;
        }
        final opened = await FileSaveService.openInWakeUp(
          path: path,
          fileName: fileName,
        );
        if (!mounted) return;
        await _showExportMessage(
          opened ? '完整课表已保存，正在打开 WakeUp' : '完整课表已保存，但未找到可用 WakeUp',
        );
      } catch (_) {
        if (mounted) await _showExportMessage('WakeUp 课表导出失败，请重试');
      }
    });
  }

  Future<void> _showExportMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    return Future<void>.value();
  }

  Future<void> _openCourseEditor([AcademicPersonalScheduleEntry? entry]) async {
    if (_scope != AcademicScheduleScope.personal) return;
    final schedule = _schedule;
    final accountKey = _accountKey;
    if (schedule == null || accountKey == null || accountKey.trim().isEmpty) {
      return;
    }

    final editor = AcademicScheduleEditor(
      initialEntry: entry,
      maxWeek: schedule.maxWeek,

      onSave: (edited) => _saveEditedEntry(accountKey, schedule, entry, edited),
      onDelete:
          entry == null
              ? null
              : () => _deleteEditedEntry(accountKey, schedule, entry),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => editor,
    );
  }

  Future<void> _restoreOriginalSchedule() async {
    if (_scope != AcademicScheduleScope.personal ||
        _accountKey == null ||
        _schedule == null ||
        !mounted) {
      return;
    }

    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '恢复原始课表？',
      message: '本学期的课程修改、新增和删除记录都会清除，远程课表内容会重新显示。',
      confirmLabel: '恢复',
    );
    if (confirmed != true || !mounted) return;
    final accountKey = _accountKey!;
    final semesterId = _schedule!.semesterId;
    final restored = await _store.clearUserLayer(
      accountKey,
      semesterId: semesterId,
    );
    if (!mounted) return;
    if (restored != null && _accountKey == accountKey) {
      setState(() => _schedule = restored);
      _refreshPersonalSurfaces();
    }
    await showAdaptiveMessageDialog(context, message: '已恢复原始课表');
  }

  Future<bool> _saveEditedEntry(
    String accountKey,
    AcademicPersonalSchedule schedule,
    AcademicPersonalScheduleEntry? original,
    AcademicPersonalScheduleEntry edited,
  ) async {
    final hasConflict = academicScheduleEntryConflicts(
      schedule,
      edited,
      excluding: original,
    );
    if (hasConflict && mounted) {
      final confirmed = await showAdaptiveConfirmationDialog(
        context,
        title: '存在时间冲突',
        message: '这门课程与已有课程的星期、节次和周次重叠，仍要保存吗？',
        confirmLabel: '仍然保存',
      );
      if (confirmed != true) return false;
    }
    final refreshed = await _store.saveUserEntry(
      accountKey,
      schedule,
      original: original,
      edited: edited,
    );
    if (!mounted || refreshed == null || _accountKey != accountKey) {
      return false;
    }
    setState(() => _schedule = refreshed);
    _refreshPersonalSurfaces();
    return true;
  }

  Future<bool> _deleteEditedEntry(
    String accountKey,
    AcademicPersonalSchedule schedule,
    AcademicPersonalScheduleEntry original,
  ) async {
    final refreshed = await _store.deleteUserEntry(
      accountKey,
      schedule,
      original,
    );
    if (!mounted || refreshed == null || _accountKey != accountKey) {
      return false;
    }
    setState(() => _schedule = refreshed);
    _refreshPersonalSurfaces();
    return true;
  }

  Future<void> _toggleLiveUpdate() async {
    if (_scope != AcademicScheduleScope.personal || !_supportsLiveUpdate) {
      return;
    }
    final accountKey = _accountKey ?? await _accountKeyLoader();
    if (accountKey == null || accountKey.trim().isEmpty) return;
    if (_liveUpdateWorking) return;
    setState(() => _liveUpdateWorking = true);
    try {
      final enable = !_liveUpdateEnabled;
      if (enable) {
        final permission =
            await hostPermissionService.requestNotificationPermission();
        // Apple ActivityKit is independent of the Android notification gate.
        if (permission.supported && !permission.granted) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('请先在系统设置中开启通知权限')));
          }
          return;
        }
        await LiveUpdatePreferences.setEnabled(
          accountKey,
          academicScheduleLiveUpdateDefinition.id,
          true,
        );
        await LiveUpdateService.refreshDefinition(
          academicScheduleLiveUpdateDefinition.id,
          forceRefresh: true,
        );
        if (!mounted) return;
        setState(() => _liveUpdateEnabled = true);
      } else {
        await LiveUpdatePreferences.setEnabled(
          accountKey,
          academicScheduleLiveUpdateDefinition.id,
          false,
        );
        await LiveUpdateService.cancelForAccount(accountKey);
        if (!mounted) return;
        setState(() => _liveUpdateEnabled = false);
      }
    } finally {
      if (mounted) setState(() => _liveUpdateWorking = false);
    }
  }

  void _returnToCurrentWeek() {
    final pageIndex = _currentPageIndex;
    if (pageIndex == null || !mounted) return;
    _setVisiblePage(pageIndex, jump: true);
  }

  Future<void> _showSemesterPicker() async {
    final semesters = _semesters
        .where((semester) => semester.id.trim().isNotEmpty)
        .toList(growable: false);
    if (semesters.isEmpty) return;
    final selectedId = _schedule?.semesterId.trim() ?? '';

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final semester in semesters)
                  ListTile(
                    title: Text(
                      semester.label.isNotEmpty ? semester.label : semester.id,
                    ),
                    trailing:
                        semester.id == selectedId
                            ? const Icon(Icons.check)
                            : null,
                    onTap: () => Navigator.of(sheetContext).pop(semester.id),
                  ),
              ],
            ),
          ),
    );
    if (selected != null && mounted) {
      await _changeSemester(selected);
    }
  }

  Future<void> _showWeekPicker() async {
    final pageCount = _pageCount;
    final selectedPage = _selectedPageIndex;
    final currentPage = _currentPageIndex;

    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: pageCount,
              itemBuilder: (context, index) {
                final isAllItem = index == 0;
                final isHolidayItem = _isHoliday && index == _holidayPageIndex;
                final title =
                    isAllItem
                        ? '全部'
                        : isHolidayItem
                        ? '假期'
                        : '第$index周';
                return ListTile(
                  title: Text(title),
                  subtitle:
                      index == currentPage
                          ? Text(isHolidayItem ? '当前' : '本周')
                          : null,
                  trailing:
                      index == selectedPage ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(sheetContext).pop(index),
                );
              },
            ),
          ),
    );
    if (selected == null || !mounted) return;
    _applyWeekSelection(selected);
  }

  void _applyWeekSelection(int selected) {
    _setVisiblePage(selected, jump: true);
  }

  Widget _buildContent(BuildContext context) {
    final schedule = _schedule;
    if (schedule == null) {
      if (_loading) return const _ScheduleLoadingState();
      return AcademicErrorState(
        error: _error ?? const AcademicAffairsException('课表暂无数据'),
        onRetry: _refreshSchedule,
      );
    }

    final maxPeriod = math.max(
      11,
      schedule.entries.fold<int>(
        0,
        (current, entry) => math.max(current, entry.endPeriod),
      ),
    );
    final isClassSchedule = _scope == AcademicScheduleScope.administrativeClass;
    final visibleWeekdays =
        _hideWeekend
            ? const <int>[1, 2, 3, 4, 5]
            : const <int>[1, 2, 3, 4, 5, 6, 7];
    final mergeResult =
        isClassSchedule
            ? mergeClassScheduleEntries(schedule.entries)
            : mergeScheduleEntries(schedule.entries);
    final courseColorIndices = _buildCourseColorIndices(mergeResult.entries);
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: AcademicInlineError(
              error: _error!,
              onRetry: _refreshSchedule,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columnWidth = math.max(
                0.0,
                (constraints.maxWidth - _scheduleLeftWidth) /
                    visibleWeekdays.length,
              );
              final pager = PageView.builder(
                key: ValueKey('schedule-pager-$_controllerGeneration'),
                controller: _weekController,
                itemCount: _pageCount,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _ScheduleWeekPage(
                      split: AcademicScheduleWeekSplit(
                        current: mergeResult.entries,
                        faded: const [],
                        hidden: const [],
                      ),
                      showNonCurrent: false,
                      maxPeriod: maxPeriod,
                      columnWidth: columnWidth,
                      visibleWeekdays: visibleWeekdays,
                      highlightToday: false,
                      todayWeekday: _clock().weekday,
                      weekStartDate: null,
                      selectedWeek: null,
                      teachingSchedule: teachingScheduleFor(_scheduleMode),
                      isClassSchedule: isClassSchedule,
                      firstCourseKey:
                          index == _visiblePage ? _firstCourseKey : null,
                      mergeSources: mergeResult.sources,
                      courseColorIndices: courseColorIndices,
                      personalConflictSelections: _personalConflictSelections,
                      onCellTap: _showCellDetails,
                      emptyText: isClassSchedule ? '本学期没有班级课程' : '本学期没有课程',
                    );
                  }
                  if (_isHoliday && index == _holidayPageIndex) {
                    return _ScheduleWeekPage(
                      split: const AcademicScheduleWeekSplit(
                        current: [],
                        faded: [],
                        hidden: [],
                      ),
                      showNonCurrent: false,
                      maxPeriod: maxPeriod,
                      columnWidth: columnWidth,
                      visibleWeekdays: visibleWeekdays,
                      highlightToday: false,
                      todayWeekday: _clock().weekday,
                      weekStartDate: _currentCalendarWeek?.startDate,
                      selectedWeek: null,
                      teachingSchedule: teachingScheduleFor(_scheduleMode),
                      isClassSchedule: isClassSchedule,
                      firstCourseKey:
                          index == _visiblePage ? _firstCourseKey : null,
                      mergeSources: const {},
                      courseColorIndices: courseColorIndices,
                      personalConflictSelections: _personalConflictSelections,
                      onCellTap: _showCellDetails,
                      emptyText: '假期中~',
                    );
                  }
                  final week = index;
                  return _ScheduleWeekPage(
                    split: classifyScheduleEntriesForWeek(
                      mergeResult.entries,
                      week,
                    ),
                    showNonCurrent: _showNonCurrent,
                    maxPeriod: maxPeriod,
                    columnWidth: columnWidth,
                    visibleWeekdays: visibleWeekdays,
                    highlightToday: week == _currentScheduleWeek,
                    todayWeekday: _clock().weekday,
                    weekStartDate: _weekStartDate(week),
                    selectedWeek: week,
                    teachingSchedule: teachingScheduleFor(_scheduleMode),
                    isClassSchedule: isClassSchedule,
                    firstCourseKey:
                        index == _visiblePage ? _firstCourseKey : null,
                    mergeSources: mergeResult.sources,
                    courseColorIndices: courseColorIndices,
                    personalConflictSelections: _personalConflictSelections,
                    onCellTap: _showCellDetails,
                    emptyText: isClassSchedule ? '本周没有班级课程' : '本周没有课程',
                  );
                },
              );
              return pager;
            },
          ),
        ),
      ],
    );
  }

  void _onPageChanged(int index) {
    _setVisiblePage(index);
  }

  List<AcademicPersonalScheduleEntry> _detailSourcesForSelectedWeek(
    AcademicPersonalScheduleEntry entry,
    Iterable<AcademicPersonalScheduleEntry> sources,
  ) {
    final all = _uniqueScheduleSourceEntries(
      sources.isEmpty ? [entry] : sources,
    );
    final week = _selectedWeek;
    if (week == null || _selectedHoliday) return all;
    final current = [
      for (final source in all)
        if (source.isVisibleInWeek(week)) source,
    ];
    // A non-current/faded cell can still be opened for context. Keep its
    // original source list when no record belongs to the selected week.
    return current.isEmpty ? all : current;
  }

  String _detailWeeksText(
    AcademicPersonalScheduleEntry entry,
    Iterable<AcademicPersonalScheduleEntry> sources, {
    required bool isSpecificWeek,
  }) {
    if (!isSpecificWeek) return entry.weeksText;
    final values = _distinctScheduleValues(
      sources.map((source) => source.weeksText),
    );
    return values.isEmpty ? entry.weeksText : values.join('、');
  }

  List<int> _detailPracticeWeeks(
    AcademicPersonalScheduleEntry entry,
    Iterable<AcademicPersonalScheduleEntry> sources, {
    required bool isSpecificWeek,
  }) {
    if (!isSpecificWeek) return entry.practiceWeeks;
    final values = <int>{for (final source in sources) ...source.practiceWeeks};
    if (values.isEmpty) return entry.practiceWeeks;
    return values.toList()..sort();
  }

  Future<void> _showPersonalConflictDetails(
    List<AcademicPersonalScheduleEntry> courses, {
    required bool isNonCurrent,
    required List<AcademicPersonalScheduleEntry> companions,
    required Map<
      AcademicPersonalScheduleEntry,
      List<AcademicPersonalScheduleEntry>
    >
    mergeSources,
  }) async {
    final selectedKey =
        _personalConflictSelections[_scheduleConflictGroupKey(courses)];
    var selectedCourse = courses.firstWhere(
      (course) =>
          selectedKey != null &&
          _scheduleEntrySelectionKey(course) == selectedKey,
      orElse: () => courses.first,
    );
    final uniqueCompanions = _uniqueScheduleSourceEntries(companions);

    Widget buildContent(BuildContext sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final selectedSources =
            mergeSources[selectedCourse] ?? [selectedCourse];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNonCurrent)
                  Text(
                    '非本周课程',
                    style: Theme.of(sheetContext).textTheme.labelMedium,
                  ),
                ..._buildGroupedCourseDetails(
                  sheetContext,
                  selectedCourse,

                  isClassSchedule: false,
                  sources: selectedSources,
                ),
                const Divider(height: 24),
                Text(
                  '时间冲突课程',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                RadioGroup<AcademicPersonalScheduleEntry>(
                  groupValue: selectedCourse,
                  onChanged: (value) {
                    if (value == null) return;
                    _rememberPersonalConflictSelection(courses, value);
                    setSheetState(() => selectedCourse = value);
                  },
                  child: Column(
                    children: [
                      for (final course in courses)
                        RadioListTile<AcademicPersonalScheduleEntry>(
                          key: ValueKey(
                            'academic-schedule-conflict-option-${_scheduleEntrySelectionKey(course)}',
                          ),
                          value: course,
                          selected: identical(course, selectedCourse),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(course.displayName),
                          subtitle: Text(_entryTimeLabel(course)),
                        ),
                    ],
                  ),
                ),
                if (uniqueCompanions.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    '非本周课程',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final companion in uniqueCompanions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            companion.displayName,
                            style: Theme.of(sheetContext).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          _DetailLine(label: '教师', value: companion.teacher),
                          _DetailLine(label: '地点', value: companion.location),
                          _DetailLine(
                            label: '时间',
                            value: _entryTimeLabel(companion),
                          ),
                          _DetailLine(label: '周次', value: companion.weeksText),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );

    {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: buildContent,
      );
    }
  }

  void _rememberPersonalConflictSelection(
    List<AcademicPersonalScheduleEntry> courses,
    AcademicPersonalScheduleEntry selected,
  ) {
    final conflictKey = _scheduleConflictGroupKey(courses);
    final courseKey = _scheduleEntrySelectionKey(selected);
    if (!mounted || conflictKey.isEmpty || courseKey.isEmpty) return;
    if (_personalConflictSelections[conflictKey] == courseKey) return;
    setState(() => _personalConflictSelections[conflictKey] = courseKey);
  }

  Future<void> _showCellDetails(
    List<AcademicPersonalScheduleEntry> entries, {
    required bool isNonCurrent,
    required List<AcademicPersonalScheduleEntry> companions,
    required Map<
      AcademicPersonalScheduleEntry,
      List<AcademicPersonalScheduleEntry>
    >
    mergeSources,
  }) async {
    final courses = _uniqueScheduleSourceEntries(entries);
    if (courses.isEmpty) return;
    final environment = PlatformEnvironment.fromContext(context);
    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded &&
        courses.length == 1) {
      final selected = courses.single;
      setState(() {
        _selectedInspectorEntry = selected;
        _selectedInspectorSources = mergeSources[selected] ?? [selected];
      });
      return;
    }
    if (courses.length == 1) {
      final entry = courses.single;
      await _showEntryDetails(
        entry,
        isNonCurrent: isNonCurrent,
        companions: companions,
        sources: mergeSources[entry] ?? [entry],
      );
      return;
    }

    final isClassSchedule = _scope == AcademicScheduleScope.administrativeClass;
    if (!isClassSchedule) {
      await _showPersonalConflictDetails(
        courses,
        isNonCurrent: isNonCurrent,
        companions: companions,
        mergeSources: mergeSources,
      );
      return;
    }

    Widget buildContent(BuildContext sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNonCurrent)
              Text(
                '非本周课程',
                style: Theme.of(sheetContext).textTheme.labelMedium,
              ),
            Text(
              '共 ${courses.length} 门课程',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < courses.length; index++) ...[
              if (index > 0) const Divider(height: 24),
              ..._buildGroupedCourseDetails(
                sheetContext,
                courses[index],

                isClassSchedule: isClassSchedule,
                sources: mergeSources[courses[index]] ?? [courses[index]],
              ),
            ],
            if (companions.isNotEmpty) ...[
              const Divider(height: 24),
              Text('非本周课程', style: Theme.of(sheetContext).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final companion in _uniqueScheduleSourceEntries(companions))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companion.displayName,
                        style: Theme.of(sheetContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      _DetailLine(label: '教师', value: companion.teacher),
                      _DetailLine(label: '地点', value: companion.location),
                      _DetailLine(
                        label: '时间',
                        value: _entryTimeLabel(companion),
                      ),
                      _DetailLine(label: '周次', value: companion.weeksText),
                      if (companion.courseCode.isNotEmpty)
                        _DetailLine(label: '课程代码', value: companion.courseCode),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: buildContent,
      );
    }
  }

  List<Widget> _buildGroupedCourseDetails(
    BuildContext sheetContext,
    AcademicPersonalScheduleEntry entry, {

    required bool isClassSchedule,
    required List<AcademicPersonalScheduleEntry> sources,
    bool closeOverlay = true,
  }) {
    final detailSources = _uniqueScheduleSourceEntries(
      _detailSourcesForSelectedWeek(entry, sources),
    );
    final detailTeachers = _distinctScheduleValues(
      detailSources.map((source) => source.teacher),
    );
    final detailLocations = _distinctScheduleValues(
      detailSources.map((source) => cleanScheduleLocation(source.location)),
    );
    final isSpecificWeek = _selectedWeek != null && !_selectedHoliday;
    final mapLocation =
        isClassSchedule
            ? detailLocations.firstOrNull ??
                cleanScheduleLocation(entry.location)
            : isSpecificWeek
            ? detailLocations.join(' / ')
            : cleanScheduleLocation(entry.location);
    final detailWeeks = _detailWeeksText(
      entry,
      detailSources,
      isSpecificWeek: isSpecificWeek,
    );
    final detailPracticeWeeks = _detailPracticeWeeks(
      entry,
      detailSources,
      isSpecificWeek: isSpecificWeek,
    );
    final courseName = entry.displayName;
    return [
      Text(courseName, style: Theme.of(sheetContext).textTheme.titleMedium),
      const SizedBox(height: 6),
      _DetailLine(
        label: '教师',
        value: isClassSchedule ? detailTeachers.join('、') : entry.teacher,
      ),
      _DetailLine(
        label: '地点',
        value:
            isClassSchedule
                ? detailLocations.join('、')
                : isSpecificWeek
                ? detailLocations.join(' / ')
                : entry.location,
      ),
      _DetailLine(label: '时间', value: _entryTimeLabel(entry)),
      _DetailLine(label: '周次', value: detailWeeks),
      if (detailPracticeWeeks.isNotEmpty)
        _DetailLine(label: '实践周', value: detailPracticeWeeks.join('、')),
      if (entry.courseCode.isNotEmpty)
        _DetailLine(label: '课程代码', value: entry.courseCode),
      if (mapLocation.isNotEmpty || !isClassSchedule)
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isClassSchedule)
                OutlinedButton.icon(
                  onPressed: () {
                    if (closeOverlay) Navigator.of(sheetContext).pop();
                    unawaited(_openCourseEditor(detailSources.first));
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑课程'),
                ),
              if (mapLocation.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      campusMapCapability.openRequest(
                        context,
                        UnifiedPlaceRequest(rawText: mapLocation.trim()),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('在地图中查看'),
                ),
            ],
          ),
        ),
      if (isClassSchedule && detailSources.length > 1) ...[
        const SizedBox(height: 8),
        Text('授课安排', style: Theme.of(sheetContext).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final source in detailSources)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailLine(label: '教师', value: source.teacher),
                _DetailLine(label: '周次', value: source.weeksText),
                _DetailLine(label: '地点', value: source.location),
              ],
            ),
          ),
      ],
    ];
  }

  Future<void> _showEntryDetails(
    AcademicPersonalScheduleEntry entry, {
    required bool isNonCurrent,
    required List<AcademicPersonalScheduleEntry> companions,
    required List<AcademicPersonalScheduleEntry> sources,
  }) async {
    final isClassSchedule = _scope == AcademicScheduleScope.administrativeClass;
    final detailSources = _uniqueScheduleSourceEntries(
      _detailSourcesForSelectedWeek(entry, sources),
    );
    final isSpecificWeek = _selectedWeek != null && !_selectedHoliday;
    final detailTeachers = _distinctScheduleValues(
      detailSources.map((source) => source.teacher),
    );
    final detailLocations = _distinctScheduleValues(
      detailSources.map((source) => cleanScheduleLocation(source.location)),
    );
    final mapLocation =
        isClassSchedule
            ? detailLocations.firstOrNull ??
                cleanScheduleLocation(entry.location)
            : isSpecificWeek
            ? detailLocations.join(' / ')
            : cleanScheduleLocation(entry.location);
    final detailWeeks = _detailWeeksText(
      entry,
      detailSources,
      isSpecificWeek: isSpecificWeek,
    );
    final detailPracticeWeeks = _detailPracticeWeeks(
      entry,
      detailSources,
      isSpecificWeek: isSpecificWeek,
    );

    Widget buildContent(BuildContext sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNonCurrent)
              Text(
                '非本周课程',
                style: Theme.of(sheetContext).textTheme.labelMedium,
              ),
            Text(
              entry.displayName,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _DetailLine(
              label: '教师',
              value: isClassSchedule ? detailTeachers.join('、') : entry.teacher,
            ),
            _DetailLine(
              label: '地点',
              value:
                  isClassSchedule
                      ? detailLocations.join('、')
                      : isSpecificWeek
                      ? detailLocations.join(' / ')
                      : entry.location,
            ),
            _DetailLine(label: '时间', value: _entryTimeLabel(entry)),
            _DetailLine(label: '周次', value: detailWeeks),
            if (detailPracticeWeeks.isNotEmpty)
              _DetailLine(label: '实践周', value: detailPracticeWeeks.join('、')),
            if (entry.courseCode.isNotEmpty)
              _DetailLine(label: '课程代码', value: entry.courseCode),
            if (mapLocation.isNotEmpty || !isClassSchedule)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!isClassSchedule)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(_openCourseEditor(detailSources.first));
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑课程'),
                      ),
                    if (mapLocation.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(
                            campusMapCapability.openRequest(
                              context,
                              UnifiedPlaceRequest(rawText: mapLocation.trim()),
                            ),
                          );
                        },
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('在地图中查看'),
                      ),
                  ],
                ),
              ),
            if (detailSources.length > 1) ...[
              const Divider(height: 24),
              Text(
                isClassSchedule ? '授课安排' : '课程分段',
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final source in detailSources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isClassSchedule)
                        _DetailLine(label: '教师', value: source.teacher),
                      _DetailLine(label: '周次', value: source.weeksText),
                      _DetailLine(label: '地点', value: source.location),
                    ],
                  ),
                ),
            ],
            if (companions.isNotEmpty) ...[
              const Divider(height: 24),
              Text('非本周课程', style: Theme.of(sheetContext).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final companion in companions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companion.displayName,
                        style: Theme.of(sheetContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      _DetailLine(label: '教师', value: companion.teacher),
                      _DetailLine(label: '地点', value: companion.location),
                      _DetailLine(
                        label: '时间',
                        value: _entryTimeLabel(companion),
                      ),
                      _DetailLine(label: '周次', value: companion.weeksText),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: buildContent,
      );
    }
  }

  String _entryTimeLabel(AcademicPersonalScheduleEntry entry) {
    final time = teachingScheduleFor(
      _scheduleMode,
    ).range(entry.startPeriod, entry.endPeriod);
    return [
      '星期${_weekdayLabel(entry.weekday)}',
      '第${entry.startPeriod}-${entry.endPeriod}节',
      if (time != null) time.rangeText,
    ].join(' · ');
  }
}

class _ScheduleTopBarLabelData {
  final String primary;
  final String? secondary;
  final String semanticLabel;

  const _ScheduleTopBarLabelData({
    required this.primary,
    this.secondary,
    String? semanticLabel,
  }) : semanticLabel = semanticLabel ?? primary;

  String get inline {
    final secondary = this.secondary;
    return secondary == null ? primary : '$primary $secondary';
  }
}

_ScheduleTopBarLabelData _compactSemesterLabel(String value) {
  final source = value.trim();
  if (source.isEmpty) {
    return const _ScheduleTopBarLabelData(
      primary: '选择',
      secondary: '学期',
      semanticLabel: '选择学期',
    );
  }

  final normalized = source
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-');
  final yearRange = RegExp(
    r'(?<!\d)(\d{4})\s*-\s*(\d{4})(?!\d)',
  ).firstMatch(normalized);
  final singleYear = RegExp(r'(?<!\d)(\d{4})(?!\d)').firstMatch(normalized);

  String? season;
  var usesEndYear = false;
  if (RegExp(
    r'短(?:学期)?|夏(?:季)?学期|(?:第\s*)?(?:3|三)\s*学期|学期\s*(?:3|三)',
  ).hasMatch(normalized)) {
    season = '短';
    usesEndYear = true;
  } else if (RegExp(
    r'春(?:季)?学期|(?:第\s*)?(?:2|二|两)\s*学期|学期\s*(?:2|二|两)',
  ).hasMatch(normalized)) {
    season = '春';
    usesEndYear = true;
  } else if (RegExp(
    r'秋(?:季)?学期|(?:第\s*)?(?:1|一)\s*学期|学期\s*(?:1|一)',
  ).hasMatch(normalized)) {
    season = '秋';
  }

  if (season != null) {
    final year =
        yearRange == null
            ? singleYear?.group(1)
            : yearRange.group(usesEndYear ? 2 : 1);
    return _ScheduleTopBarLabelData(
      primary: year ?? season,
      secondary: year == null ? null : season,
      semanticLabel: year == null ? season : '$year $season',
    );
  }

  final fallback =
      source
          .replaceAll(RegExp(r'\s*学年\s*'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  return _ScheduleTopBarLabelData(
    primary: fallback.isEmpty ? source : fallback,
  );
}

class _ScheduleTopBarLabel extends StatelessWidget {
  final String primary;
  final String? secondary;

  const _ScheduleTopBarLabel({required this.primary, this.secondary});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    final secondary = this.secondary;
    final style = TextStyle(
      color: color,
      fontSize: 13,
      height: 1.05,
      fontWeight: FontWeight.w500,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(primary, maxLines: 1, style: style),
          if (secondary != null)
            Text(secondary, maxLines: 1, style: style.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

typedef _ScheduleCellTapCallback =
    void Function(
      List<AcademicPersonalScheduleEntry> entries, {
      required bool isNonCurrent,
      required List<AcademicPersonalScheduleEntry> companions,
      required Map<
        AcademicPersonalScheduleEntry,
        List<AcademicPersonalScheduleEntry>
      >
      mergeSources,
    });

/// One rendered timetable view: a fixed weekday/date header on top of a
/// vertically scrollable period grid. Horizontal paging is owned by the
/// enclosing PageView, so this grid always fits the width.
class _ScheduleWeekPage extends StatelessWidget {
  static const _leftWidth = _scheduleLeftWidth;
  static const _periodHeight = 68.0;
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  final AcademicScheduleWeekSplit split;
  final bool showNonCurrent;
  final int maxPeriod;
  final bool highlightToday;
  final int todayWeekday;
  final DateTime? weekStartDate;
  final int? selectedWeek;
  final TeachingSchedule teachingSchedule;
  final double columnWidth;
  final List<int> visibleWeekdays;
  final bool isClassSchedule;
  final GlobalKey? firstCourseKey;
  final Map<AcademicPersonalScheduleEntry, List<AcademicPersonalScheduleEntry>>
  mergeSources;
  final Map<String, int> courseColorIndices;
  final Map<String, String> personalConflictSelections;
  final _ScheduleCellTapCallback onCellTap;
  final String emptyText;

  const _ScheduleWeekPage({
    required this.split,
    required this.showNonCurrent,
    required this.maxPeriod,
    required this.highlightToday,
    required this.todayWeekday,
    required this.weekStartDate,
    required this.selectedWeek,
    required this.teachingSchedule,
    required this.columnWidth,
    required this.visibleWeekdays,
    required this.isClassSchedule,
    required this.firstCourseKey,
    required this.mergeSources,
    required this.courseColorIndices,
    required this.personalConflictSelections,
    required this.onCellTap,
    this.emptyText = '本周没有课程',
  });

  @override
  Widget build(BuildContext context) {
    final visible = <AcademicPersonalScheduleEntry>[
      ...split.current,
      if (showNonCurrent) ...split.faded,
    ];
    final groups = [
      for (final group in groupScheduleEntriesByOverlap(visible))
        if (visibleWeekdays.contains(group.weekday)) group,
    ];
    final fadedEntries =
        showNonCurrent
            ? split.faded.toSet()
            : const <AcademicPersonalScheduleEntry>{};
    final height = _periodHeight * maxPeriod;
    final colors = Theme.of(context).colorScheme;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final highlightColor = colors.primary.withValues(
      alpha: isDarkTheme ? 0.18 : 0.07,
    );
    final weekStartDate = this.weekStartDate;

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: _leftWidth,
                child: Center(
                  child:
                      weekStartDate != null
                          ? Text(
                            '${weekStartDate.month}月',
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.2,
                              color: colors.onSurfaceVariant,
                            ),
                          )
                          : null,
                ),
              ),
              for (final day in visibleWeekdays)
                SizedBox(
                  width: columnWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          highlightToday && day == todayWeekday
                              ? highlightColor
                              : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '周${_weekdays[day - 1]}',
                            style: const TextStyle(fontSize: 11, height: 1.2),
                          ),
                          if (weekStartDate != null)
                            Text(
                              () {
                                final date = weekStartDate.add(
                                  Duration(days: day - 1),
                                );
                                return '${date.month}/${date.day}';
                              }(),
                              style: TextStyle(
                                fontSize: 9,
                                height: 1.2,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: SizedBox(
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var period = 0; period < maxPeriod; period++)
                    Positioned(
                      left: 0,
                      top: period * _periodHeight,
                      width: _leftWidth,
                      height: _periodHeight,
                      child: _PeriodLabel(
                        period: period + 1,
                        teachingSchedule: teachingSchedule,
                      ),
                    ),
                  for (
                    var groupIndex = 0;
                    groupIndex < groups.length;
                    groupIndex++
                  )
                    _buildCoursePositioned(
                      groups[groupIndex],
                      groupIndex,
                      visibleWeekdays,
                      columnWidth,
                      selectedWeek,
                      fadedEntries,
                    ),
                  if (groups.isEmpty)
                    Positioned.fill(
                      child: Center(
                        child: Text(
                          emptyText,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoursePositioned(
    AcademicScheduleCellGroup group,
    int groupIndex,
    List<int> visibleWeekdays,
    double columnWidth,
    int? selectedWeek,
    Set<AcademicPersonalScheduleEntry> fadedEntries,
  ) {
    final courseBlock = _CourseBlock(
      group: group,
      blockHeight: math.max(
        12.0,
        (group.endPeriod - group.startPeriod + 1) * _periodHeight - 4,
      ),
      mergeSources: mergeSources,
      selectedWeek: selectedWeek,
      isClassSchedule: isClassSchedule,
      courseColorIndices: courseColorIndices,
      personalConflictSelections: personalConflictSelections,
      faded: group.entries.every(fadedEntries.contains),
      onTap: () => _onBlockTap(group, fadedEntries),
    );
    final child =
        firstCourseKey != null && groupIndex == 0
            ? KeyedSubtree(key: firstCourseKey, child: courseBlock)
            : courseBlock;
    return Positioned(
      left:
          _leftWidth + visibleWeekdays.indexOf(group.weekday) * columnWidth + 2,
      top: (group.startPeriod - 1) * _periodHeight + 2,
      width: math.max(12.0, columnWidth - 4),
      height: math.max(
        12.0,
        (group.endPeriod - group.startPeriod + 1) * _periodHeight - 4,
      ),
      child: child,
    );
  }

  void _onBlockTap(
    AcademicScheduleCellGroup group,
    Set<AcademicPersonalScheduleEntry> fadedEntries,
  ) {
    final isFaded = group.entries.every(fadedEntries.contains);
    onCellTap(
      group.entries,
      isNonCurrent: isFaded,
      companions:
          isFaded
              ? const <AcademicPersonalScheduleEntry>[]
              : [
                for (final other in split.hidden)
                  if (group.overlaps(other)) other,
              ],
      mergeSources: mergeSources,
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  final int period;
  final TeachingSchedule teachingSchedule;

  const _PeriodLabel({required this.period, required this.teachingSchedule});

  @override
  Widget build(BuildContext context) {
    final time = teachingSchedule.period(period);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$period', style: const TextStyle(fontSize: 12, height: 1.2)),
          if (time != null) ...[
            Text(
              time.startText,
              style: TextStyle(fontSize: 9, height: 1.2, color: secondary),
            ),
            Text(
              time.endText,
              style: TextStyle(fontSize: 9, height: 1.2, color: secondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  final AcademicScheduleCellGroup group;
  final double blockHeight;
  final Map<AcademicPersonalScheduleEntry, List<AcademicPersonalScheduleEntry>>
  mergeSources;
  final int? selectedWeek;
  final bool isClassSchedule;
  final Map<String, int> courseColorIndices;
  final Map<String, String> personalConflictSelections;
  final bool faded;
  final VoidCallback onTap;

  const _CourseBlock({
    required this.group,
    required this.blockHeight,
    required this.mergeSources,
    required this.selectedWeek,
    required this.isClassSchedule,
    required this.courseColorIndices,
    required this.personalConflictSelections,
    required this.faded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstEntry = group.entries.first;
    final conflictKey =
        !isClassSchedule && group.entries.length > 1
            ? _scheduleConflictGroupKey(group.entries)
            : null;
    final selectedKey =
        conflictKey == null ? null : personalConflictSelections[conflictKey];
    final entry = group.entries.firstWhere(
      (candidate) =>
          selectedKey != null &&
          _scheduleEntrySelectionKey(candidate) == selectedKey,
      orElse: () => firstEntry,
    );
    final colorIndex =
        courseColorIndices[_scheduleCourseColorKey(entry)] ??
        stableCourseColorIndex(
          _scheduleCourseColorKey(entry),
          colorCount: _coursePalettes.length,
        );
    final palette = _coursePaletteForIndex(colorIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? palette.darkBackground : palette.lightBackground;
    final cardBackground =
        faded ? Color.lerp(background, Colors.white, 0.5)! : background;
    final textColor =
        faded ? Colors.white.withValues(alpha: 0.5) : Colors.white;
    final isMultiple = group.entries.length > 1;
    final allSources =
        mergeSources[entry] ?? <AcademicPersonalScheduleEntry>[entry];
    final sourceEntries =
        selectedWeek == null
            ? allSources
            : allSources
                .where((source) => source.isVisibleInWeek(selectedWeek!))
                .toList(growable: false);
    final location = cleanScheduleLocation(
      sourceEntries.firstOrNull?.location ?? entry.location,
    );
    final courseName = entry.displayName;
    final teachers = _distinctScheduleValues(
      sourceEntries.map((source) => source.teacher),
    );
    final locations = _distinctScheduleValues(
      sourceEntries.map((source) => cleanScheduleLocation(source.location)),
    );
    final displayLocation =
        isClassSchedule
            ? locations.length > 1
                ? '${locations.length}个地点'
                : locations.firstOrNull ?? ''
            : location;
    final displayTeacher =
        isClassSchedule
            ? teachers.length > 1
                ? '${teachers.length}位教师'
                : teachers.firstOrNull ?? ''
            : entry.teacher;
    final title = courseName;
    final locationText = displayLocation;
    final statusText =
        isMultiple
            ? '${group.entries.length}门冲突'
            : faded
            ? '非本周'
            : '';
    final lineBudget = _CourseBlockLineBudget.calculate(
      blockHeight: blockHeight,
      periodSpan: group.endPeriod - group.startPeriod + 1,
      textScaler: MediaQuery.textScalerOf(context),
      hasStatus: statusText.isNotEmpty,
      hasLocation: locationText.isNotEmpty,
      hasTeacher: displayTeacher.isNotEmpty,
    );
    final isCompactRoomCode = RegExp(
      r'^[A-Za-z]{2}\d{4}$',
    ).hasMatch(locationText);
    final locationLineCount = isCompactRoomCode ? 1 : lineBudget.locationLines;
    return Stack(
      children: [
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                color: cardBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: onTap,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(1, 2, 1, 3),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final locationLineHeight =
                                MediaQuery.textScalerOf(context).scale(9) * 1.1;
                            final roomText = Text(
                              locationText,
                              maxLines:
                                  locationLineCount > 0 ? locationLineCount : 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 9,
                                height: 1.1,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                            final locationHeight =
                                locationLineCount == 0
                                    ? 0.0
                                    : math
                                        .min(
                                          constraints.maxHeight,
                                          locationLineHeight *
                                              locationLineCount,
                                        )
                                        .toDouble();
                            final locationGap =
                                locationLineCount == 0
                                    ? 0.0
                                    : math
                                        .min(
                                          2.0,
                                          math.max(
                                            0.0,
                                            constraints.maxHeight -
                                                locationHeight,
                                          ),
                                        )
                                        .toDouble();
                            final statusHeight =
                                statusText.isEmpty
                                    ? 0.0
                                    : math
                                        .min(
                                          constraints.maxHeight,
                                          MediaQuery.textScalerOf(
                                                context,
                                              ).scale(9) *
                                              1.1,
                                        )
                                        .toDouble();
                            final statusGap =
                                statusText.isEmpty
                                    ? 0.0
                                    : math
                                        .min(
                                          2.0,
                                          math.max(
                                            0.0,
                                            constraints.maxHeight -
                                                statusHeight,
                                          ),
                                        )
                                        .toDouble();
                            final middleAvailableHeight = math.max(
                              0.0,
                              constraints.maxHeight -
                                  statusHeight -
                                  statusGap -
                                  locationHeight -
                                  locationGap,
                            );
                            final middleContentHeight =
                                math
                                    .min(
                                      middleAvailableHeight,
                                      constraints.maxHeight * 0.62,
                                    )
                                    .toDouble();
                            final middleContentTop =
                                statusHeight +
                                statusGap +
                                (middleAvailableHeight - middleContentHeight) /
                                    2;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                if (statusText.isNotEmpty)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    height: statusHeight,
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          statusText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 9,
                                            height: 1.1,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: middleContentTop,
                                  height: middleContentHeight,
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: SizedBox(
                                        width: constraints.maxWidth,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: lineBudget.titleLines,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 12,
                                                height: 1.15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (lineBudget.teacherLines >
                                                0) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                displayTeacher,
                                                maxLines:
                                                    lineBudget.teacherLines,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontSize: 10,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (locationLineCount > 0)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    height: locationHeight,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.bottomCenter,
                                        child:
                                            isCompactRoomCode
                                                ? roomText
                                                : SizedBox(
                                                  width: constraints.maxWidth,
                                                  child: roomText,
                                                ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseBlockLineBudget {
  final int titleLines;
  final int locationLines;
  final int teacherLines;

  const _CourseBlockLineBudget({
    required this.titleLines,
    required this.locationLines,
    required this.teacherLines,
  });

  static _CourseBlockLineBudget calculate({
    required double blockHeight,
    required int periodSpan,
    required TextScaler textScaler,
    required bool hasStatus,
    required bool hasLocation,
    required bool hasTeacher,
  }) {
    final span = math.max(1, periodSpan).toInt();
    var titleLines = math.min(6, span * 2);
    var locationLines =
        hasLocation && span >= 2
            ? 2
            : hasLocation
            ? 1
            : 0;
    var teacherLines =
        hasTeacher && span >= 2
            ? 2
            : hasTeacher
            ? 1
            : 0;
    final availableHeight = math.max(0.0, blockHeight - 7);

    while (_estimatedHeight(
              textScaler: textScaler,
              hasStatus: hasStatus,
              titleLines: titleLines,
              locationLines: locationLines,
              teacherLines: teacherLines,
            ) >
            availableHeight &&
        teacherLines > 0) {
      teacherLines--;
    }
    while (_estimatedHeight(
              textScaler: textScaler,
              hasStatus: hasStatus,
              titleLines: titleLines,
              locationLines: locationLines,
              teacherLines: teacherLines,
            ) >
            availableHeight &&
        titleLines > 1) {
      titleLines--;
    }
    while (_estimatedHeight(
              textScaler: textScaler,
              hasStatus: hasStatus,
              titleLines: titleLines,
              locationLines: locationLines,
              teacherLines: teacherLines,
            ) >
            availableHeight &&
        locationLines > 1) {
      locationLines--;
    }

    return _CourseBlockLineBudget(
      titleLines: titleLines,
      locationLines: locationLines,
      teacherLines: teacherLines,
    );
  }

  static double _estimatedHeight({
    required TextScaler textScaler,
    required bool hasStatus,
    required int titleLines,
    required int locationLines,
    required int teacherLines,
  }) {
    final lineHeights = <double>[
      if (hasStatus) textScaler.scale(9) * 1.1,
      textScaler.scale(12) * 1.15 * titleLines,
      if (locationLines > 0) textScaler.scale(11) * 1.1 * locationLines,
      if (teacherLines > 0) textScaler.scale(10) * 1.1 * teacherLines,
    ];
    if (lineHeights.isEmpty) return 0;
    return lineHeights.fold<double>(0, (sum, value) => sum + value) +
        (lineHeights.length - 1) * 2;
  }
}

class _CoursePalette {
  final Color lightBackground;
  final Color darkBackground;

  const _CoursePalette({
    required this.lightBackground,
    required this.darkBackground,
  });
}

const _coursePalettes = <_CoursePalette>[
  _CoursePalette(
    lightBackground: Color(0xff2196f3), // Material Blue 500
    darkBackground: Color(0xff1976d2), // Material Blue 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff009688), // Material Teal 500
    darkBackground: Color(0xff00796b), // Material Teal 700
  ),
  _CoursePalette(
    lightBackground: Color(0xffff5722), // Material Deep Orange 500
    darkBackground: Color(0xffd84315), // Material Deep Orange 800
  ),
  _CoursePalette(
    lightBackground: Color(0xff9c27b0), // Material Purple 500
    darkBackground: Color(0xff7b1fa2), // Material Purple 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff4caf50), // Material Green 500
    darkBackground: Color(0xff388e3c), // Material Green 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff3f51b5), // Material Indigo 500
    darkBackground: Color(0xff303f9f), // Material Indigo 700
  ),
  _CoursePalette(
    lightBackground: Color(0xffe91e63), // Material Pink 500
    darkBackground: Color(0xffc2185b), // Material Pink 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff00acc1), // Material Cyan 600
    darkBackground: Color(0xff0097a7), // Material Cyan 700
  ),
  _CoursePalette(
    lightBackground: Color(0xfff44336), // Material Red 500
    darkBackground: Color(0xffd32f2f), // Material Red 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff7cb342), // Material Light Green 600
    darkBackground: Color(0xff558b2f), // Material Light Green 800
  ),
  _CoursePalette(
    lightBackground: Color(0xff039be5), // Material Light Blue 600
    darkBackground: Color(0xff0277bd), // Material Light Blue 800
  ),
  _CoursePalette(
    lightBackground: Color(0xff673ab7), // Material Deep Purple 500
    darkBackground: Color(0xff512da8), // Material Deep Purple 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff607d8b), // Material Blue Grey 500
    darkBackground: Color(0xff546e7a), // Material Blue Grey 600
  ),
  _CoursePalette(
    lightBackground: Color(0xff795548), // Material Brown 500
    darkBackground: Color(0xff5d4037), // Material Brown 700
  ),
  _CoursePalette(
    lightBackground: Color(0xff757575), // Material Grey 600
    darkBackground: Color(0xff616161), // Material Grey 700
  ),
];

_CoursePalette _coursePaletteForIndex(int index) {
  return _coursePalettes[index % _coursePalettes.length];
}

String _scheduleCourseColorKey(AcademicPersonalScheduleEntry entry) {
  final code = entry.courseCode.trim();
  if (code.isNotEmpty) return code;
  final name = entry.courseName.trim();
  if (name.isNotEmpty) return name;
  return entry.courseSequence.trim();
}

String _scheduleEntrySelectionKey(AcademicPersonalScheduleEntry entry) =>
    academicScheduleEntryKey(entry);

String _scheduleConflictGroupKey(
  Iterable<AcademicPersonalScheduleEntry> entries,
) {
  final values = entries.toList(growable: false);
  if (values.isEmpty) return '';
  final courseKeys = values.map(_scheduleEntrySelectionKey).toList()..sort();
  final startPeriod = values.map((entry) => entry.startPeriod).reduce(math.min);
  final endPeriod = values.map((entry) => entry.endPeriod).reduce(math.max);
  return '${values.first.weekday}|$startPeriod|$endPeriod|${courseKeys.join('|')}';
}

Map<String, int> _buildCourseColorIndices(
  Iterable<AcademicPersonalScheduleEntry> entries,
) {
  final courseKeys = <String>{};
  for (final entry in entries) {
    final key = _scheduleCourseColorKey(entry);
    if (key.isNotEmpty) courseKeys.add(key);
  }
  final sortedKeys = courseKeys.toList()..sort();
  final usedIndices = <int>{};
  final colorIndices = <String, int>{};
  for (final key in sortedKeys) {
    final preferredIndex = stableCourseColorIndex(
      key,
      colorCount: _coursePalettes.length,
    );
    var colorIndex = preferredIndex;
    if (usedIndices.length < _coursePalettes.length) {
      for (var offset = 0; offset < _coursePalettes.length; offset++) {
        final candidate = (preferredIndex + offset) % _coursePalettes.length;
        if (!usedIndices.contains(candidate)) {
          colorIndex = candidate;
          break;
        }
      }
      usedIndices.add(colorIndex);
    }
    colorIndices[key] = colorIndex;
  }
  return colorIndices;
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label：$value', style: null),
    );
  }
}

class _ScheduleLoadingState extends StatelessWidget {
  final String label;

  const _ScheduleLoadingState({this.label = '正在加载课表…'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

class _ScheduleLoadingOverlay extends StatelessWidget {
  final String label;

  const _ScheduleLoadingOverlay({required this.label});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
      child: _ScheduleLoadingState(label: label),
    );
  }
}

List<String> _distinctScheduleValues(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    result.add(normalized);
  }
  return result;
}

List<AcademicPersonalScheduleEntry> _uniqueScheduleSourceEntries(
  Iterable<AcademicPersonalScheduleEntry> entries,
) {
  final result = <AcademicPersonalScheduleEntry>[];
  final seen = <String>{};
  for (final entry in entries) {
    final key = [
      entry.courseSequence.trim(),
      entry.courseCode.trim(),
      entry.courseName.trim(),
      entry.teacher.trim(),
      cleanScheduleLocation(entry.location).trim(),
      entry.weekday,
      entry.startPeriod,
      entry.endPeriod,
      _normalizedScheduleWeekList(entry.weeks),
      _normalizedScheduleWeekList(entry.practiceWeeks),
    ].join('\u0000');
    if (seen.add(key)) result.add(entry);
  }
  return result;
}

String _normalizedScheduleWeekList(Iterable<int> weeks) {
  final normalized = weeks.toSet().toList()..sort();
  return normalized.join(',');
}

String _weekdayLabel(int weekday) {
  const labels = ['一', '二', '三', '四', '五', '六', '日'];
  return weekday >= 1 && weekday <= labels.length
      ? labels[weekday - 1]
      : '$weekday';
}
