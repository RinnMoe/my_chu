import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/campus_map/campus_map_capability.dart';
import '../../capabilities/text_utils.dart';
import '../../services/error_feedback_service.dart';
import '../../services/user_error_message.dart';
import 'academic_affairs_models.dart';
import 'academic_affairs_service.dart';
import 'academic_affairs_widgets.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 考试安排：考试安排、批次/状态筛选与关键词搜索。
class AcademicExamsPage extends StatefulWidget {
  final AcademicExamLoader? examLoader;
  final AcademicExamSemesterLoader? examSemesterLoader;
  final AcademicExamBatchLoader? examBatchLoader;

  const AcademicExamsPage({
    super.key,
    this.examLoader,
    this.examSemesterLoader,
    this.examBatchLoader,
  });

  @override
  State<AcademicExamsPage> createState() => _AcademicExamsPageState();
}

class _AcademicExamsPageState extends State<AcademicExamsPage> {
  final TextEditingController _queryController = TextEditingController();
  List<AcademicExam>? _exams;
  List<AcademicSemesterOption> _semesters = const [];
  List<AcademicExamBatchOption> _batches = const [];
  String? _selectedSemester;
  String? _selectedBatch;
  String _query = '';
  bool? _arrangedFilter;
  Object? _error;
  bool _loading = true;
  bool _examLoading = false;
  bool _semesterOptionsFailed = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _examLoading = false;
      _error = null;
    });
    final service = AcademicAffairsService();
    var semesterOptionsFailed = false;
    final result = await captureAcademicSection(() async {
      List<AcademicSemesterOption> options = const [];
      List<AcademicExamBatchOption> batches = const [];
      try {
        options =
            await (widget.examSemesterLoader ?? service.fetchExamSemesters)();
      } catch (_) {
        semesterOptionsFailed = true;
        // 学期选项为可选增强，失败时仍按服务端默认学期加载考试安排。
      }
      try {
        batches = await (widget.examBatchLoader ?? service.fetchExamBatches)();
      } catch (_) {
        // 批次选项为可选增强，失败时按全部批次加载。
      }
      final semesterId = defaultSemesterId(options);
      final exams = await (widget.examLoader ?? service.fetchAllExams)(
        semesterId,
      );
      return (options: options, batches: batches, exams: exams);
    });
    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      if (result.value != null) {
        _semesters = result.value!.options;
        _batches = result.value!.batches;
        _exams = result.value!.exams;
        _selectedSemester = defaultSemesterId(_semesters);
        _selectedBatch = null;
        _queryController.clear();
        _query = '';
        _arrangedFilter = null;
      }
      _error = result.error;
      _semesterOptionsFailed = semesterOptionsFailed;
      _loading = false;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicExams,
      );
    }
  }

  Future<void> _reloadExams() async {
    if (_exams == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = false;
      _examLoading = true;
      _error = null;
    });
    final service = AcademicAffairsService();
    final semesterId = _selectedSemester;
    final batchId = _selectedBatch;
    final result = await captureAcademicSection(() {
      final injected = widget.examLoader;
      if (injected != null) return injected(semesterId);
      return service.fetchExamsByBatch(semesterId, batchId);
    });
    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      if (result.value != null) _exams = result.value;
      _queryController.clear();
      _query = '';
      _arrangedFilter = null;
      _error = result.error;
      _examLoading = false;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicExams,
      );
    }
  }

  void _openMap(AcademicExam exam) {
    if (exam.location.trim().isEmpty) return;
    campusMapCapability.openRequest(
      context,
      UnifiedPlaceRequest(rawText: exam.location.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _ExamsView(
      exams: _exams,
      error: _error,
      loading: _loading || _examLoading,
      semesters: _semesters,
      batches: _batches,
      semesterOptionsFailed: _semesterOptionsFailed,
      selectedSemester: _selectedSemester,
      selectedBatch: _selectedBatch,

      onSemesterChanged: (value) {
        setState(() => _selectedSemester = value);
        unawaited(_reloadExams());
      },
      onBatchChanged: (value) {
        setState(() => _selectedBatch = value);
        unawaited(_reloadExams());
      },
      query: _query,
      arrangedFilter: _arrangedFilter,
      queryController: _queryController,
      onQueryChanged: (value) => setState(() => _query = value),
      onArrangedFilterChanged:
          (value) => setState(() => _arrangedFilter = value),
      onMap: _openMap,
      onRefresh: _load,
    );

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('考试安排')),
      ),
      body: view,
    );
  }
}

class _ExamsView extends StatelessWidget {
  final List<AcademicExam>? exams;
  final Object? error;
  final bool loading;
  final List<AcademicSemesterOption> semesters;
  final List<AcademicExamBatchOption> batches;
  final bool semesterOptionsFailed;
  final String? selectedSemester;
  final String? selectedBatch;

  final ValueChanged<String?> onSemesterChanged;
  final ValueChanged<String?> onBatchChanged;
  final String query;
  final bool? arrangedFilter;
  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool?> onArrangedFilterChanged;
  final ValueChanged<AcademicExam> onMap;
  final Future<void> Function() onRefresh;

  const _ExamsView({
    required this.exams,
    required this.error,
    required this.loading,
    required this.semesters,
    required this.batches,
    required this.semesterOptionsFailed,
    required this.selectedSemester,
    required this.selectedBatch,

    required this.onSemesterChanged,
    required this.onBatchChanged,
    required this.query,
    required this.arrangedFilter,
    required this.queryController,
    required this.onQueryChanged,
    required this.onArrangedFilterChanged,
    required this.onMap,
    required this.onRefresh,
  });

  List<AcademicExam> _filtered(List<AcademicExam> source) {
    final keyword = query.trim().toLowerCase();
    return source
        .where((exam) {
          if (keyword.isNotEmpty &&
              !exam.courseName.toLowerCase().contains(keyword) &&
              !exam.courseSequence.toLowerCase().contains(keyword)) {
            return false;
          }
          if (arrangedFilter != null && exam.isScheduled != arrangedFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (exams == null) {
      return Column(
        children: [
          _SemesterSelector(
            semesters: semesters,
            selectedSemester: selectedSemester,
            optionsFailed: semesterOptionsFailed,
            onChanged: onSemesterChanged,
          ),
          Expanded(
            child: AcademicSectionFallback(
              loading: loading,
              error: error,
              emptyMessage: '暂无考试安排',
              onRefresh: onRefresh,
            ),
          ),
        ],
      );
    }
    final children = <Widget>[
      if (loading) const LinearProgressIndicator(minHeight: 2),
      _SemesterSelector(
        semesters: semesters,
        selectedSemester: selectedSemester,
        optionsFailed: semesterOptionsFailed,
        onChanged: onSemesterChanged,
      ),
      _ExamFilters(
        batches: batches,
        selectedBatch: selectedBatch,
        onBatchChanged: onBatchChanged,
        query: query,
        arrangedFilter: arrangedFilter,
        queryController: queryController,
        onQueryChanged: onQueryChanged,
        onArrangedFilterChanged: onArrangedFilterChanged,
      ),
      if (error != null) AcademicInlineError(error: error!, onRetry: onRefresh),
      if (exams!.isEmpty)
        const AcademicEmptyCard(
          icon: Icons.event_busy_outlined,
          text: '本学期暂无考试安排',
        )
      else ...[
        const SizedBox(height: 2),
        Text(
          '${_filtered(exams!).length} 场考试',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (_filtered(exams!).isEmpty)
          const AcademicEmptyCard(
            icon: Icons.search_off_outlined,
            text: '没有符合筛选条件的考试',
          )
        else
          for (final exam in _filtered(exams!))
            _ExamCard(exam: exam, onMap: onMap),
      ],
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      ),
    );
  }
}

class _SemesterSelector extends StatelessWidget {
  final List<AcademicSemesterOption> semesters;
  final String? selectedSemester;
  final bool optionsFailed;
  final ValueChanged<String?> onChanged;

  const _SemesterSelector({
    required this.semesters,
    required this.selectedSemester,
    required this.optionsFailed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.titleSmall;
    final mutedStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final iconColor = Theme.of(context).colorScheme.primary;
    if (semesters.isEmpty) {
      if (!optionsFailed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Text('学期', style: labelStyle),
            const Spacer(),
            Text('教务系统当前学期', style: mutedStyle),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Text('学期', style: labelStyle),
          const Spacer(),
          DropdownButton<String>(
            value: selectedSemester,
            hint: const Text('请选择学期'),
            isDense: true,
            items: [
              for (final semester in semesters)
                DropdownMenuItem<String>(
                  value: semester.id,
                  child: Text(semester.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ExamFilters extends StatelessWidget {
  final List<AcademicExamBatchOption> batches;
  final String? selectedBatch;
  final ValueChanged<String?> onBatchChanged;
  final String query;
  final bool? arrangedFilter;
  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool?> onArrangedFilterChanged;

  const _ExamFilters({
    required this.batches,
    required this.selectedBatch,
    required this.onBatchChanged,
    required this.query,
    required this.arrangedFilter,
    required this.queryController,
    required this.onQueryChanged,
    required this.onArrangedFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: queryController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索课程名称或课程序号',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  query.isEmpty
                      ? null
                      : IconButton(
                        tooltip: '清除',
                        onPressed: () {
                          queryController.clear();
                          onQueryChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (batches.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('考试批次', style: labelStyle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedBatch,
                    isDense: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('全部批次'),
                      ),
                      for (final batch in batches)
                        if (batch.id != '0')
                          DropdownMenuItem<String?>(
                            value: batch.id,
                            child: Text(
                              batch.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: onBatchChanged,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          _FilterChips<bool?>(
            label: '状态',
            options: const [null, true, false],
            selected: arrangedFilter,
            labelFor:
                (option) => switch (option) {
                  null => '全部',
                  true => '已安排',
                  false => '未安排',
                },
            onSelected: onArrangedFilterChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChips<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final T selected;
  final String Function(T option) labelFor;
  final ValueChanged<T> onSelected;

  const _FilterChips({
    required this.label,
    required this.options,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label, style: labelStyle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(labelFor(option)),
                  selected: selected == option,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSelected(option),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  final AcademicExam exam;
  final ValueChanged<AcademicExam> onMap;

  const _ExamCard({required this.exam, required this.onMap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium;
    final bodyStyle = theme.textTheme.bodyMedium;
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final dateTime = _join(exam.examDate, exam.arrangement);
    final location = exam.location.trim();
    final seat = exam.seat.trim();
    final locationLine = _join(location, seat.isEmpty ? '' : '座位 $seat');
    final metaLine = _join(exam.examType, exam.status);
    final note = exam.note.trim();
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exam.courseName.ifEmpty(exam.courseSequence),
            style: titleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (dateTime.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(dateTime, style: bodyStyle),
            ),
          if (locationLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      locationLine,
                      style: bodyStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '在地图中查看',
                      onPressed: () => onMap(exam),
                      icon: const Icon(Icons.map_outlined),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
          if (metaLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(metaLine, style: secondaryStyle),
            ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note, style: secondaryStyle),
            ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: content,
    );
  }

  static String _join(String left, String right) {
    final a = left.trim();
    final b = right.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a · $b';
  }
}
