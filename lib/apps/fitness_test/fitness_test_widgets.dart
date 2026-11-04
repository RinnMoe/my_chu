import 'package:flutter/material.dart';

import 'fitness_test_models.dart';
import 'fitness_test_standard.dart';

/// 保留一位小数，与等级分界的一位小数口径一致。
String formatFitnessTestScore(double value) => value.toStringAsFixed(1);

const _tabular = [FontFeature.tabularFigures()];

/// 等级标记：不及格用错误色，其余用主色。
class FitnessTestGradeChip extends StatelessWidget {
  const FitnessTestGradeChip({
    super.key,
    required this.grade,
    this.compact = false,
  });

  final FitnessTestGrade grade;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failed = grade == FitnessTestGrade.fail;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: failed ? colors.errorContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 3,
        ),
        child: Text(
          grade.label,
          style: (compact
                  ? theme.textTheme.labelMedium
                  : theme.textTheme.labelLarge)
              ?.copyWith(
                color:
                    failed
                        ? colors.onErrorContainer
                        : colors.onPrimaryContainer,
              ),
        ),
      ),
    );
  }
}

/// 单项得分：不及格与满分的着色不同，便于在表格里扫读。
class FitnessTestScoreText extends StatelessWidget {
  const FitnessTestScoreText({
    super.key,
    required this.score,
    this.style,
    this.placeholder = '—',
  });

  final int? score;
  final TextStyle? style;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final score = this.score;
    final base = (style ?? theme.textTheme.bodyLarge)?.copyWith(
      fontFeatures: _tabular,
    );

    // 得分列宽固定，字号放大时缩小而不是折行。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child:
          score == null
              ? Text(
                placeholder,
                style: base?.copyWith(color: colors.onSurfaceVariant),
              )
              : Text(
                '$score',
                style: base?.copyWith(
                  color: switch (score) {
                    >= 90 => colors.primary,
                    >= 60 => colors.onSurface,
                    _ => colors.error,
                  },
                ),
              ),
    );
  }
}

/// 等级刻度：四段区间按分值占宽，标记线指出当前总分位置。
class FitnessTestScoreScale extends StatelessWidget {
  const FitnessTestScoreScale({
    super.key,
    required this.score,
    required this.grade,
  });

  final double score;
  final FitnessTestGrade grade;

  static const List<(FitnessTestGrade, int, String)> _bands = [
    (FitnessTestGrade.fail, 60, '不及格'),
    (FitnessTestGrade.pass, 20, '及格'),
    (FitnessTestGrade.good, 10, '良好'),
    (FitnessTestGrade.excellent, 30, '优秀'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const maximum = FitnessTestStandard.maximumTotalScore;
    final fraction = (score / maximum).clamp(0.0, 1.0);
    final bandColor = switch (grade) {
      FitnessTestGrade.fail => colors.error,
      FitnessTestGrade.pass => colors.tertiary,
      FitnessTestGrade.good => colors.secondary,
      FitnessTestGrade.excellent => colors.primary,
    };

    return Semantics(
      label: '总分 ${formatFitnessTestScore(score)}，满分 120，等级${grade.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const markerWidth = 3.0;
              return SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      top: 3,
                      bottom: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (band, flex, _) in _bands)
                              Expanded(
                                flex: flex,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: bandColor.withValues(
                                      alpha: band == grade ? 0.95 : 0.22,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (constraints.maxWidth - markerWidth) * fraction,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: markerWidth,
                        decoration: BoxDecoration(
                          color: colors.onSurface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (_, flex, label) in _bands)
                Expanded(
                  flex: flex,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 常驻结果条：输入过程中始终可见当前总分与等级，点按展开明细。
class FitnessTestResultBar extends StatelessWidget {
  const FitnessTestResultBar({
    super.key,
    required this.result,
    required this.hasProfile,
    required this.totalItems,
    this.onOpenResult,
  });

  final FitnessTestResult result;
  final bool hasProfile;
  final int totalItems;
  final VoidCallback? onOpenResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = result.totalScore;
    final grade = result.grade;
    final ready = total != null && grade != null;

    final Widget leading;
    if (!hasProfile) {
      leading = Text(
        '先选择性别与年级',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    } else if (!ready) {
      leading = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            '${result.scoredItemCount} / $totalItems',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: _tabular,
            ),
          ),
          Text(
            '项已填',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      );
    } else {
      leading = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            formatFitnessTestScore(total),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: _tabular,
            ),
          ),
          FitnessTestGradeChip(grade: grade, compact: true),
        ],
      );
    }

    return Material(
      color: colors.surfaceContainer,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: InkWell(
            onTap: ready ? onOpenResult : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(child: leading),
                    if (ready) ...[
                      const SizedBox(width: 12),
                      Text(
                        '明细',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 结果面板：总分、等级刻度、提升空间与计分明细。
Future<void> showFitnessTestResultSheet(
  BuildContext context, {
  required FitnessTestResult result,
  required FitnessTestGender gender,
  required FitnessTestGradeGroup gradeGroup,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (_) => _ResultSheet(
          result: result,
          gender: gender,
          gradeGroup: gradeGroup,
        ),
  );
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.result,
    required this.gender,
    required this.gradeGroup,
  });

  final FitnessTestResult result;
  final FitnessTestGender gender;
  final FitnessTestGradeGroup gradeGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final total = result.totalScore ?? 0;
    final grade = result.grade ?? FitnessTestGrade.fail;

    final headroom =
        <(FitnessTestItem, double)>[
            for (final item in result.items)
              if (item.score != null)
                (
                  item.item,
                  (100 - item.score!) * item.item.weightPercent / 100,
                ),
          ].where((entry) => entry.$2 > 0).toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Text(
                  formatFitnessTestScore(total),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(width: 10),
                FitnessTestGradeChip(grade: grade),
              ],
            ),
            const SizedBox(height: 14),
            FitnessTestScoreScale(score: total, grade: grade),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _MetricText(
                  label: '标准分',
                  value: formatFitnessTestScore(result.standardScore ?? 0),
                ),
                _MetricText(
                  label: '附加分',
                  value:
                      result.bonusScore == 0
                          ? formatFitnessTestScore(0)
                          : '+${formatFitnessTestScore(result.bonusScore.toDouble())}',
                ),
                const _MetricText(label: '满分', value: '120'),
              ],
            ),
            if (headroom.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('提升空间', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('单项拉满还能增加的分值', style: muted),
              const SizedBox(height: 6),
              for (final (item, gain) in headroom.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label(gender),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '+${formatFitnessTestScore(gain)} 分',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.primary,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 22),
            Text('计分明细', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            _BreakdownTable(result: result, gender: gender),
            const SizedBox(height: 22),
            Text(
              '使用${gradeGroup.label}评分表。依据《国家学生体质健康标准'
              '（2014 年修订）》；实际成绩与等级以学校组织测试和认定结果为准。',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          TextSpan(
            text: value,
            style: theme.textTheme.labelLarge?.copyWith(fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

/// 计分明细：单项得分、权重与加权分，附加分单列在表格之后。
class _BreakdownTable extends StatelessWidget {
  const _BreakdownTable({required this.result, required this.gender});

  final FitnessTestResult result;
  final FitnessTestGender gender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final header = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final cell = theme.textTheme.bodyMedium;

    Widget row({
      required Widget name,
      required Widget score,
      required Widget weight,
      required Widget weighted,
    }) {
      return Row(
        children: [
          Expanded(flex: 4, child: name),
          Expanded(flex: 2, child: score),
          Expanded(flex: 2, child: weight),
          Expanded(flex: 3, child: weighted),
        ],
      );
    }

    final bonusItems = result.items
        .where((item) => item.item.isBonusItem)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          name: Text('单项', style: header),
          score: Text('得分', textAlign: TextAlign.end, style: header),
          weight: Text('权重', textAlign: TextAlign.end, style: header),
          weighted: Text('加权分', textAlign: TextAlign.end, style: header),
        ),
        for (final item in result.items)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: row(
              name: Text(
                item.item.label(gender),
                style: cell,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              score: FitnessTestScoreText(score: item.score, style: cell),
              weight: Text(
                '${item.item.weightPercent}%',
                textAlign: TextAlign.end,
                style: cell?.copyWith(color: colors.onSurfaceVariant),
              ),
              weighted: Text(
                item.weightedScore == null
                    ? '—'
                    : item.weightedScore!.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: cell?.copyWith(fontFeatures: _tabular),
              ),
            ),
          ),
        if (bonusItems.any((item) => item.bonus > 0)) ...[
          const SizedBox(height: 10),
          Divider(color: colors.outlineVariant, height: 1),
          for (final item in bonusItems)
            if (item.bonus > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '附加 · ${item.item.label(gender)}',
                        style: cell,
                      ),
                    ),
                    Text(
                      '+${item.bonus}',
                      style: cell?.copyWith(fontFeatures: _tabular),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}

/// 评分标准：权重、等级分界、加分规则与依据。
Future<void> showFitnessTestStandardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _StandardSheet(),
  );
}

class _StandardSheet extends StatelessWidget {
  const _StandardSheet();

  static const List<(String, int)> _weights = [
    ('体重指数（BMI）', 15),
    ('肺活量', 15),
    ('50 米跑', 20),
    ('坐位体前屈', 10),
    ('立定跳远', 10),
    ('引体向上 / 一分钟仰卧起坐', 10),
    ('1000 米跑 / 800 米跑', 20),
  ];

  static const List<(String, String)> _grades = [
    ('优秀', '90.0 分及以上'),
    ('良好', '80.0 ～ 89.9 分'),
    ('及格', '60.0 ～ 79.9 分'),
    ('不及格', '59.9 分及以下'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = theme.textTheme.bodyMedium;
    final muted = body?.copyWith(color: colors.onSurfaceVariant);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('单项与权重', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (label, weight) in _weights)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: body)),
                    Text(
                      '$weight%',
                      style: body?.copyWith(fontFeatures: _tabular),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text('等级', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (label, range) in _grades)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: body)),
                    Text(range, style: muted),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text('加分', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '男生：引体向上、1000 米跑；女生：一分钟仰卧起坐、800 米跑。'
              '成绩超过该项 100 分标准后按次数或秒数加分，每项最多 10 分，'
              '学年总分满分 120 分。',
              style: muted,
            ),
            const SizedBox(height: 20),
            Text(
              '依据《国家学生体质健康标准（2014 年修订）》大学阶段评分表。'
              '实际成绩与等级以学校组织测试和认定结果为准。',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}
