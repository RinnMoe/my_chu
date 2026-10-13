import 'package:flutter/foundation.dart';

import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../services/auth_service.dart';
import '../../services/privacy_agreement_service.dart';
import '../../services/teaching_schedule_service.dart';
import '../../services/campus_settings_service.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import '../east8_time.dart';
import 'academic_schedule_store.dart';
import 'academic_schedule_utils.dart';

enum AcademicSchedulePreviewSource { account, demo }

typedef AcademicSchedulePreviewAccountLoader = Future<String?> Function();
typedef AcademicSchedulePreviewPrivacyLoader = Future<bool> Function();
typedef AcademicSchedulePreviewCalendarLoader =
    Future<AcademicCalendarData?> Function(String accountKey, String semester);

/// In-memory state for the developer timetable preview.
///
/// It deliberately exposes only cache reads. Edits are held in this controller
/// and never reach the production schedule store or its reminder pipeline.
class AcademicSchedulePreviewController extends ChangeNotifier {
  AcademicSchedulePreviewController({
    AcademicScheduleStore? store,
    AcademicSchedulePreviewAccountLoader? accountLoader,
    AcademicSchedulePreviewPrivacyLoader? privacyLoader,
    AcademicSchedulePreviewCalendarLoader? calendarLoader,
    Future<TeachingScheduleMode> Function(String accountKey)?
    scheduleModeLoader,
    DateTime Function()? clock,
  }) : _store = store ?? AcademicScheduleStore(),
       _accountLoader =
           accountLoader ??
           (() async => (await AuthService.getCurrentAccount())?.accountKey),
       _privacyLoader = privacyLoader ?? PrivacyAgreementService.isAccepted,
       _calendarLoader =
           calendarLoader ??
           ((accountKey, semester) => AcademicCalendarService()
               .readCachedCalendarForSemester(accountKey, semester)),
       _scheduleModeLoader =
           scheduleModeLoader ??
           ((accountKey) => CampusSettingsService().scheduleModeFor()),
       _clock = clock ?? east8Now;

  final AcademicScheduleStore _store;
  final AcademicSchedulePreviewAccountLoader _accountLoader;
  final AcademicSchedulePreviewPrivacyLoader _privacyLoader;
  final AcademicSchedulePreviewCalendarLoader _calendarLoader;
  final Future<TeachingScheduleMode> Function(String accountKey)
  _scheduleModeLoader;
  final DateTime Function() _clock;
  final Map<String, AcademicPersonalSchedule> _baseSchedules = {};
  final Map<String, AcademicPersonalSchedule> _workingSchedules = {};
  final Map<AcademicScheduleScope, List<AcademicSemesterOption>> _catalogs = {};
  final Map<AcademicScheduleScope, String> _selectedSemesters = {};
  final Map<AcademicScheduleScope, AcademicCalendarData?> _calendars = {};
  final Map<String, String> conflictSelections = {};
  AcademicPersonalSchedule _demoWorkingSchedule = demoAcademicSchedulePreview;
  AcademicScheduleScope _lastAccountScope = AcademicScheduleScope.personal;

  AcademicSchedulePreviewSource source = AcademicSchedulePreviewSource.account;
  AcademicScheduleScope scope = AcademicScheduleScope.personal;
  TeachingScheduleMode scheduleMode = TeachingScheduleMode.weishui;
  int? selectedWeek;
  bool selectedHoliday = false;
  bool loading = true;
  bool showNonCurrent = true;
  bool hideWeekend = false;
  String? accountKey;
  String? error;
  int _generation = 0;

  AcademicPersonalSchedule? get schedule {
    if (source == AcademicSchedulePreviewSource.demo) {
      return _demoWorkingSchedule;
    }
    final semester = _selectedSemesters[scope];
    if (semester == null) return null;
    return _workingSchedules[_snapshotKey(scope, semester)];
  }

  AcademicPersonalSchedule? get originalSchedule {
    if (source == AcademicSchedulePreviewSource.demo) {
      return demoAcademicSchedulePreview;
    }
    final semester = _selectedSemesters[scope];
    if (semester == null) return null;
    return _baseSchedules[_snapshotKey(scope, semester)];
  }

  AcademicCalendarData? get calendar =>
      source == AcademicSchedulePreviewSource.demo
          ? demoAcademicCalendarPreview
          : _calendars[scope];

  AcademicCalendarWeek? get currentCalendarWeek => calendar?.weekFor(_clock());

  int? get currentWeek {
    final week = currentCalendarWeek;
    return week == null || week.isHoliday ? null : week.week;
  }

  int get maxWeek => schedule?.maxWeek ?? 1;

  DateTime get now => _clock();

  List<AcademicSemesterOption> get semesters => _catalogs[scope] ?? const [];

  bool get hasCurrentSnapshot => schedule != null;

  bool get hasAnyCachedData =>
      _catalogs.values.any((catalog) => catalog.isNotEmpty);

  String get selectedSemester => _selectedSemesters[scope] ?? '';

  Future<void> initialize() => reload();

  Future<bool> checkAccess() async {
    final accepted = await _privacyLoader();
    if (!accepted) {
      clearAccountData();
      error = '请先同意当前用户协议，再查看课表预览。';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> reload({bool resetPreviewEdits = true}) async {
    if (source == AcademicSchedulePreviewSource.demo) {
      final current = currentCalendarWeek;
      selectedWeek = current?.week;
      selectedHoliday = current?.isHoliday ?? false;
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!await checkAccess()) return;
      final sessionRevision = AuthService.sessionRevision;
      final loadedAccount = (await _accountLoader())?.trim();
      if (!_isCurrent(generation)) return;
      if (loadedAccount == null || loadedAccount.isEmpty) {
        clearAccountData();
        error = '当前没有已登录账号。可以切换到演示数据预览页面。';
        return;
      }
      if (accountKey != null && accountKey != loadedAccount) {
        _clearAccountDataState();
      }
      final catalogs = <AcademicScheduleScope, List<AcademicSemesterOption>>{};
      final loaded = <String, AcademicPersonalSchedule>{};
      final calendars = <AcademicScheduleScope, AcademicCalendarData?>{};
      for (final targetScope in AcademicScheduleScope.values) {
        final catalog = await _store.readCachedSemesterCatalog(
          loadedAccount,
          scope: targetScope,
        );
        final options = <AcademicSemesterOption>[];
        if (catalog != null) {
          for (final semester in academicSemestersNewestFirst(
            catalog.semesters,
          )) {
            final id = semester.id.trim();
            if (id.isEmpty) continue;
            final snapshot = await _store.readCachedSchedule(
              loadedAccount,
              id,
              scope: targetScope,
            );
            if (snapshot == null) continue;
            loaded[_snapshotKey(targetScope, id)] = snapshot;
            options.add(
              AcademicSemesterOption(
                id: id,
                label: semester.label,
                selected: id == catalog.selectedSemesterId,
              ),
            );
          }
        }
        final current = await _store.readCachedCurrentSchedule(
          loadedAccount,
          scope: targetScope,
        );
        if (current != null) {
          final key = _snapshotKey(targetScope, current.semesterId);
          loaded.putIfAbsent(key, () => current);
          if (options.every((value) => value.id != current.semesterId)) {
            options.insert(
              0,
              AcademicSemesterOption(
                id: current.semesterId,
                label: current.semesterLabel,
                selected: true,
              ),
            );
          }
        }
        options.sort((left, right) {
          final a = loaded[_snapshotKey(targetScope, left.id)];
          final b = loaded[_snapshotKey(targetScope, right.id)];
          return (b?.semesterId ?? '').compareTo(a?.semesterId ?? '');
        });
        catalogs[targetScope] = options;
        if (options.isNotEmpty) {
          final preferred = options.where((item) => item.selected).firstOrNull;
          _selectedSemesters[targetScope] ??= preferred?.id ?? options.first.id;
          if (options.every(
            (item) => item.id != _selectedSemesters[targetScope],
          )) {
            _selectedSemesters[targetScope] = preferred?.id ?? options.first.id;
          }
          final active = _selectedSemesters[targetScope]!;
          final selectedSchedule = loaded[_snapshotKey(targetScope, active)];
          if (selectedSchedule != null) {
            calendars[targetScope] = await _calendarLoader(
              loadedAccount,
              selectedSchedule.semesterLabel,
            );
          }
        }
      }
      if (!_isCurrent(generation)) return;
      final loadedMode = await _scheduleModeLoader(loadedAccount);
      if (!_isCurrent(generation)) return;
      if (AuthService.sessionRevision != sessionRevision ||
          (await _accountLoader())?.trim() != loadedAccount ||
          !await _privacyLoader()) {
        clearAccountData();
        return;
      }
      accountKey = loadedAccount;
      _lastAccountScope = scope;
      scheduleMode = loadedMode;
      _catalogs
        ..clear()
        ..addAll(catalogs);
      _calendars
        ..clear()
        ..addAll(calendars);
      if (resetPreviewEdits) {
        _baseSchedules
          ..clear()
          ..addAll(loaded);
        _workingSchedules
          ..clear()
          ..addAll(loaded);
      } else {
        for (final entry in loaded.entries) {
          _baseSchedules.putIfAbsent(entry.key, () => entry.value);
          _workingSchedules.putIfAbsent(entry.key, () => entry.value);
        }
      }
      final selectedCalendarWeek = _calendars[scope]?.weekFor(_clock());
      selectedWeek = selectedCalendarWeek?.week;
      selectedHoliday = selectedCalendarWeek?.isHoliday ?? false;
      if (!hasCurrentSnapshot) {
        error = '没有找到已缓存课表，请先在正式课表同步；也可以切换到演示数据。';
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        error = '读取已缓存课表失败，请返回后重试。';
      }
    } finally {
      if (_isCurrent(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void useDemo() {
    _generation++;
    source = AcademicSchedulePreviewSource.demo;
    scope = AcademicScheduleScope.personal;
    final current = currentCalendarWeek;
    selectedWeek = current?.week;
    selectedHoliday = current?.isHoliday ?? false;
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<void> useAccount() async {
    source = AcademicSchedulePreviewSource.account;
    scope = _lastAccountScope;
    final generation = ++_generation;
    if (!await checkAccess()) return;
    final sessionRevision = AuthService.sessionRevision;
    final activeAccount = (await _accountLoader())?.trim();
    if (!_isCurrent(generation)) return;
    if (!await _privacyLoader()) {
      if (_isCurrent(generation)) {
        clearAccountData();
        error = '请先同意当前用户协议，再查看课表预览。';
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    if (activeAccount == null || activeAccount.isEmpty) {
      clearAccountData();
      error = '当前没有已登录账号。可以切换到演示数据预览页面。';
      notifyListeners();
      return;
    }
    if (AuthService.sessionRevision != sessionRevision ||
        activeAccount != accountKey) {
      clearAccountData();
      await reload();
      return;
    }
    if (accountKey != null && schedule != null) {
      final current = currentCalendarWeek;
      selectedWeek = current?.week;
      selectedHoliday = current?.isHoliday ?? false;
      error = null;
      notifyListeners();
      return;
    }
    selectedWeek = null;
    selectedHoliday = false;
    await reload();
  }

  Future<void> selectScope(AcademicScheduleScope value) async {
    if (scope == value) return;
    scope = value;
    error = null;
    if (source == AcademicSchedulePreviewSource.account) {
      _lastAccountScope = value;
    }
    final current = currentCalendarWeek;
    selectedWeek = current?.week;
    selectedHoliday = current?.isHoliday ?? false;
    if (source == AcademicSchedulePreviewSource.account &&
        schedule == null &&
        !loading) {
      await reload(resetPreviewEdits: false);
    } else {
      notifyListeners();
    }
  }

  Future<void> selectSemester(String semesterId) async {
    if (semesterId == selectedSemester) return;
    if (source == AcademicSchedulePreviewSource.demo) return;
    final generation = ++_generation;
    loading = true;
    notifyListeners();
    try {
      if (!await checkAccess()) return;
      final activeAccount = accountKey;
      if (activeAccount == null) return;
      final sessionRevision = AuthService.sessionRevision;
      final snapshot = await _store.readCachedSchedule(
        activeAccount,
        semesterId,
        scope: scope,
      );
      if (!_isCurrent(generation) || accountKey != activeAccount) return;
      if (snapshot == null) {
        error = '该学期没有已缓存课表。';
        return;
      }
      final calendar = await _calendarLoader(
        activeAccount,
        snapshot.semesterLabel,
      );
      if (!_isCurrent(generation) ||
          accountKey != activeAccount ||
          AuthService.sessionRevision != sessionRevision ||
          (await _accountLoader())?.trim() != activeAccount ||
          !await _privacyLoader()) {
        if (_isCurrent(generation)) clearAccountData();
        return;
      }
      final key = _snapshotKey(scope, semesterId);
      _selectedSemesters[scope] = semesterId;
      _baseSchedules.putIfAbsent(key, () => snapshot);
      _workingSchedules.putIfAbsent(key, () => snapshot);
      _calendars[scope] = calendar;
      final current = currentCalendarWeek;
      selectedWeek = current?.week;
      selectedHoliday = current?.isHoliday ?? false;
      error = null;
    } catch (_) {
      if (_isCurrent(generation)) error = '读取该学期缓存失败。';
    } finally {
      if (_isCurrent(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void selectPage({int? week, bool holiday = false}) {
    selectedWeek = week;
    selectedHoliday = holiday;
    notifyListeners();
  }

  void setShowNonCurrent(bool value) {
    showNonCurrent = value;
    notifyListeners();
  }

  void setHideWeekend(bool value) {
    hideWeekend = value;
    notifyListeners();
  }

  void editEntry(
    AcademicPersonalScheduleEntry? original,
    AcademicPersonalScheduleEntry edited,
  ) {
    if (scope != AcademicScheduleScope.personal) return;
    final current = schedule;
    if (current == null) return;
    final entries = [...current.entries];
    if (original == null) {
      entries.add(edited);
    } else {
      final index = entries.indexWhere(
        (entry) =>
            identical(entry, original) ||
            academicScheduleEntryKey(entry) ==
                academicScheduleEntryKey(original),
      );
      if (index < 0) return;
      entries[index] = edited;
    }
    _replaceWorking(current.copyWith(entries: entries));
  }

  void deleteEntry(AcademicPersonalScheduleEntry entry) {
    if (scope != AcademicScheduleScope.personal) return;
    final current = schedule;
    if (current == null) return;
    final entries = current.entries
        .where(
          (candidate) =>
              !identical(candidate, entry) &&
              academicScheduleEntryKey(candidate) !=
                  academicScheduleEntryKey(entry),
        )
        .toList(growable: false);
    _replaceWorking(current.copyWith(entries: entries));
  }

  void restorePreview() {
    if (source == AcademicSchedulePreviewSource.demo) {
      _demoWorkingSchedule = demoAcademicSchedulePreview;
      notifyListeners();
      return;
    }
    final current = schedule;
    final original = originalSchedule;
    if (current == null || original == null) return;
    _replaceWorking(original);
  }

  String conflictKey(Iterable<AcademicPersonalScheduleEntry> entries) {
    final sorted = entries.map(academicScheduleEntryKey).toList()..sort();
    final values = entries.toList(growable: false);
    return '${values.first.weekday}|${values.map((e) => e.startPeriod).reduce((a, b) => a < b ? a : b)}|${values.map((e) => e.endPeriod).reduce((a, b) => a > b ? a : b)}|${sorted.join('|')}';
  }

  String selectionKey(AcademicPersonalScheduleEntry entry) =>
      academicScheduleEntryKey(entry);

  AcademicPersonalScheduleEntry selectedConflict(
    Iterable<AcademicPersonalScheduleEntry> entries,
  ) {
    final values = entries.toList(growable: false);
    final selected = conflictSelections[conflictKey(values)];
    return values.firstWhere(
      (entry) => selectionKey(entry) == selected,
      orElse: () => values.first,
    );
  }

  void selectConflict(
    Iterable<AcademicPersonalScheduleEntry> entries,
    AcademicPersonalScheduleEntry selected,
  ) {
    final values = entries.toList(growable: false);
    conflictSelections[conflictKey(values)] = selectionKey(selected);
    notifyListeners();
  }

  void clearAccountData() {
    _generation++;
    _clearAccountDataState();
  }

  void _clearAccountDataState() {
    accountKey = null;
    _lastAccountScope = AcademicScheduleScope.personal;
    _baseSchedules.clear();
    _workingSchedules.clear();
    _catalogs.clear();
    _selectedSemesters.clear();
    _calendars.clear();
    conflictSelections.clear();
    if (source == AcademicSchedulePreviewSource.account) {
      loading = false;
      selectedWeek = null;
      selectedHoliday = false;
    }
    notifyListeners();
  }

  String _snapshotKey(AcademicScheduleScope scope, String semester) =>
      '${scope.name}|$semester';

  bool _isCurrent(int generation) => generation == _generation;

  void _replaceWorking(AcademicPersonalSchedule updated) {
    if (source == AcademicSchedulePreviewSource.demo) {
      _demoWorkingSchedule = updated;
      notifyListeners();
      return;
    }
    final key = _snapshotKey(scope, updated.semesterId);
    _workingSchedules[key] = updated;
    notifyListeners();
  }
}

final demoAcademicSchedulePreview = AcademicPersonalSchedule(
  semesterId: 'dev-demo',
  semesterLabel: '演示学期',
  maxWeek: 17,
  fetchedAt: DateTime(2026, 9, 1),
  entries: [
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-math',
      courseSequence: 'DEMO-01',
      courseCode: 'MATH101',
      courseName: '高等数学（上）',
      teacher: '张老师',
      location: '渭水校区教学东楼 A-101',
      weekday: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeksText: '1-16周',
      weeks: List.generate(16, (index) => index + 1),
      practiceWeeks: [],
    ),
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-conflict-a',
      courseSequence: 'DEMO-02',
      courseCode: 'CS201',
      courseName: '数据结构与算法设计',
      teacher: '李老师',
      location: '教学西楼 W-302',
      weekday: 2,
      startPeriod: 3,
      endPeriod: 4,
      weeksText: '1-8周',
      weeks: List.generate(8, (index) => index + 1),
      practiceWeeks: [],
    ),
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-conflict-b',
      courseSequence: 'DEMO-03',
      courseCode: 'DESIGN101',
      courseName: '信息可视化与交互设计',
      teacher: '王老师',
      location: '创新实验中心 409',
      weekday: 2,
      startPeriod: 4,
      endPeriod: 5,
      weeksText: '3-12周',
      weeks: List.generate(10, (index) => index + 3),
      practiceWeeks: [],
    ),
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-single',
      courseSequence: 'DEMO-04',
      courseCode: 'PE001',
      courseName: '大学体育',
      teacher: '',
      location: '体育馆',
      weekday: 3,
      startPeriod: 7,
      endPeriod: 7,
      weeksText: '1-16周',
      weeks: List.generate(16, (index) => index + 1),
      practiceWeeks: [],
    ),
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-future',
      courseSequence: 'DEMO-05',
      courseCode: 'ENG301',
      courseName: '学术英语写作与跨文化交流',
      teacher: '陈老师',
      location: '长安校区教学主楼 C 区 6 层 602 教室',
      weekday: 4,
      startPeriod: 1,
      endPeriod: 3,
      weeksText: '8-16周',
      weeks: List.generate(9, (index) => index + 8),
      practiceWeeks: [],
    ),
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-friday',
      courseSequence: 'DEMO-06',
      courseCode: 'PHY102',
      courseName: '大学物理实验',
      teacher: '赵老师',
      location: '物理实验中心',
      weekday: 5,
      startPeriod: 5,
      endPeriod: 6,
      weeksText: '2-14周',
      weeks: List.generate(13, (index) => index + 2),
      practiceWeeks: [],
    ),
    AcademicPersonalScheduleEntry(
      sourceId: 'demo-weekend',
      courseSequence: 'DEMO-07',
      courseCode: 'ART100',
      courseName: '艺术鉴赏',
      teacher: '周老师',
      location: '北区活动中心',
      weekday: 6,
      startPeriod: 2,
      endPeriod: 3,
      weeksText: '1-16周',
      weeks: List.generate(16, (index) => index + 1),
      practiceWeeks: [],
    ),
  ],
);

final demoAcademicCalendarPreview = AcademicCalendarData(
  term: const AcademicCalendarTerm(academicYear: '2026-2027', semester: 1),
  weeks: [
    for (var week = 1; week <= 17; week++)
      AcademicCalendarWeek(
        week: week,
        startDate: DateTime(2026, 9, 7).add(Duration(days: (week - 1) * 7)),
        endDate: DateTime(2026, 9, 13).add(Duration(days: (week - 1) * 7)),
      ),
    AcademicCalendarWeek(
      week: 18,
      startDate: DateTime(2026, 9, 7).add(const Duration(days: 17 * 7)),
      endDate: DateTime(2026, 9, 13).add(const Duration(days: 17 * 7)),
      isHoliday: true,
      event: '寒假',
    ),
  ],
  events: const [],
);
