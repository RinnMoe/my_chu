import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/text_utils.dart';
import '../../services/error_feedback_service.dart';
import '../../theme/app_palette.dart';
import '../../services/platform_environment.dart';
import '../../services/user_error_message.dart';
import 'academic_affairs_models.dart';
import 'academic_affairs_service.dart';
import 'academic_affairs_widgets.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 成绩查询：成绩、绩点与学分。
class AcademicGradesPage extends StatefulWidget {
  final AcademicGradeLoader? gradeLoader;

  const AcademicGradesPage({super.key, this.gradeLoader});

  @override
  State<AcademicGradesPage> createState() => _AcademicGradesPageState();
}

class _AcademicGradesPageState extends State<AcademicGradesPage> {
  AcademicGradeReport? _grades;
  Object? _error;
  String? _selectedTerm;
  AcademicCourseGrade? _selectedGrade;
  var _termSelectionInitialized = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AcademicAffairsService.gradeCacheRevision.addListener(_onGradeCacheChanged);
    _load();
  }

  @override
  void dispose() {
    AcademicAffairsService.gradeCacheRevision.removeListener(
      _onGradeCacheChanged,
    );
    super.dispose();
  }

  void _onGradeCacheChanged() {
    if (mounted) unawaited(_reloadGrades());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = AcademicAffairsService();
    final result = await captureAcademicSection(
      widget.gradeLoader ?? service.fetchGrades,
    );
    if (!mounted) return;
    setState(() {
      if (result.value != null) {
        _applyReport(result.value!);
      }
      _error = result.error;
      _loading = false;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicGrades,
      );
    }
  }

  Future<void> _reloadGrades() async {
    final service = AcademicAffairsService();
    final result = await captureAcademicSection(
      widget.gradeLoader ?? service.fetchGrades,
    );
    if (!mounted) return;
    setState(() {
      if (result.value != null) _applyReport(result.value!);
      _error = result.error;
    });
    if (result.error case final error?) {
      logUserFacingError(
        UserErrorContext.academic,
        error,
        operationId: UserOperationId.academicGrades,
      );
    }
  }

  void _applyReport(AcademicGradeReport report) {
    _grades = report;
    final terms = _sortedGradeTerms(report);
    if (!_termSelectionInitialized) {
      _selectedTerm = terms.isEmpty ? null : terms.first;
      _termSelectionInitialized = true;
      return;
    }
    if (_selectedTerm != null && !terms.contains(_selectedTerm)) {
      _selectedTerm = terms.isEmpty ? null : terms.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _GradesView(
      report: _grades,
      error: _error,
      loading: _loading,
      selectedTerm: _selectedTerm,
      onTermChanged:
          (term) => setState(() {
            _selectedTerm = term;
            _selectedGrade = null;
          }),
      onRefresh: _load,

      selectedGrade: _selectedGrade,
      onGradeSelected: (grade) => setState(() => _selectedGrade = grade),
    );

    return Scaffold(
      appBar: WindowControlsAwareAppBar(child: AppBar(title: const Text('成绩'))),
      body: view,
    );
  }
}

List<String> _sortedGradeTerms(AcademicGradeReport report) {
  final terms =
      report.majorGrades
          .map((grade) => grade.term)
          .where((term) => term.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));
  return terms;
}

class _GradesView extends StatelessWidget {
  final AcademicGradeReport? report;
  final Object? error;
  final bool loading;
  final String? selectedTerm;
  final ValueChanged<String?> onTermChanged;
  final Future<void> Function() onRefresh;

  final AcademicCourseGrade? selectedGrade;
  final ValueChanged<AcademicCourseGrade>? onGradeSelected;

  const _GradesView({
    required this.report,
    required this.error,
    required this.loading,
    required this.selectedTerm,
    required this.onTermChanged,
    required this.onRefresh,

    this.selectedGrade,
    this.onGradeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final environment = PlatformEnvironment.fromContext(context);
    final expandedTablet =
        environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded;
    final gradeTap = expandedTablet ? onGradeSelected : null;
    if (report == null) {
      return AcademicSectionFallback(
        loading: loading,
        error: error,
        emptyMessage: '暂无成绩数据',
        onRefresh: onRefresh,
      );
    }
    final data = report!;
    final terms = _sortedGradeTerms(data);
    final visibleGrades = data.majorGrades
        .where((grade) => selectedTerm == null || grade.term == selectedTerm)
        .toList(growable: false);
    final visibleMinorGrades = data.minorGrades
        .where((grade) => selectedTerm == null || grade.term == selectedTerm)
        .toList(growable: false);
    final groups = <String, List<AcademicCourseGrade>>{};
    for (final grade in visibleGrades) {
      final group = groups.putIfAbsent(
        grade.term.isEmpty ? '未分学期' : grade.term,
        () => [],
      );
      group.add(grade);
    }
    final selectedSummary =
        selectedTerm == null ? null : _termSummaryFor(data, selectedTerm!);
    final selectedWeightedGpa =
        selectedTerm == null ? null : data.weightedGpaForTerm(selectedTerm!);

    final list = KeyedSubtree(
      key: const ValueKey('academic-grades-list'),
      child: RefreshIndicator.adaptive(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (error != null)
              AcademicInlineError(error: error!, onRetry: onRefresh),
            if (data.enrollmentSummary case final summary?)
              _EnrollmentSummaryCard(summary: summary),
            if (terms.isNotEmpty) ...[
              const SizedBox(height: 12),
              _MaterialTermOverviewCard(
                terms: terms,
                selectedTerm: selectedTerm,
                onTermChanged: onTermChanged,
                summary: selectedSummary,
                weightedGpa: selectedWeightedGpa,
                courseCount: visibleGrades.length,
              ),
            ],
            const SizedBox(height: 20),
            _GradeSectionHeader(title: '主修成绩', count: visibleGrades.length),
            const SizedBox(height: 10),
            if (visibleGrades.isEmpty)
              AcademicEmptyCard(
                icon: Icons.school_outlined,
                text: selectedTerm == null ? '暂无成绩' : '该学期暂无成绩',
              )
            else ...[
              if (selectedTerm == null)
                for (final entry in groups.entries) ...[
                  _TermSummaryCard(
                    term: entry.key,
                    summary: _termSummaryFor(data, entry.key),
                    weightedGpa: data.weightedGpaForTerm(entry.key),
                    courseCount: entry.value.length,
                  ),
                  const SizedBox(height: 6),
                  _GradeListSection(grades: entry.value, onGradeTap: gradeTap),
                  if (entry.key != groups.keys.last) const SizedBox(height: 16),
                ]
              else
                _GradeListSection(grades: visibleGrades, onGradeTap: gradeTap),
            ],
            if (visibleMinorGrades.isNotEmpty) ...[
              const SizedBox(height: 24),
              _GradeSectionHeader(
                title: '辅修成绩',
                count: visibleMinorGrades.length,
              ),
              const SizedBox(height: 6),
              _GradeListSection(
                grades: visibleMinorGrades,

                onGradeTap: gradeTap,
              ),
            ],
            if (data.statisticsAt.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '数据统计时间：${data.statisticsAt}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!expandedTablet || selectedGrade == null) return list;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inspectorWidth =
            (constraints.maxWidth * 0.30).clamp(320.0, 360.0).toDouble();
        return Row(
          children: [
            Expanded(child: list),
            const VerticalDivider(width: 1),
            SizedBox(
              width: inspectorWidth,
              child: KeyedSubtree(
                key: const ValueKey('academic-grades-inspector'),
                child: _GradeInspector(grade: selectedGrade),
              ),
            ),
          ],
        );
      },
    );
  }

  static AcademicTermSummary? _termSummaryFor(
    AcademicGradeReport report,
    String term,
  ) {
    for (final summary in report.termSummaries) {
      if ('${summary.academicYear} ${summary.semester}' == term) {
        return summary;
      }
    }
    return null;
  }
}

class _EnrollmentSummaryCard extends StatelessWidget {
  final AcademicEnrollmentSummary summary;

  const _EnrollmentSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final valueColor = colors.onPrimaryContainer;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: valueColor.withValues(alpha: 0.78),
    );
    final supportingValueStyle = theme.textTheme.titleMedium?.copyWith(
      color: valueColor,
      fontWeight: FontWeight.w700,
    );

    Widget supportingMetric(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 2),
        Text(value, style: supportingValueStyle),
      ],
    );

    return Card(
      color: colors.primaryContainer,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '在校总览',
              style: theme.textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('平均绩点', style: labelStyle),
                      const SizedBox(height: 2),
                      Text(
                        academicValue(summary.averageGpa),
                        maxLines: 1,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: valueColor,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 1,
                  height: 72,
                  color: valueColor.withValues(alpha: 0.18),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      supportingMetric(
                        '总学分',
                        academicValue(summary.totalCredits),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 1,
                        color: valueColor.withValues(alpha: 0.18),
                      ),
                      const SizedBox(height: 8),
                      supportingMetric(
                        '课程数',
                        academicValue(summary.courseCount),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool prominent;

  const _Metric({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: (prominent
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _TermSelector extends StatelessWidget {
  final List<String> terms;
  final String? selectedTerm;
  final ValueChanged<String?> onTermChanged;

  const _TermSelector({
    required this.terms,
    required this.selectedTerm,
    required this.onTermChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey<String?>(selectedTerm),
      initialValue: selectedTerm,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '学期',
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
      menuMaxHeight: MediaQuery.sizeOf(context).height * .6,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部学期')),
        for (final term in terms)
          DropdownMenuItem<String?>(
            value: term,
            child: Text(term, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onTermChanged,
    );
  }
}

class _MaterialTermOverviewCard extends StatelessWidget {
  final List<String> terms;
  final String? selectedTerm;
  final ValueChanged<String?> onTermChanged;
  final AcademicTermSummary? summary;
  final String? weightedGpa;
  final int courseCount;

  const _MaterialTermOverviewCard({
    required this.terms,
    required this.selectedTerm,
    required this.onTermChanged,
    required this.summary,
    required this.weightedGpa,
    required this.courseCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasSummary = summary != null || weightedGpa != null;
    return Card(
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TermSelector(
              terms: terms,
              selectedTerm: selectedTerm,
              onTermChanged: onTermChanged,
            ),
            if (hasSummary) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 12),
              _TermSummaryCard(
                term: selectedTerm!,
                summary: summary,
                weightedGpa: weightedGpa,
                courseCount: courseCount,
                showCourseCount: false,
                showCalculationHint: true,
                embedded: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GradeSectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GradeSectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$count 门',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TermSummaryCard extends StatelessWidget {
  final String term;
  final AcademicTermSummary? summary;
  final String? weightedGpa;
  final int courseCount;
  final bool showCalculationHint;
  final bool showCourseCount;
  final bool embedded;

  const _TermSummaryCard({
    required this.term,
    required this.summary,
    required this.weightedGpa,
    required this.courseCount,
    this.showCalculationHint = false,
    this.showCourseCount = true,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = summary?.label ?? term;
    final child = Padding(
      padding:
          embedded
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!embedded)
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (showCourseCount)
                  Text(
                    '$courseCount 门',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          if (summary != null || weightedGpa != null) ...[
            SizedBox(height: embedded ? 0 : 9),
            Row(
              children: [
                _Metric(
                  label: '平均绩点',
                  value: academicValue(summary?.averageGpa ?? ''),
                  prominent: true,
                ),
                _Metric(
                  label: '加权绩点',
                  value: academicValue(weightedGpa ?? ''),
                  prominent: true,
                ),
                _Metric(
                  label: '学分',
                  value: academicValue(summary?.totalCredits ?? ''),
                ),
              ],
            ),
          ],
          if (showCalculationHint) ...[
            const SizedBox(height: 8),
            Text(
              '加权绩点按主修课程学分计算，已排除三类课程',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    if (embedded) return child;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _GradeListSection extends StatelessWidget {
  final List<AcademicCourseGrade> grades;

  final ValueChanged<AcademicCourseGrade>? onGradeTap;

  const _GradeListSection({required this.grades, this.onGradeTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < grades.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 66,
                endIndent: 14,
                color: colors.outlineVariant.withValues(alpha: 0.65),
              ),
            _CourseGradeRow(
              grade: grades[index],

              onTap:
                  onGradeTap == null ? null : () => onGradeTap!(grades[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourseGradeRow extends StatelessWidget {
  final AcademicCourseGrade grade;

  final VoidCallback? onTap;

  const _CourseGradeRow({required this.grade, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final score = academicValue(grade.finalScore);
    final isExcluded = AcademicWeightedGpaCalculator.isExcludedCategory(
      grade.category,
    );
    final metadata = [
      grade.courseCode,
      if (grade.credit.isNotEmpty) '${grade.credit} 学分',
    ].where((value) => value.isNotEmpty).join(' · ');
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final subtitleChildren = <Widget>[
      if (metadata.isNotEmpty) Text(metadata, style: secondaryStyle),
      if (grade.category.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  grade.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondaryStyle,
                ),
              ),
              if (isExcluded) ...[
                const SizedBox(width: 6),
                const _ExcludedCategoryTag(),
              ],
            ],
          ),
        ),
    ];
    final subtitle =
        subtitleChildren.isEmpty
            ? null
            : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: subtitleChildren,
            );
    void openDetails() {
      if (onTap != null) {
        onTap!();
        return;
      }
      unawaited(_showCourseGradeDetails(context, grade));
    }

    final rowKey = ValueKey<String>(_gradeRowKey(grade));

    return Semantics(
      container: true,
      button: true,
      label:
          '${grade.courseName.ifEmpty('未命名课程')}，成绩 $score，绩点 ${academicValue(grade.gradePoint)}',
      child: InkWell(
        key: rowKey,
        onTap: openDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _ScoreBadge(score: score),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      grade.courseName.ifEmpty('未命名课程'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      subtitle,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    academicValue(grade.gradePoint),
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '绩点',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExcludedCategoryTag extends StatelessWidget {
  const _ExcludedCategoryTag();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '不计入加权',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final String score;

  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final parsed = double.tryParse(score);
    final background = switch (parsed) {
      null => colors.surfaceContainerHighest,
      >= 90 => semantic.successContainer,
      >= 80 => semantic.infoContainer,
      >= 60 => semantic.warningContainer,
      _ => semantic.dangerContainer,
    };
    final foreground = switch (parsed) {
      null => colors.onSurfaceVariant,
      >= 90 => semantic.success,
      >= 80 => semantic.info,
      >= 60 => semantic.warning,
      _ => semantic.danger,
    };
    return SizedBox(
      width: 40,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            score.isEmpty ? '—' : score,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _MaterialGradeDetailHeader extends StatelessWidget {
  final AcademicCourseGrade grade;

  const _MaterialGradeDetailHeader({required this.grade});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '课程成绩',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                grade.courseName.ifEmpty('未命名课程'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          constraints: const BoxConstraints(minWidth: 76),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '总评',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                academicValue(grade.finalScore),
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GradeSummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _GradeSummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label $value'),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colors.onSecondaryContainer,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: colors.secondaryContainer,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _MaterialGradeDetailContent extends StatelessWidget {
  final AcademicCourseGrade grade;

  const _MaterialGradeDetailContent({required this.grade});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sections = _gradeDetailSections(grade);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MaterialGradeDetailHeader(grade: grade),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _GradeSummaryChip(
              label: '绩点',
              value: academicValue(grade.gradePoint),
            ),
            if (grade.credit.trim().isNotEmpty)
              _GradeSummaryChip(label: '学分', value: grade.credit),
          ],
        ),
        if (AcademicWeightedGpaCalculator.isExcludedCategory(
          grade.category,
        )) ...[
          const SizedBox(height: 4),
          const _ExcludedCategoryTag(),
        ],
        const SizedBox(height: 16),
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) Divider(height: 24, color: colors.outlineVariant),
          Text(
            sections[index].title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final item in sections[index].items)
            _GradeDetailLine(label: item.$1, value: item.$2),
        ],
      ],
    );
  }
}

class _GradeInspector extends StatelessWidget {
  final AcademicCourseGrade? grade;

  const _GradeInspector({required this.grade});

  @override
  Widget build(BuildContext context) {
    final current = grade;
    final background = Theme.of(context).colorScheme.surface;
    if (current == null) {
      final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
      return ColoredBox(
        color: background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 38, color: secondary),
              const SizedBox(height: 12),
              Text('选择一门课程查看成绩详情', style: TextStyle(color: secondary)),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      color: background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [_MaterialGradeDetailContent(grade: current)],
      ),
    );
  }
}

String _gradeRowKey(AcademicCourseGrade grade) =>
    'academic-grade-${grade.term}-${grade.courseSequence}-${grade.courseCode}-${grade.courseName}';

Future<void> _showCourseGradeDetails(
  BuildContext context,
  AcademicCourseGrade grade,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder:
        (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _MaterialGradeDetailContent(grade: grade),
          ),
        ),
  );
}

List<_GradeDetailSection> _gradeDetailSections(AcademicCourseGrade grade) {
  final courseItems = _nonEmptyGradeItems([
    ('课程代码', grade.courseCode),
    ('课程序号', grade.courseSequence),
    ('课程类别', grade.category),
    ('学分', grade.credit),
    ('教师', grade.teacher),
    ('记分制', grade.scoreSystem),
    ('备注', grade.note),
  ]);
  final scoreItems = _nonEmptyGradeItems([
    ('期中', grade.midtermScore),
    ('期末', grade.finalExamScore),
    ('平时', grade.usualScore),
    ('总评', grade.totalScore),
    ('实验', grade.labScore),
    ('最终', grade.finalScore),
    ('绩点', grade.gradePoint),
    ('补考', grade.makeupScore),
    ('重修', grade.retakeStatus),
  ]);
  return [
    if (courseItems.isNotEmpty)
      _GradeDetailSection(title: '课程信息', items: courseItems),
    if (scoreItems.isNotEmpty)
      _GradeDetailSection(title: '成绩明细', items: scoreItems),
  ];
}

List<(String, String)> _nonEmptyGradeItems(List<(String, String)> items) =>
    items.where((item) => item.$2.trim().isNotEmpty).toList(growable: false);

class _GradeDetailSection {
  final String title;
  final List<(String, String)> items;

  const _GradeDetailSection({required this.title, required this.items});
}

class _GradeDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _GradeDetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label：',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
