import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';
import '../../services/auth_service.dart';
import '../../services/development_mode_service.dart';
import '../../services/platform_environment.dart';
import '../../services/privacy_agreement_service.dart';
import '../../services/teaching_schedule_service.dart';
import '../../widgets/apple_window_controls.dart';
import '../campus_map/campus_map_capability.dart';
import 'academic_schedule_editor.dart';
import 'academic_schedule_preview_controller.dart';
import 'academic_schedule_utils.dart';

class AcademicSchedulePreviewPage extends StatefulWidget {
  static const rootTabKey = 'dev.academic_schedule.preview';
  static const rootTabLabel = '新版课表';

  const AcademicSchedulePreviewPage({super.key, this.controller});

  final AcademicSchedulePreviewController? controller;

  @override
  State<AcademicSchedulePreviewPage> createState() =>
      _AcademicSchedulePreviewPageState();
}

class _AcademicSchedulePreviewPageState
    extends State<AcademicSchedulePreviewPage> {
  late final AcademicSchedulePreviewController _preview;
  late PageController _weekController;
  String? _pagerDataIdentity;
  int _pagerGeneration = 0;
  AcademicPersonalScheduleEntry? _inspectedEntry;
  List<AcademicPersonalScheduleEntry> _inspectedSources = const [];
  bool _accessDenied = false;
  late final bool _ownsController;

  bool get _isDemo => _preview.source == AcademicSchedulePreviewSource.demo;
  bool get _isPersonal => _preview.scope == AcademicScheduleScope.personal;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _preview = widget.controller ?? AcademicSchedulePreviewController();
    _pagerDataIdentity = _currentPagerDataIdentity;
    _weekController = PageController(initialPage: _selectedPageIndex);
    _preview.addListener(_onPreviewChanged);
    AuthService.sessionRevisionNotifier.addListener(_onSessionChanged);
    PrivacyAgreementService.revision.addListener(_onPrivacyChanged);
    if (DevelopmentModeService.isDev) unawaited(_preview.initialize());
  }

  @override
  void dispose() {
    _weekController.dispose();
    _preview.removeListener(_onPreviewChanged);
    if (_ownsController) _preview.dispose();
    AuthService.sessionRevisionNotifier.removeListener(_onSessionChanged);
    PrivacyAgreementService.revision.removeListener(_onPrivacyChanged);
    super.dispose();
  }

  void _onPreviewChanged() {
    if (!mounted) return;
    final identity = _currentPagerDataIdentity;
    if (identity != _pagerDataIdentity) {
      _pagerDataIdentity = identity;
      final previous = _weekController;
      _weekController = PageController(initialPage: _selectedPageIndex);
      _pagerGeneration++;
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPagerSelection());
  }

  void _onSessionChanged() {
    _inspectedEntry = null;
    _inspectedSources = const [];
    _preview.clearAccountData();
    if (!_isDemo) unawaited(_preview.reload());
  }

  void _onPrivacyChanged() {
    unawaited(_refreshPrivacyState());
  }

  Future<void> _refreshPrivacyState() async {
    final accepted = await PrivacyAgreementService.isAccepted();
    if (!mounted) return;
    if (!accepted) {
      _accessDenied = true;
      _inspectedEntry = null;
      _inspectedSources = const [];
      _preview.clearAccountData();
      _preview.error = '当前用户协议未同意或已撤回。';
      setState(() {});
      return;
    }
    _accessDenied = false;
    if (!_isDemo) await _preview.reload();
  }

  Future<bool> _ensureAccess() async {
    final allowed = await _preview.checkAccess();
    if (!mounted) return false;
    setState(() => _accessDenied = !allowed);
    return allowed;
  }

  @override
  Widget build(BuildContext context) {
    if (!DevelopmentModeService.isDev) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: const Text('新版课表预览')),
        ),
        body: const Center(child: Text('此页面仅在 Debug 开发构建中可用。')),
      );
    }
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: Row(
            children: [
              Flexible(
                child: Text(
                  _weekTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 4),
              _PreviewScopeButton(
                label: _isPersonal ? '个人' : '班级',
                nextLabel: _isPersonal ? '班级' : '个人',
                onTap: _preview.loading ? null : _toggleScope,
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const ValueKey('academic-schedule-semester-selector'),
              tooltip: '选择学期：$_semesterLabel',
              onPressed:
                  _isDemo || _preview.loading ? null : _showSemesterPicker,
              icon: _PreviewTopBarLabel(
                primary: _semesterTopBarLabel.primary,
                secondary: _semesterTopBarLabel.secondary,
              ),
            ),
            IconButton(
              key: const ValueKey('academic-schedule-week-selector'),
              tooltip: '选择周次：$_weekSemanticLabel',
              onPressed:
                  _preview.loading || _preview.schedule == null
                      ? null
                      : _showWeekPicker,
              icon: _PreviewTopBarLabel(
                primary: _weekTopBarLabel.primary,
                secondary: _weekTopBarLabel.secondary,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '课表选项',
              onSelected: _onOptionSelected,
              itemBuilder:
                  (context) => [
                    const PopupMenuItem<String>(
                      enabled: false,
                      child: Text('DEV · 新版课表预览'),
                    ),
                    PopupMenuItem(
                      value: 'source',
                      child: Text(_isDemo ? '切换到真实缓存' : '切换到演示数据'),
                    ),
                    PopupMenuItem(
                      value: 'currentWeek',
                      enabled: _preview.currentCalendarWeek != null,
                      child: const Text('返回当前周'),
                    ),
                    if (_isPersonal)
                      const PopupMenuItem(
                        value: 'restore',
                        child: Text('恢复预览初始状态'),
                      ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: 'weekend',
                      checked: _preview.hideWeekend,
                      child: const Text('不显示周末'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'noncurrent',
                      checked: _preview.showNonCurrent,
                      child: const Text('显示非本周课程'),
                    ),
                    if (_isPersonal && _preview.schedule != null)
                      const PopupMenuItem(
                        value: 'addCourse',
                        child: Text('添加课程'),
                      ),
                    PopupMenuItem(
                      value: 'reload',
                      child: Text(_isDemo ? '恢复演示数据初始状态' : '重新载入缓存'),
                    ),
                  ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
      body: SafeArea(top: false, child: _buildBody(context)),
    );
  }

  String get _semesterLabel {
    if (_isDemo) return '演示学期';
    return _preview.semesters
            .where((value) => value.id == _preview.selectedSemester)
            .firstOrNull
            ?.label ??
        _preview.schedule?.semesterLabel ??
        '选择学期';
  }

  _PreviewTopBarLabelData get _semesterTopBarLabel =>
      _isDemo
          ? const _PreviewTopBarLabelData(primary: '演示')
          : _compactPreviewSemesterLabel(_semesterLabel);

  _PreviewTopBarLabelData get _weekTopBarLabel {
    if (_preview.selectedHoliday) {
      return const _PreviewTopBarLabelData(primary: '假期');
    }
    final week = _preview.selectedWeek;
    return week == null
        ? const _PreviewTopBarLabelData(primary: '全部')
        : _PreviewTopBarLabelData(primary: '$week', secondary: '周');
  }

  String get _weekSemanticLabel {
    if (_preview.selectedHoliday) return '假期';
    final week = _preview.selectedWeek;
    return week == null ? '全部' : '第$week周';
  }

  String get _weekTitle {
    if (_preview.selectedHoliday) return '假期';
    final week = _preview.selectedWeek;
    return week == null ? '全部' : '第$week周';
  }

  String get _currentPagerDataIdentity =>
      '${_preview.source.name}|${_preview.scope.name}|${_preview.selectedSemester}|${_preview.schedule?.semesterId ?? ''}|${_preview.schedule?.maxWeek ?? 0}';

  List<_WeekSelection> get _pageSelections {
    final holidays =
        _preview.calendar?.weeks.where((week) => week.isHoliday).toList() ??
        <AcademicCalendarWeek>[];
    holidays.sort((left, right) => left.week.compareTo(right.week));
    return [
      const _WeekSelection.all(),
      for (var week = 1; week <= _preview.maxWeek; week++)
        _WeekSelection.week(week),
      for (final holiday in holidays) _WeekSelection.holiday(holiday.week),
    ];
  }

  int get _selectedPageIndex {
    final selections = _pageSelections;
    final index = selections.indexWhere(
      (selection) =>
          selection.week == _preview.selectedWeek &&
          selection.holiday == _preview.selectedHoliday,
    );
    return index < 0 ? 0 : index;
  }

  void _syncPagerSelection() {
    if (!mounted || !_weekController.hasClients) return;
    final target = _selectedPageIndex.clamp(0, _pageSelections.length - 1);
    final page = _weekController.page;
    if (page != null && page.round() == target) return;
    unawaited(
      _weekController.animateToPage(
        target,
        duration: _motion(context, 180),
        curve: Curves.easeInOut,
      ),
    );
  }

  void _onPageChanged(int index) {
    final selections = _pageSelections;
    if (index < 0 || index >= selections.length) return;
    final selection = selections[index];
    _preview.selectPage(week: selection.week, holiday: selection.holiday);
  }

  Widget _buildBody(BuildContext context) {
    if (_preview.loading && _preview.schedule == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final schedule = _preview.schedule;
    if (_accessDenied) return _buildAccessMessage(context);
    if (schedule == null) return _buildNoSchedule(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final environment = PlatformEnvironment.fromContext(context);
        final canInspectAlongside =
            environment.deviceFamily == DeviceFamily.tablet &&
            constraints.maxWidth - 320 - 1 - 28 >= _visibleWeekdays.length * 80;
        return Column(
          children: [
            if (_preview.error != null) _buildNotice(context, _preview.error!),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: PageView.builder(
                      key: ValueKey(
                        'academic-schedule-preview-pager-$_pagerGeneration',
                      ),
                      controller: _weekController,
                      itemCount: _pageSelections.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder:
                          (context, index) => _buildGrid(
                            context,
                            schedule,
                            selection: _pageSelections[index],
                          ),
                    ),
                  ),
                  if (canInspectAlongside && _inspectedEntry != null) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(width: 320, child: _buildInspector(context)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNotice(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_isDemo)
                TextButton(
                  onPressed: _preview.useAccount,
                  child: const Text('真实缓存'),
                )
              else
                TextButton(
                  onPressed: _preview.useDemo,
                  child: const Text('试用演示'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    AcademicPersonalSchedule schedule, {
    required _WeekSelection selection,
  }) {
    final week = selection.holiday ? null : selection.week;
    final merged =
        _preview.scope == AcademicScheduleScope.administrativeClass
            ? mergeClassScheduleEntries(schedule.entries)
            : mergeScheduleEntries(schedule.entries);
    final split =
        selection.holiday
            ? const AcademicScheduleWeekSplit(
              current: [],
              faded: [],
              hidden: [],
            )
            : week == null
            ? AcademicScheduleWeekSplit(
              current: merged.entries,
              faded: const [],
              hidden: const [],
            )
            : classifyScheduleEntriesForWeek(merged.entries, week);
    final visible = <AcademicPersonalScheduleEntry>[
      ...split.current,
      if (!selection.holiday && _preview.showNonCurrent) ...split.faded,
    ];
    final groups = groupScheduleEntriesByOverlap(visible)
        .where((group) => _visibleWeekdays.contains(group.weekday))
        .toList(growable: false);
    final maxPeriod = math.max(
      11,
      schedule.entries.fold<int>(
        0,
        (max, entry) => math.max(max, entry.endPeriod),
      ),
    );
    final colors = _previewCourseColors(merged.entries);
    final weekStartDate =
        selection.holiday
            ? _calendarWeekForHoliday(selection.week)?.startDate
            : week == null
            ? null
            : _calendarWeek(week)?.startDate;
    final isCurrentWeek = week != null && week == _preview.currentWeek;
    final colorScheme = Theme.of(context).colorScheme;
    final highlightColor = colorScheme.primary.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.07,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const leftWidth = 28.0;
        final isTablet =
            PlatformEnvironment.fromContext(context).deviceFamily ==
            DeviceFamily.tablet;
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final periodHeight =
            isTablet
                ? ((constraints.maxHeight - 44) / maxPeriod)
                    .clamp(40.0 * scale, math.max(56.0, 40.0 * scale))
                    .toDouble()
                : 68.0;
        final columnWidth = math.max(
          0.0,
          (constraints.maxWidth - leftWidth) / _visibleWeekdays.length,
        );

        return Column(
          key: ValueKey(
            'academic-schedule-preview-week-${selection.week ?? 0}-${selection.holiday}',
          ),
          children: [
            SizedBox(
              key: const ValueKey('academic-schedule-preview-week-header'),
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: leftWidth,
                    child: Center(
                      child:
                          weekStartDate == null
                              ? null
                              : Text(
                                '${weekStartDate.month}月',
                                style: TextStyle(
                                  fontSize: 9,
                                  height: 1.2,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                    ),
                  ),
                  for (final day in _visibleWeekdays)
                    SizedBox(
                      width: columnWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              isCurrentWeek && day == _preview.now.weekday
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
                                '周${_weekdayName(day)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.2,
                                ),
                              ),
                              if (weekStartDate != null)
                                Text(
                                  '${weekStartDate.add(Duration(days: day - 1)).day}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    height: 1.2,
                                    color: colorScheme.onSurfaceVariant,
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
                  height: periodHeight * maxPeriod,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          children: [
                            SizedBox(
                              width: leftWidth,
                              child: Column(
                                children: [
                                  for (
                                    var period = 1;
                                    period <= maxPeriod;
                                    period++
                                  )
                                    SizedBox(
                                      key:
                                          period == 1
                                              ? const ValueKey(
                                                'academic-schedule-preview-period-1',
                                              )
                                              : null,
                                      height: periodHeight,
                                      child: _PeriodMarker(
                                        period: period,
                                        time: teachingScheduleFor(
                                          _preview.scheduleMode,
                                        ).period(period),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            for (final day in _visibleWeekdays)
                              SizedBox(
                                width: columnWidth,
                                child: Stack(
                                  children: [
                                    for (final group in groups.where(
                                      (value) => value.weekday == day,
                                    ))
                                      _positionedCourse(
                                        context,
                                        group,
                                        merged.sources,
                                        colors,
                                        periodHeight,
                                        week,
                                        split.hidden,
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (groups.isEmpty)
                        Positioned(
                          left: leftWidth,
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Text(
                              selection.holiday
                                  ? '假期中~'
                                  : week == null
                                  ? '暂无课程'
                                  : '本周没有课程',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
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
      },
    );
  }

  Widget _positionedCourse(
    BuildContext context,
    AcademicScheduleCellGroup group,
    Map<AcademicPersonalScheduleEntry, List<AcademicPersonalScheduleEntry>>
    sources,
    Map<String, int> colors,
    double periodHeight,
    int? week,
    List<AcademicPersonalScheduleEntry> hidden,
  ) {
    final faded =
        week != null &&
        group.entries.every((entry) => !entry.isVisibleInWeek(week));
    return Positioned(
      top: (group.startPeriod - 1) * periodHeight + 2,
      left: 2,
      right: 2,
      height: math.max(
        12,
        (group.endPeriod - group.startPeriod + 1) * periodHeight - 4,
      ),
      child: Semantics(
        button: true,
        label:
            '${group.entries.map((entry) => entry.displayName).join('、')}，第${group.startPeriod}-${group.endPeriod}节${faded ? '，非本周课程' : ''}，点按查看详情',
        child: _PreviewCourseBlock(
          group: group,
          blockHeight: math.max(
            12,
            (group.endPeriod - group.startPeriod + 1) * periodHeight - 4,
          ),
          mergeSources: sources,
          selectedWeek: week,
          isClassSchedule: !_isPersonal,
          courseColorIndices: colors,
          personalConflictSelections: _preview.conflictSelections,
          faded: faded,
          onTap:
              () => _showCellDetails(
                group.entries,
                isNonCurrent: faded,
                companions:
                    faded ? const [] : hidden.where(group.overlaps).toList(),
                mergeSources: sources,
              ),
        ),
      ),
    );
  }

  Widget _buildInspector(BuildContext context) {
    final entry = _inspectedEntry;
    if (entry == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => setState(() => _inspectedEntry = null),
              icon: const Icon(Icons.close),
            ),
          ),
          ..._buildGroupedCourseDetails(
            context,
            entry,
            isClassSchedule: !_isPersonal,
            sources: _inspectedSources.isEmpty ? [entry] : _inspectedSources,
            closeOverlay: false,
          ),
        ],
      ),
    );
  }

  bool _canShowScheduleInspector(double width) =>
      width - 320 - 1 - 28 >= _visibleWeekdays.length * 80;

  Widget _buildNoSchedule(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _accessDenied
                    ? Icons.lock_outline
                    : Icons.calendar_month_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _preview.error ?? '尚无可预览的课表',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _preview.loading ? null : _preview.reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新载入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _useDemo,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('使用演示数据'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessMessage(BuildContext context) => _buildNoSchedule(context);

  Future<void> _onOptionSelected(String value) async {
    switch (value) {
      case 'source':
        if (_isDemo) {
          if (await _ensureAccess() && mounted) await _preview.useAccount();
        } else {
          _useDemo();
        }
        break;
      case 'currentWeek':
        _selectCurrentCalendarWeek();
        break;
      case 'restore':
        _preview.restorePreview();
        _inspectedEntry = null;
        _inspectedSources = const [];
        break;
      case 'reload':
        if (_isDemo) {
          _preview.restorePreview();
        } else if (await _ensureAccess() && mounted) {
          await _preview.reload();
        }
        break;
      case 'addCourse':
        await _openEditor();
        break;
      case 'weekend':
        _preview.setHideWeekend(!_preview.hideWeekend);
        break;
      case 'noncurrent':
        _preview.setShowNonCurrent(!_preview.showNonCurrent);
        break;
    }
  }

  void _useDemo() {
    _accessDenied = false;
    _preview.useDemo();
  }

  Future<void> _toggleScope() async {
    if (_isDemo) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('演示数据只提供个人课表示例。')));
      return;
    }
    if (!await _ensureAccess()) return;
    final next =
        _preview.scope == AcademicScheduleScope.personal
            ? AcademicScheduleScope.administrativeClass
            : AcademicScheduleScope.personal;
    await _preview.selectScope(next);
    _inspectedEntry = null;
    _inspectedSources = const [];
  }

  Future<void> _showSemesterPicker() async {
    if (!await _ensureAccess()) return;
    if (!mounted) return;
    final semesters = _preview.semesters;
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
                      semester.label.isEmpty ? semester.id : semester.label,
                    ),
                    subtitle: Text(semester.id),
                    trailing:
                        semester.id == _preview.selectedSemester
                            ? const Icon(Icons.check)
                            : null,
                    onTap: () => Navigator.pop(sheetContext, semester.id),
                  ),
                if (semesters.isEmpty) const ListTile(title: Text('没有已缓存的学期')),
              ],
            ),
          ),
    );
    if (selected == null || !mounted || !await _ensureAccess()) return;
    await _preview.selectSemester(selected);
    _inspectedEntry = null;
    _inspectedSources = const [];
  }

  Future<void> _showWeekPicker() async {
    final selections = _pageSelections;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: selections.length,
              itemBuilder: (context, index) {
                final selection = selections[index];
                final currentCalendarWeek = _preview.currentCalendarWeek;
                final current =
                    currentCalendarWeek != null &&
                    selection.week == currentCalendarWeek.week &&
                    selection.holiday == currentCalendarWeek.isHoliday;
                return ListTile(
                  title: Text(
                    selection.holiday
                        ? '假期'
                        : selection.week == null
                        ? '全部'
                        : '第${selection.week}周',
                  ),
                  subtitle:
                      current ? Text(selection.holiday ? '当前' : '本周') : null,
                  trailing:
                      index == _selectedPageIndex
                          ? const Icon(Icons.check)
                          : null,
                  onTap: () => Navigator.of(sheetContext).pop(index),
                );
              },
            ),
          ),
    );
    if (selected == null || !mounted) return;
    final selection = selections[selected];
    _preview.selectPage(week: selection.week, holiday: selection.holiday);
  }

  void _selectCurrentCalendarWeek() {
    final current = _preview.currentCalendarWeek;
    if (current == null) return;
    _preview.selectPage(week: current.week, holiday: current.isHoliday);
  }

  List<AcademicPersonalScheduleEntry> _detailSourcesForSelectedWeek(
    AcademicPersonalScheduleEntry entry,
    Iterable<AcademicPersonalScheduleEntry> sources,
  ) {
    final all = _uniqueScheduleSourceEntries(
      sources.isEmpty ? [entry] : sources,
    );
    final week = _preview.selectedWeek;
    if (week == null || _preview.selectedHoliday) return all;
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
        _preview.conflictSelections[_scheduleConflictGroupKey(courses)];
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
    if (_preview.conflictSelections[conflictKey] == courseKey) return;
    setState(() => _preview.conflictSelections[conflictKey] = courseKey);
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
    if (!await _ensureAccess() || !mounted) return;
    final courses = _uniqueScheduleSourceEntries(entries);
    if (courses.isEmpty) return;
    final environment = PlatformEnvironment.fromContext(context);
    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded &&
        _canShowScheduleInspector(context.size?.width ?? 0) &&
        courses.length == 1) {
      final selected = courses.single;
      setState(() {
        _inspectedEntry = selected;
        _inspectedSources = mergeSources[selected] ?? [selected];
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

    final isClassSchedule =
        _preview.scope == AcademicScheduleScope.administrativeClass;
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
    final isSpecificWeek =
        _preview.selectedWeek != null && !_preview.selectedHoliday;
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
                    unawaited(_openEditor(detailSources.first));
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑课程'),
                ),
              if (mapLocation.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    if (closeOverlay) Navigator.of(sheetContext).pop();
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
    final isClassSchedule =
        _preview.scope == AcademicScheduleScope.administrativeClass;
    final detailSources = _uniqueScheduleSourceEntries(
      _detailSourcesForSelectedWeek(entry, sources),
    );
    final isSpecificWeek =
        _preview.selectedWeek != null && !_preview.selectedHoliday;
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
                          unawaited(_openEditor(detailSources.first));
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
      _preview.scheduleMode,
    ).range(entry.startPeriod, entry.endPeriod);
    return [
      '星期${_weekdayName(entry.weekday)}',
      '第${entry.startPeriod}-${entry.endPeriod}节',
      if (time != null) time.rangeText,
    ].join(' · ');
  }

  Future<void> _openEditor([AcademicPersonalScheduleEntry? entry]) async {
    if (!_isPersonal || !await _ensureAccess()) return;
    if (!mounted) return;
    final schedule = _preview.schedule;
    if (schedule == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => AcademicScheduleEditor(
            initialEntry: entry,
            maxWeek: schedule.maxWeek,
            onSave: (edited) async {
              if (!await _ensureAccess()) return false;
              _preview.editEntry(entry, edited);
              return true;
            },
            onDelete:
                entry == null
                    ? null
                    : () async {
                      if (!await _ensureAccess()) return false;
                      _preview.deleteEntry(entry);
                      return true;
                    },
          ),
    );
  }

  AcademicCalendarWeek? _calendarWeek(int week) =>
      _preview.calendar?.weeks
          .where((item) => item.week == week && !item.isHoliday)
          .firstOrNull;

  AcademicCalendarWeek? _calendarWeekForHoliday(int? week) =>
      _preview.calendar?.weeks
          .where((item) => item.isHoliday && item.week == week)
          .firstOrNull;

  List<int> get _visibleWeekdays =>
      _preview.hideWeekend
          ? const [1, 2, 3, 4, 5]
          : const [1, 2, 3, 4, 5, 6, 7];

  Duration _motion(BuildContext context, int milliseconds) =>
      MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : Duration(milliseconds: milliseconds);
}

class _WeekSelection {
  final int? week;
  final bool holiday;
  const _WeekSelection._(this.week, this.holiday);
  const _WeekSelection.all() : this._(null, false);
  const _WeekSelection.week(int value) : this._(value, false);
  const _WeekSelection.holiday(int value) : this._(value, true);
}

class _PreviewScopeButton extends StatelessWidget {
  const _PreviewScopeButton({
    required this.label,
    required this.nextLabel,
    required this.onTap,
  });
  final String label;
  final String nextLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '当前为$label课表，点击切换到$nextLabel课表',
      child: Tooltip(
        message: '切换到$nextLabel课表',
        child: Material(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: const ValueKey('academic-schedule-scope-selector'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
    );
  }
}

class _PreviewTopBarLabelData {
  const _PreviewTopBarLabelData({required this.primary, this.secondary});

  final String primary;
  final String? secondary;
}

_PreviewTopBarLabelData _compactPreviewSemesterLabel(String value) {
  final source = value.trim();
  if (source.isEmpty) {
    return const _PreviewTopBarLabelData(primary: '选择', secondary: '学期');
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
    return _PreviewTopBarLabelData(
      primary: year ?? season,
      secondary: year == null ? null : season,
    );
  }

  final fallback =
      source
          .replaceAll(RegExp(r'\s*学年\s*'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  return _PreviewTopBarLabelData(primary: fallback.isEmpty ? source : fallback);
}

class _PreviewTopBarLabel extends StatelessWidget {
  const _PreviewTopBarLabel({required this.primary, this.secondary});

  final String primary;
  final String? secondary;

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

class _PeriodMarker extends StatelessWidget {
  const _PeriodMarker({required this.period, required this.time});
  final int period;
  final TeachingPeriodTime? time;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$period', style: const TextStyle(fontSize: 12, height: 1.2)),
          if (time != null) ...[
            Text(
              time!.startText,
              style: TextStyle(fontSize: 9, height: 1.2, color: secondary),
            ),
            Text(
              time!.endText,
              style: TextStyle(fontSize: 9, height: 1.2, color: secondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewCourseBlock extends StatelessWidget {
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

  const _PreviewCourseBlock({
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
        courseColorIndices[_courseColorKey(entry)] ??
        stableCourseColorIndex(
          _courseColorKey(entry),
          colorCount: _previewPalettes.length,
        );
    final palette = _previewPalettes[colorIndex % _previewPalettes.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? palette.dark : palette.light;
    final cardBackground =
        faded
            ? (isDark ? const Color(0xff323944) : const Color(0xffeceff2))
            : background;
    final textColor =
        faded
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : (isDark ? const Color(0xfff7f8fa) : const Color(0xff17212c));
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
    final lineBudget = _PreviewCourseBlockLineBudget.calculate(
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

class _PreviewCourseBlockLineBudget {
  final int titleLines;
  final int locationLines;
  final int teacherLines;

  const _PreviewCourseBlockLineBudget({
    required this.titleLines,
    required this.locationLines,
    required this.teacherLines,
  });

  static _PreviewCourseBlockLineBudget calculate({
    required double blockHeight,
    required int periodSpan,
    required TextScaler textScaler,
    required bool hasStatus,
    required bool hasLocation,
    required bool hasTeacher,
  }) {
    final span = math.max(1, periodSpan).toInt();
    var titleLines = 2;
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
        locationLines > 1) {
      locationLines--;
    }

    return _PreviewCourseBlockLineBudget(
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

class _PreviewPalette {
  const _PreviewPalette(this.light, this.dark);
  final Color light;
  final Color dark;
}

const _previewPalettes = <_PreviewPalette>[
  _PreviewPalette(Color(0xffc9ddf4), Color(0xff29445d)),
  _PreviewPalette(Color(0xffc7e3d9), Color(0xff285047)),
  _PreviewPalette(Color(0xfff6d4bd), Color(0xff624333)),
  _PreviewPalette(Color(0xffd8c9ee), Color(0xff493d65)),
  _PreviewPalette(Color(0xffccdfc7), Color(0xff38513c)),
  _PreviewPalette(Color(0xffc9d3f0), Color(0xff37446b)),
  _PreviewPalette(Color(0xffeec6d7), Color(0xff60384c)),
  _PreviewPalette(Color(0xffbfe1e7), Color(0xff2f4e55)),
  _PreviewPalette(Color(0xfff2cbc4), Color(0xff623c39)),
  _PreviewPalette(Color(0xffd8e2b0), Color(0xff485238)),
  _PreviewPalette(Color(0xffc2dbea), Color(0xff304c61)),
  _PreviewPalette(Color(0xffd9c7e6), Color(0xff4c3d5a)),
  _PreviewPalette(Color(0xffcbd7dd), Color(0xff394c55)),
  _PreviewPalette(Color(0xffe3c9b4), Color(0xff51443e)),
  _PreviewPalette(Color(0xffd2d4d7), Color(0xff43474c)),
];

String _courseColorKey(AcademicPersonalScheduleEntry entry) {
  final code = entry.courseCode.trim();
  if (code.isNotEmpty) return code;
  final name = entry.courseName.trim();
  return name.isNotEmpty ? name : entry.courseSequence.trim();
}

Map<String, int> _previewCourseColors(
  Iterable<AcademicPersonalScheduleEntry> entries,
) {
  final keys =
      entries
          .map(_courseColorKey)
          .where((key) => key.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final used = <int>{};
  final result = <String, int>{};
  for (final key in keys) {
    final preferred = stableCourseColorIndex(
      key,
      colorCount: _previewPalettes.length,
    );
    var index = preferred;
    if (used.length < _previewPalettes.length) {
      for (var offset = 0; offset < _previewPalettes.length; offset++) {
        final candidate = (preferred + offset) % _previewPalettes.length;
        if (!used.contains(candidate)) {
          index = candidate;
          break;
        }
      }
      used.add(index);
    }
    result[key] = index;
  }
  return result;
}

String _weekdayName(int weekday) =>
    const ['一', '二', '三', '四', '五', '六', '日'][(weekday - 1).clamp(0, 6)];

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
