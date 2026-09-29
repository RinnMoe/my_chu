import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/east8_time.dart';
import '../../capabilities/public_holidays/public_holidays.dart';
import '../../capabilities/skeleton_block.dart';
import '../../services/error_feedback_service.dart';
import '../../services/user_error_message.dart';
import 'academic_calendar_models.dart';
import 'academic_calendar_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class AcademicCalendarPage extends StatefulWidget {
  final AcademicCalendarService? service;
  final PublicHolidayProvider? publicHolidayProvider;
  final DateTime Function()? clock;

  const AcademicCalendarPage({
    super.key,
    this.service,
    this.publicHolidayProvider,
    this.clock,
  });

  @override
  State<AcademicCalendarPage> createState() => _AcademicCalendarPageState();
}

class _AcademicCalendarPageState extends State<AcademicCalendarPage> {
  late final AcademicCalendarService _service;
  late final PublicHolidayProvider _publicHolidayProvider;
  PublicHolidayRevisionSource? _publicHolidayRevisionSource;
  late final DateTime Function() _clock;
  List<AcademicCalendarTerm> _terms = const [];
  AcademicCalendarData? _calendar;
  PublicHolidaySnapshot? _publicHolidaySnapshot;
  Object? _error;
  bool _loading = true;
  int _generation = 0;
  int _publicHolidayGeneration = 0;
  final _scrollController = ScrollController();
  final _currentWeekKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AcademicCalendarService();
    _publicHolidayProvider =
        widget.publicHolidayProvider ?? PublicHolidayCapability();
    final revisionSource = _publicHolidayProvider;
    if (revisionSource is PublicHolidayRevisionSource) {
      final source = revisionSource as PublicHolidayRevisionSource;
      _publicHolidayRevisionSource = source;
      source.revision.addListener(_onPublicHolidayRevision);
    }
    _clock = widget.clock ?? east8Now;
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _publicHolidayRevisionSource?.revision.removeListener(
      _onPublicHolidayRevision,
    );
    if (widget.publicHolidayProvider == null) {
      final provider = _publicHolidayProvider;
      if (provider is PublicHolidayCapability) provider.close();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onPublicHolidayRevision() {
    final calendar = _calendar;
    if (!mounted || calendar == null) return;
    unawaited(_loadPublicHolidays(calendar));
  }

  Future<void> _loadInitial({bool force = false}) async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = _calendar == null;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<_CalendarLoadResult>([
        _capture(_service.fetchTerms(force: force)),
        _capture(_service.fetchCurrentCalendar(force: force)),
      ]);
      if (!mounted || generation != _generation) return;
      final termsResult = results[0];
      final calendarResult = results[1];
      final loadedCalendar =
          calendarResult.value is AcademicCalendarData
              ? calendarResult.value as AcademicCalendarData
              : null;
      setState(() {
        if (termsResult.value case final List<AcademicCalendarTerm> terms) {
          _terms = terms;
        }
        if (loadedCalendar != null) _calendar = loadedCalendar;
        _error = calendarResult.error ?? termsResult.error;
        _loading = false;
      });
      final loadError = calendarResult.error ?? termsResult.error;
      if (loadError != null) {
        logUserFacingError(
          UserErrorContext.academic,
          loadError,
          operationId: UserOperationId.academicCalendar,
        );
      }
      if (loadedCalendar != null) {
        _scheduleCurrentWeek(loadedCalendar);
        unawaited(_loadPublicHolidays(loadedCalendar, force: force));
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicCalendar,
      );
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectTerm(AcademicCalendarTerm term) async {
    if (_calendar?.term.id == term.id) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _publicHolidayGeneration++;
      _publicHolidaySnapshot = null;
    });
    try {
      final calendar = await _service.fetchCalendar(term);
      if (!mounted || generation != _generation) return;
      setState(() {
        _calendar = calendar;
        _loading = false;
      });
      _scheduleCurrentWeek(calendar);
      unawaited(_loadPublicHolidays(calendar));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicCalendar,
      );
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadPublicHolidays(
    AcademicCalendarData calendar, {
    bool force = false,
  }) async {
    final generation = ++_publicHolidayGeneration;
    if (calendar.weeks.isEmpty) {
      if (!mounted || !identical(_calendar, calendar)) return;
      setState(() {
        _publicHolidaySnapshot = null;
      });
      return;
    }
    var startDate = calendar.weeks.first.startDate;
    var endDate = calendar.weeks.first.endDate;
    for (final week in calendar.weeks.skip(1)) {
      if (week.startDate.isBefore(startDate)) startDate = week.startDate;
      if (week.endDate.isAfter(endDate)) endDate = week.endDate;
    }
    if (mounted) {
      setState(() {
        _publicHolidaySnapshot = null;
      });
    }
    try {
      final snapshot = await _publicHolidayProvider.loadRange(
        startDate,
        endDate,
        force: force,
      );
      if (!mounted ||
          generation != _publicHolidayGeneration ||
          !identical(_calendar, calendar)) {
        return;
      }
      setState(() {
        _publicHolidaySnapshot = snapshot;
      });
    } catch (_) {
      // Public holiday annotations are optional; the school calendar remains
      // usable when the independent data source is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('校历'),
          actions: [
            if (_terms.isNotEmpty && _calendar != null)
              _termPickerButton(context, _calendar!),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_loading && _calendar == null) {
      return const _CalendarSkeleton();
    }
    if (_error != null && _calendar == null) {
      return _CalendarError(error: _error!, onRetry: _loadInitial);
    }
    final calendar = _calendar;
    if (calendar == null) return const Center(child: Text('暂无校历数据'));
    final weekTable = _CalendarWeekTable(
      calendar: calendar,
      publicHolidays: _publicHolidaySnapshot,
      currentDate: _clock(),
      currentWeekKey: _currentWeekKey,
    );
    final scrollView = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MaterialBanner(
                content: Text('刷新失败：$_error'),
                actions: [
                  TextButton(onPressed: _loadInitial, child: const Text('重试')),
                ],
              ),
            ),
          ),
        if (calendar.weeks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('该学期暂无周次数据')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverToBoxAdapter(child: weekTable),
          ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () => _loadInitial(force: true),
      child: scrollView,
    );
  }

  Widget _termPickerButton(
    BuildContext context,
    AcademicCalendarData calendar,
  ) {
    return Semantics(
      button: true,
      label: '当前学期：${calendar.term.label}',
      child: Tooltip(
        message: '切换学期',
        child: TextButton(
          key: const ValueKey('academic-calendar-term-picker'),
          onPressed: () => unawaited(_showTermPicker(context, calendar)),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 208, maxWidth: 208),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: Text(
                    calendar.term.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTermPicker(
    BuildContext context,
    AcademicCalendarData calendar,
  ) async {
    final selected = await showModalBottomSheet<AcademicCalendarTerm>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        var refreshing = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCalendar = _calendar ?? calendar;
            return SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .5,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
                    child: Row(
                      children: [
                        Text(
                          '选择学期',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '刷新',
                          onPressed:
                              refreshing
                                  ? null
                                  : () async {
                                    setSheetState(() => refreshing = true);
                                    try {
                                      await _loadInitial(force: true);
                                    } finally {
                                      if (sheetContext.mounted) {
                                        setSheetState(() => refreshing = false);
                                      }
                                    }
                                  },
                          icon:
                              refreshing
                                  ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(top: 2, bottom: 16),
                      itemCount: _terms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (_, index) {
                        final term = _terms[index];
                        final isSelected = term.id == selectedCalendar.term.id;
                        return ListTile(
                          title: Text(term.label),
                          selected: isSelected,
                          trailing:
                              isSelected
                                  ? const Icon(Icons.check_circle_outline)
                                  : null,
                          onTap: () => Navigator.of(sheetContext).pop(term),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (!mounted || selected == null) return;
    await _selectTerm(selected);
  }

  void _scheduleCurrentWeek(AcademicCalendarData calendar) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_calendar, calendar)) return;
      final currentWeek = calendar.weekFor(_clock());
      if (currentWeek == null) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      final currentWeekContext = _currentWeekKey.currentContext;
      if (currentWeekContext == null) return;
      Scrollable.ensureVisible(
        currentWeekContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _CalendarLoadResult {
  final Object? value;
  final Object? error;

  const _CalendarLoadResult.success(this.value) : error = null;
  const _CalendarLoadResult.failure(this.error) : value = null;
}

Future<_CalendarLoadResult> _capture(Future<Object> future) async {
  try {
    return _CalendarLoadResult.success(await future);
  } catch (error) {
    return _CalendarLoadResult.failure(error);
  }
}

String _calendarDateKey(DateTime date) =>
    '${date.year}-${date.month}-${date.day}';

Map<String, String> _calendarHolidayNamesByDate(
  Iterable<PublicHolidayDay> days,
) {
  final offDays = [
    for (final day in days)
      if (day.isOffDay && day.name.trim().isNotEmpty) day,
  ]..sort((left, right) => left.date.compareTo(right.date));
  final lastDateByName = <String, DateTime>{};
  final namesByDate = <String, String>{};
  for (final day in offDays) {
    final name = day.name.trim();
    final previous = lastDateByName[name];
    if (previous == null || day.date.difference(previous).inDays > 1) {
      namesByDate[_calendarDateKey(day.date)] = name;
    }
    if (previous == null || day.date.isAfter(previous)) {
      lastDateByName[name] = day.date;
    }
  }
  return namesByDate;
}

class _CalendarWeekTable extends StatelessWidget {
  static const weekColumnWidth = 86.0;

  final AcademicCalendarData calendar;
  final PublicHolidaySnapshot? publicHolidays;
  final DateTime currentDate;
  final GlobalKey currentWeekKey;

  const _CalendarWeekTable({
    required this.calendar,
    required this.publicHolidays,
    required this.currentDate,
    required this.currentWeekKey,
  });

  @override
  Widget build(BuildContext context) {
    final materialColors = Theme.of(context).colorScheme;
    final surface = materialColors.surface;
    final separator = materialColors.outlineVariant;
    final header = materialColors.surfaceContainerHighest;
    final currentWeek = calendar.weekFor(currentDate);
    final holidayNamesByDate = _calendarHolidayNamesByDate(
      publicHolidays?.days ?? const <PublicHolidayDay>[],
    );
    const weekdays = ['周次', '一', '二', '三', '四', '五', '六', '日'];
    return Container(
      key: const ValueKey('academic-calendar-grid'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: separator),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            color: header,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: _CalendarWeekTable.weekColumnWidth),
                for (var index = 1; index < weekdays.length; index++)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekdays[index],
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          color:
                              index >= 6
                                  ? materialColors.error
                                  : materialColors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final week in calendar.weeks)
            _CalendarWeekRow(
              key:
                  identical(week, currentWeek)
                      ? currentWeekKey
                      : ValueKey('academic-calendar-week-${week.week}'),
              week: week,
              events: _eventsFor(calendar, week),
              publicHolidays: _publicHolidaysFor(publicHolidays, week),
              holidayNamesByDate: holidayNamesByDate,
              current: identical(week, currentWeek),
              currentDate: currentDate,
            ),
        ],
      ),
    );
  }

  static List<AcademicCalendarEvent> _eventsFor(
    AcademicCalendarData calendar,
    AcademicCalendarWeek week,
  ) => calendar.events.where((event) => week.contains(event.date)).toList();

  static List<PublicHolidayDay> _publicHolidaysFor(
    PublicHolidaySnapshot? snapshot,
    AcademicCalendarWeek week,
  ) => [
    for (final day in snapshot?.days ?? const <PublicHolidayDay>[])
      if (week.contains(day.date)) day,
  ];
}

class _CalendarWeekRow extends StatelessWidget {
  final AcademicCalendarWeek week;
  final List<AcademicCalendarEvent> events;
  final List<PublicHolidayDay> publicHolidays;
  final Map<String, String> holidayNamesByDate;
  final bool current;
  final DateTime currentDate;

  const _CalendarWeekRow({
    super.key,
    required this.week,
    required this.events,
    required this.publicHolidays,
    required this.holidayNamesByDate,
    required this.current,
    required this.currentDate,
  });

  @override
  Widget build(BuildContext context) {
    final materialColors = Theme.of(context).colorScheme;
    final primary = materialColors.primary;
    final label = materialColors.onSurface;
    final secondary = materialColors.onSurfaceVariant;
    final separator = materialColors.outlineVariant;
    final statusLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.normal,
      color: current ? primary : secondary,
    );
    final days = List.generate(
      7,
      (index) => week.startDate.add(Duration(days: index)),
    );
    final hasExamWeek = events.any(_isExamWeekEvent);
    final dayEvents = events;
    final eventsByDay = [
      for (final day in days)
        dayEvents.where((event) => _sameDate(event.date, day)).toList(),
    ];
    final publicHolidaysByDay = [
      for (final day in days)
        publicHolidays
            .where((holiday) => _sameDate(holiday.date, day))
            .toList(),
    ];
    final rowColor =
        current
            ? (materialColors.primaryContainer)
            : week.isHoliday
            ? (materialColors.surfaceContainerHighest)
            : (materialColors.surface);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(top: BorderSide(color: separator)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _CalendarWeekTable.weekColumnWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '第${week.week}周',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: current ? primary : label,
                        ),
                      ),
                      if (week.isHoliday)
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            '（假期）',
                            textAlign: TextAlign.center,
                            style: statusLabelStyle,
                          ),
                        ),
                      if (hasExamWeek)
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            '（考试周）',
                            textAlign: TextAlign.center,
                            style: statusLabelStyle,
                          ),
                        ),
                      if (week.event.trim().isNotEmpty)
                        Text(
                          week.event.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: secondary),
                        ),
                    ],
                  ),
                ),
              ),
              for (var index = 0; index < days.length; index++)
                Expanded(
                  child: _CalendarDayCell(
                    key: ValueKey(
                      'academic-calendar-day-${days[index].year}-'
                      '${days[index].month}-${days[index].day}',
                    ),
                    date: days[index],
                    events: eventsByDay[index],
                    publicHolidays: publicHolidaysByDay[index],
                    publicHolidayName:
                        holidayNamesByDate[_calendarDateKey(days[index])],
                    current: _sameDate(days[index], currentDate),
                    weekend: days[index].weekday >= DateTime.saturday,

                    onTap:
                        eventsByDay[index].isEmpty &&
                                publicHolidaysByDay[index].isEmpty
                            ? null
                            : () => _showDayEvents(
                              context,
                              days[index],
                              eventsByDay[index],
                              publicHolidaysByDay[index],
                            ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static void _showDayEvents(
    BuildContext context,
    DateTime date,
    List<AcademicCalendarEvent> events,
    List<PublicHolidayDay> publicHolidays,
  ) {
    Widget buildDialog(BuildContext dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;

      return AlertDialog(
        title: Text('${date.month}月${date.day}日'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (publicHolidays.isNotEmpty) ...[
              Text(
                '公共节假日',
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              for (final holiday in publicHolidays)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        holiday.isOffDay
                            ? Icons.celebration_outlined
                            : Icons.work_history_outlined,
                        size: 20,
                        color:
                            holiday.isOffDay
                                ? colors.error
                                : publicHolidayColor(
                                  dialogContext,
                                  isOffDay: false,
                                ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PublicHolidayLabel(
                              day: holiday,

                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(holiday.name),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (publicHolidays.isNotEmpty && events.isNotEmpty)
              const SizedBox(height: 2),
            if (events.isNotEmpty) ...[
              Text('校历事件', style: Theme.of(dialogContext).textTheme.titleSmall),
              const SizedBox(height: 10),
            ],
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      event.isCommonHoliday
                          ? Icons.celebration_outlined
                          : Icons.event_note_outlined,
                      size: 20,
                      color:
                          event.isCommonHoliday
                              ? colors.error
                              : colors.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.isCommonHoliday ? '节假日' : '特殊事件',
                            style: Theme.of(dialogContext).textTheme.labelMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(event.title),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    }

    showDialog<void>(context: context, builder: buildDialog);
  }

  static bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static bool _isExamWeekEvent(AcademicCalendarEvent event) =>
      event.isSpecial && event.title.trim().contains('考试周');
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime date;
  final List<AcademicCalendarEvent> events;
  final List<PublicHolidayDay> publicHolidays;
  final String? publicHolidayName;
  final bool current;
  final bool weekend;
  final VoidCallback? onTap;

  const _CalendarDayCell({
    super.key,
    required this.date,
    required this.events,
    required this.publicHolidays,
    required this.publicHolidayName,
    required this.current,
    required this.weekend,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final materialColors = Theme.of(context).colorScheme;
    final primary = materialColors.primary;
    final label = materialColors.onSurface;
    final secondary = materialColors.onSurfaceVariant;
    final hasPublicHoliday = publicHolidays.any((holiday) => holiday.isOffDay);
    final hasPublicHolidayAdjustment = publicHolidays.any(
      (holiday) => !holiday.isOffDay,
    );
    final dayColor =
        hasPublicHoliday
            ? publicHolidayColor(context, isOffDay: true)
            : hasPublicHolidayAdjustment
            ? publicHolidayColor(context, isOffDay: false)
            : weekend
            ? (materialColors.error)
            : label;
    final publicHolidayLabel =
        publicHolidayName ?? (hasPublicHolidayAdjustment ? '调休' : null);
    Color eventColor(bool holiday) {
      if (holiday) {
        return materialColors.error;
      }
      return materialColors.secondary;
    }

    final content = Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration:
          current
              ? BoxDecoration(
                border: Border.all(color: primary, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              )
              : null,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (date.day == 1)
            Text(
              '${date.month}月',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: secondary),
            )
          else
            const SizedBox(height: 14),
          Text(
            '${date.day}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: dayColor,
              fontWeight: current ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          if (publicHolidayLabel != null)
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  publicHolidayLabel,
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: dayColor,
                  ),
                ),
              ),
            ),
          SizedBox(
            height: publicHolidayLabel == null ? 6 : 4,
            child:
                events.isEmpty
                    ? null
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final event in events.take(3))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: eventColor(event.isCommonHoliday),
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox.square(dimension: 5),
                            ),
                          ),
                      ],
                    ),
          ),
        ],
      ),
    );
    return Semantics(
      key: ValueKey(
        'academic-calendar-semantic-${date.year}-${date.month}-${date.day}',
      ),
      excludeSemantics: true,
      button: onTap != null,
      onTap: onTap,
      label:
          '${date.month}月${date.day}日'
          '${publicHolidays.isEmpty ? '' : '，公共节假日：${publicHolidays.map((holiday) => '${holiday.label}${holiday.name}').join('、')}'}'
          '${events.isEmpty ? '' : '，校历事件：${events.map((event) => event.title).join('、')}'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }
}

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) {
    const color = null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBlock(width: 208, height: 40, color: color),
        ),
        const SizedBox(height: 8),
        const SkeletonBlock(height: 118, color: color),
        const SizedBox(height: 10),
        const SkeletonBlock(height: 118, color: color),
      ],
    );
  }
}

class _CalendarError extends StatelessWidget {
  final Object error;
  final Future<void> Function({bool force}) onRetry;

  const _CalendarError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy_outlined, size: 48),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => onRetry(force: true),
            child: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}
