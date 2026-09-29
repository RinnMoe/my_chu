import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/campus_map/campus_map_capability.dart';
import '../../capabilities/text_utils.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/error_feedback_service.dart';
import '../../services/user_error_message.dart';
import 'academic_affairs_models.dart';
import 'academic_affairs_service.dart';
import 'academic_affairs_widgets.dart';
import '../../capabilities/academic_schedule/academic_schedule_utils.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 全校排课查询：按学期筛选全校课程并展开排课安排。
class AcademicSyllabusPage extends StatefulWidget {
  final SyllabusSemesterLoader? semesterLoader;
  final SyllabusSearchLoader? searchLoader;

  const AcademicSyllabusPage({
    super.key,
    this.semesterLoader,
    this.searchLoader,
  });

  @override
  State<AcademicSyllabusPage> createState() => _AcademicSyllabusPageState();
}

class _AcademicSyllabusPageState extends State<AcademicSyllabusPage> {
  static const _initialAutoLoadPages = 3;

  final TextEditingController _courseNameController = TextEditingController();
  final TextEditingController _courseCodeController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  final TextEditingController _teachClassController = TextEditingController();
  final TextEditingController _courseTypeController = TextEditingController();
  final TextEditingController _lessonNoController = TextEditingController();

  List<AcademicSemesterOption> _semesters = const [];
  String? _selectedSemester;
  List<SyllabusCourseRow> _rows = const [];
  int _pageNo = 0;
  bool _hasMore = false;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  Object? _loadMoreError;
  int _generation = 0;
  int _autoLoadedPages = 1;
  AcademicAffairsBackend _backend = AcademicAffairsBackend.undergraduate;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _courseNameController.dispose();
    _courseCodeController.dispose();
    _teacherController.dispose();
    _teachClassController.dispose();
    _courseTypeController.dispose();
    _lessonNoController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _loadMoreError = null;
    });
    final service = AcademicAffairsService();
    final result = await captureAcademicSection(() async {
      final backend =
          widget.semesterLoader == null && widget.searchLoader == null
              ? await AcademicAffairsBackendResolver.resolveCurrent()
              : AcademicAffairsBackend.undergraduate;
      final options = academicSemestersNewestFirst(
        await (widget.semesterLoader ?? service.fetchSyllabusSemesters)(),
      );
      final semesterId = options.isEmpty ? null : options.first.id;
      if (semesterId == null) {
        throw const AcademicAffairsException('未找到排课查询学期');
      }
      final page = await (widget.searchLoader ?? service.searchSyllabus)(
        semesterId,
        const SyllabusSearchFilters(),
        1,
      );
      return (
        backend: backend,
        options: options,
        semesterId: semesterId,
        page: page,
      );
    });
    if (!mounted || generation != _generation) return;
    setState(() {
      final value = result.value;
      if (value != null) {
        _backend = value.backend;
        _semesters = value.options;
        _selectedSemester = value.semesterId;
        _rows = value.page.rows;
        _pageNo = value.page.pageNo;
        _hasMore = value.page.hasMore;
        _total = value.page.total;
        _autoLoadedPages = 1;
      }
      _error = result.error;
      _loading = false;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicSyllabus,
      );
    }
    if (result.value?.page.hasMore ?? false) {
      unawaited(_loadMore(automatic: true));
    }
  }

  Future<void> _searchFirstPage(SyllabusSearchFilters filters) async {
    final semesterId = _selectedSemester;
    if (semesterId == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _loadMoreError = null;
    });
    final service = AcademicAffairsService();
    final result = await captureAcademicSection(
      () => (widget.searchLoader ?? service.searchSyllabus)(
        semesterId,
        filters,
        1,
      ),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      if (result.value != null) {
        _rows = result.value!.rows;
        _pageNo = result.value!.pageNo;
        _hasMore = result.value!.hasMore;
        _total = result.value!.total;
        _autoLoadedPages = 1;
      }
      _error = result.error;
      _loading = false;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicSyllabus,
      );
    }
    if (result.value?.hasMore ?? false) {
      unawaited(_loadMore(automatic: true));
    }
  }

  Future<void> _loadMore({bool automatic = false}) async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (automatic && _autoLoadedPages >= _initialAutoLoadPages) return;
    final generation = _generation;
    final semesterId = _selectedSemester;
    if (semesterId == null) return;
    final nextPage = _pageNo + 1;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    final service = AcademicAffairsService();
    final result = await captureAcademicSection(
      () => (widget.searchLoader ?? service.searchSyllabus)(
        semesterId,
        _currentFilters(),
        nextPage,
      ),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      final value = result.value;
      if (value != null) {
        _rows = [..._rows, ...value.rows];
        _pageNo = value.pageNo;
        _hasMore = value.hasMore;
        _total = value.total;
        if (automatic) _autoLoadedPages++;
      }
      _loadMoreError = result.error;
      _loadingMore = false;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicSyllabus,
      );
    }
    if (automatic &&
        (result.value?.hasMore ?? false) &&
        _autoLoadedPages < _initialAutoLoadPages) {
      unawaited(_loadMore(automatic: true));
    }
  }

  Future<void> _openFilterSheet() async {
    final sheet = _SyllabusFilterSheet(
      initial: _currentFilters(),
      backend: _backend,
    );
    final filters = await showModalBottomSheet<SyllabusSearchFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
    if (filters == null) return;
    _courseNameController.text = filters.courseName;
    _courseCodeController.text = filters.courseCode;
    _teacherController.text = filters.teacherName;
    _teachClassController.text = filters.teachClassName;
    _courseTypeController.text = filters.courseTypeName;
    _lessonNoController.text = filters.lessonNo;
    await _searchFirstPage(filters);
  }

  SyllabusSearchFilters _currentFilters() {
    return SyllabusSearchFilters(
      lessonNo: _lessonNoController.text.trim(),
      courseCode: _courseCodeController.text.trim(),
      courseName: _courseNameController.text.trim(),
      courseTypeName: _courseTypeController.text.trim(),
      teachClassName: _teachClassController.text.trim(),
      teacherName: _teacherController.text.trim(),
    );
  }

  void _openMap(SyllabusScheduleEntry entry) {
    if (entry.location.trim().isEmpty) return;
    campusMapCapability.openRequest(
      context,
      UnifiedPlaceRequest(rawText: entry.location.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildSyllabusBody(context);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('全校排课查询'),
          actions: [
            IconButton(
              tooltip: '筛选',
              onPressed: _openFilterSheet,
              icon: const Icon(Icons.filter_list),
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _buildSyllabusBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedSemester,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '学年学期',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            menuMaxHeight: MediaQuery.sizeOf(context).height * .6,
            items: [
              for (final semester in _semesters)
                DropdownMenuItem<String?>(
                  value: semester.id,
                  child: Text(semester.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value == null || value == _selectedSemester) return;
              setState(() => _selectedSemester = value);
              unawaited(_searchFirstPage(_currentFilters()));
            },
          ),
        ),
        if (_total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 $_total 门课程',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return AcademicSectionFallback(
        loading: false,
        error: _error,
        emptyMessage: '暂无排课数据',
        onRefresh: _loadInitial,
      );
    }
    if (_rows.isEmpty) {
      return AcademicEmptyState(message: '暂无排课数据', onRefresh: _loadInitial);
    }
    final showFooter = _hasMore || _loadingMore || _loadMoreError != null;
    Widget itemBuilder(BuildContext context, int index) {
      if (index >= _rows.length) {
        return _SyllabusLoadMoreFooter(
          hasMore: _hasMore,
          loadingMore: _loadingMore,
          error: _loadMoreError,
          onLoadMore: () => unawaited(_loadMore()),
          onRetry: () => unawaited(_loadMore()),
        );
      }
      final row = _rows[index];
      return _SyllabusCourseCard(row: row, onMap: _openMap);
    }

    final list = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: _rows.length + (showFooter ? 1 : 0),
      itemBuilder: itemBuilder,
    );

    return RefreshIndicator(onRefresh: _loadInitial, child: list);
  }
}

class _SyllabusCourseCard extends StatelessWidget {
  final SyllabusCourseRow row;
  final ValueChanged<SyllabusScheduleEntry> onMap;

  const _SyllabusCourseCard({required this.row, required this.onMap});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      row.category,
      row.teachClass,
      row.teachers,
      row.language,
      row.campus,
    ].where((value) => value.isNotEmpty).join(' · ');
    final metaParts = [
      '实际 ${row.actualCount}',
      '上限 ${row.limitCount}',
      '${row.credits} 学分',
      row.periodPerWeek,
      row.weekState,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.schedule_outlined),
        title: Text(
          row.courseName.ifEmpty(row.courseSequence),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                row.courseSequence,
                row.courseCode,
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitleParts.isNotEmpty)
              Text(subtitleParts, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (metaParts.isNotEmpty)
              Text(metaParts, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        children: [
          if (row.scheduleEntries.isEmpty)
            const ListTile(title: Text('暂无排课安排')),
          for (final entry in row.scheduleEntries)
            _SyllabusScheduleTile(entry: entry, onMap: () => onMap(entry)),
        ],
      ),
    );
  }
}

class _SyllabusScheduleTile extends StatelessWidget {
  final SyllabusScheduleEntry entry;
  final VoidCallback onMap;

  const _SyllabusScheduleTile({required this.entry, required this.onMap});

  @override
  Widget build(BuildContext context) {
    final detailParts = [
      entry.teachers,
      entry.periodText,
      entry.weeksText,
    ].where((value) => value.isNotEmpty).join(' · ');

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 56,
        child: Text(
          entry.weekdayLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      title: Text(
        detailParts.isNotEmpty ? detailParts : entry.rawText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        entry.rawText,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          entry.location.isEmpty
              ? null
              : IconButton(
                tooltip: '在地图中查看',
                onPressed: onMap,
                icon: const Icon(Icons.map_outlined),
              ),
    );
  }
}

class _SyllabusLoadMoreFooter extends StatelessWidget {
  final bool hasMore;
  final bool loadingMore;
  final Object? error;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  const _SyllabusLoadMoreFooter({
    required this.hasMore,
    required this.loadingMore,
    required this.error,
    required this.onLoadMore,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Card(
        child: ListTile(
          title: Text(academicErrorMessage(error!)),
          trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
        ),
      );
    }
    if (hasMore) {
      return Center(
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('加载更多'),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

class _SyllabusFilterSheet extends StatefulWidget {
  final SyllabusSearchFilters initial;
  final AcademicAffairsBackend backend;

  const _SyllabusFilterSheet({required this.initial, required this.backend});

  @override
  State<_SyllabusFilterSheet> createState() => _SyllabusFilterSheetState();
}

class _SyllabusFilterSheetState extends State<_SyllabusFilterSheet> {
  late final TextEditingController _lessonNoController;
  late final TextEditingController _courseCodeController;
  late final TextEditingController _courseNameController;
  late final TextEditingController _courseTypeController;
  late final TextEditingController _teachClassController;
  late final TextEditingController _teacherController;

  @override
  void initState() {
    super.initState();
    _lessonNoController = TextEditingController(text: widget.initial.lessonNo);
    _courseCodeController = TextEditingController(
      text: widget.initial.courseCode,
    );
    _courseNameController = TextEditingController(
      text: widget.initial.courseName,
    );
    _courseTypeController = TextEditingController(
      text: widget.initial.courseTypeName,
    );
    _teachClassController = TextEditingController(
      text: widget.initial.teachClassName,
    );
    _teacherController = TextEditingController(
      text: widget.initial.teacherName,
    );
  }

  @override
  void dispose() {
    _lessonNoController.dispose();
    _courseCodeController.dispose();
    _courseNameController.dispose();
    _courseTypeController.dispose();
    _teachClassController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      SyllabusSearchFilters(
        lessonNo: _lessonNoController.text.trim(),
        courseCode: _courseCodeController.text.trim(),
        courseName: _courseNameController.text.trim(),
        courseTypeName: _courseTypeController.text.trim(),
        teachClassName: _teachClassController.text.trim(),
        teacherName: _teacherController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('筛选条件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _filterField(
              _lessonNoController,
              widget.backend == AcademicAffairsBackend.graduate
                  ? '开课号'
                  : '课程序号',
            ),
            _filterField(_courseNameController, '课程名称'),
            if (widget.backend == AcademicAffairsBackend.undergraduate)
              _filterField(_courseCodeController, '课程代码'),
            _filterField(_courseTypeController, '课程类别'),
            if (widget.backend == AcademicAffairsBackend.undergraduate)
              _filterField(_teachClassController, '教学班'),
            _filterField(_teacherController, '教师'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.search),
              label: const Text('查询'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
