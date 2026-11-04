import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mychu/widgets/adaptive_confirmation_dialog.dart';

import 'fitness_test_grade_hint.dart';
import 'fitness_test_models.dart';
import 'fitness_test_standard.dart';
import 'fitness_test_widgets.dart';

/// 体测计算器：按标准评分表把身高体重与各项成绩换算成单项得分、
/// 标准分、附加分与学年总分等级。
///
/// 页面结构是「身份 → 一张成绩表 → 常驻结果条」：输入过程中结果条始终
/// 可见，计分明细放在结果面板里，避免同一屏重复展示分值。
/// 只做本地计算，不缓存也不上传身高、体重与成绩。
class FitnessTestPage extends StatefulWidget {
  const FitnessTestPage({super.key});

  @override
  State<FitnessTestPage> createState() => _FitnessTestPageState();
}

/// 输入允许范围：超出后按未填写处理，避免把明显误输当成成绩。
class _FieldRange {
  const _FieldRange(this.min, this.max);

  final double min;
  final double max;

  bool contains(double value) => value >= min && value <= max;
}

class _FitnessTestPageState extends State<FitnessTestPage> {
  static const _heightRange = _FieldRange(100, 250);
  static const _weightRange = _FieldRange(20, 200);
  static const _vitalCapacityRange = _FieldRange(500, 9999);
  static const _sprintRange = _FieldRange(4, 20);
  static const _sitAndReachRange = _FieldRange(-30, 40);
  static const _jumpRange = _FieldRange(50, 400);
  static const _strengthRange = _FieldRange(0, 200);
  static const _enduranceMinutesRange = _FieldRange(0, 30);
  static const _enduranceSecondsRange = _FieldRange(0, 59);

  static const _scoreWidth = 56.0;

  FitnessTestGender? _gender;
  FitnessTestGradeYear? _gradeYear;

  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _vitalCapacity = TextEditingController();
  final _sprint = TextEditingController();
  final _sitAndReach = TextEditingController();
  final _jump = TextEditingController();
  final _strength = TextEditingController();
  final _enduranceMinutes = TextEditingController();
  final _enduranceSeconds = TextEditingController();

  late final List<TextEditingController> _controllers = [
    _height,
    _weight,
    _vitalCapacity,
    _sprint,
    _sitAndReach,
    _jump,
    _strength,
    _enduranceMinutes,
    _enduranceSeconds,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_onFieldChanged);
    }
    unawaited(_applyDetectedGradeGroup());
  }

  /// 用本机已回填的学号推算年级组；用户在结果返回前已改选时不覆盖。
  Future<void> _applyDetectedGradeGroup() async {
    final detected = await detectCurrentGradeYear();
    if (!mounted || detected == null || _gradeYear != null) return;
    setState(() => _gradeYear = detected);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  FitnessTestInput get _input => FitnessTestInput(
    gender: _gender,
    gradeGroup: _gradeYear?.gradeGroup,
    heightCm: _readValue(_height, _heightRange),
    weightKg: _readValue(_weight, _weightRange),
    vitalCapacityMl: _readValue(_vitalCapacity, _vitalCapacityRange)?.round(),
    sprint50mSeconds: _readValue(_sprint, _sprintRange),
    sitAndReachCm: _readValue(_sitAndReach, _sitAndReachRange),
    standingJumpCm: _readValue(_jump, _jumpRange),
    upperStrengthCount: _readValue(_strength, _strengthRange)?.round(),
    enduranceRunSeconds: _readEnduranceSeconds(),
  );

  double? _readValue(TextEditingController controller, _FieldRange range) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !range.contains(value)) return null;
    return value;
  }

  int? _readEnduranceSeconds() {
    final minutes = _readValue(_enduranceMinutes, _enduranceMinutesRange);
    final seconds = _readValue(_enduranceSeconds, _enduranceSecondsRange);
    if (minutes == null && seconds == null) return null;
    final total = ((minutes ?? 0) * 60 + (seconds ?? 0)).round();
    return total <= 0 ? null : total;
  }

  /// 只在输入非空且越界时给出可接受的区间。
  String? _rangeError(
    TextEditingController controller,
    _FieldRange range,
    String unit,
  ) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value != null && range.contains(value)) return null;
    return '${_trimZero(range.min)}–${_trimZero(range.max)} $unit';
  }

  String _trimZero(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  bool get _hasAnyInput =>
      _gender != null ||
      _gradeYear != null ||
      _controllers.any((controller) => controller.text.trim().isNotEmpty);

  Future<void> _confirmReset() async {
    if (!_hasAnyInput) return;
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '清空全部输入？',
      message: '性别、年级与所有成绩都会被清除。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    FocusScope.of(context).unfocus();
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _gender = null;
      _gradeYear = null;
    });
    unawaited(_applyDetectedGradeGroup());
  }

  @override
  Widget build(BuildContext context) {
    final input = _input;
    final result = FitnessTestStandard.evaluate(input);
    final gender = _gender;

    return Scaffold(
      appBar: AppBar(
        title: const Text('体测计算器'),
        actions: [
          IconButton(
            tooltip: '评分标准',
            onPressed: () => showFitnessTestStandardSheet(context),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _hasAnyInput ? _confirmReset : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      _buildIdentityBar(),
                      const SizedBox(height: 8),
                      _buildMetricTable(result, gender),
                    ],
                  ),
                ),
              ),
            ),
            FitnessTestResultBar(
              result: result,
              hasProfile: input.hasProfile,
              totalItems: FitnessTestItem.values.length,
              onOpenResult:
                  result.isComplete && gender != null
                      ? () => showFitnessTestResultSheet(
                        context,
                        result: result,
                        gender: gender,
                        gradeGroup: _gradeYear!.gradeGroup,
                      )
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 两组连胶囊：左侧是维度名，胶囊右对齐贴住页面右缘。
  ///
  /// 年级可能是按学号推算出来的初始值，用户随时可以改选；评分表仍按
  /// 大一·大二 / 大三·大四两组合并计算。
  Widget _buildIdentityBar() {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      children: [
        _identityRow(
          '性别',
          labelStyle,
          SegmentedButton<FitnessTestGender>(
            showSelectedIcon: false,
            segments: [
              for (final gender in FitnessTestGender.values)
                ButtonSegment(value: gender, label: Text(gender.label)),
            ],
            selected: _gender == null ? const {} : {_gender!},
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) {
              setState(() {
                _gender = selection.isEmpty ? null : selection.first;
              });
            },
          ),
        ),
        const SizedBox(height: 4),
        _identityRow(
          '年级',
          labelStyle,
          SegmentedButton<FitnessTestGradeYear>(
            showSelectedIcon: false,
            segments: [
              for (final year in FitnessTestGradeYear.values)
                ButtonSegment(value: year, label: Text(year.label)),
            ],
            selected: _gradeYear == null ? const {} : {_gradeYear!},
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) {
              setState(() {
                _gradeYear = selection.isEmpty ? null : selection.first;
              });
            },
          ),
        ),
      ],
    );
  }

  /// 维度名贴左、胶囊贴右；宽度实在不够时胶囊等比缩小，不折行也不溢出。
  Widget _identityRow(String label, TextStyle? labelStyle, Widget control) {
    return Row(
      children: [
        Text(label, style: labelStyle),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: control,
            ),
          ),
        ),
      ],
    );
  }

  /// 一张表装完全部指标：身高体重与 BMI 在前，其余按标准顺序排列。
  Widget _buildMetricTable(
    FitnessTestResult result,
    FitnessTestGender? gender,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final header = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('指标', style: header)),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: Text('成绩', style: header)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: _scoreWidth,
                    child: Text('得分', textAlign: TextAlign.end, style: header),
                  ),
                ],
              ),
            ),
            _metricRow(
              name: '身高',
              score: null,
              field: _numberField(
                controller: _height,
                semanticsLabel: '身高',
                unit: 'cm',
                range: _heightRange,
              ),
            ),
            _metricRow(
              name: '体重',
              score: null,
              field: _numberField(
                controller: _weight,
                semanticsLabel: '体重',
                unit: 'kg',
                range: _weightRange,
              ),
            ),
            _metricRow(
              name: '体重指数',
              score: result.resultFor(FitnessTestItem.bmi)?.score,
              field: _bmiValue(result),
            ),
            _metricRow(
              name: '肺活量',
              score: result.resultFor(FitnessTestItem.vitalCapacity)?.score,
              field: _numberField(
                controller: _vitalCapacity,
                semanticsLabel: '肺活量',
                unit: 'ml',
                range: _vitalCapacityRange,
                integer: true,
              ),
            ),
            _metricRow(
              name: '50 米跑',
              score: result.resultFor(FitnessTestItem.sprint50m)?.score,
              field: _numberField(
                controller: _sprint,
                semanticsLabel: '50 米跑',
                unit: '秒',
                range: _sprintRange,
              ),
            ),
            _metricRow(
              name: '坐位体前屈',
              score: result.resultFor(FitnessTestItem.sitAndReach)?.score,
              field: _numberField(
                controller: _sitAndReach,
                semanticsLabel: '坐位体前屈',
                unit: '厘米',
                range: _sitAndReachRange,
                allowNegative: true,
              ),
            ),
            _metricRow(
              name: '立定跳远',
              score: result.resultFor(FitnessTestItem.standingJump)?.score,
              field: _numberField(
                controller: _jump,
                semanticsLabel: '立定跳远',
                unit: '厘米',
                range: _jumpRange,
                integer: true,
              ),
            ),
            _metricRow(
              name:
                  gender == null
                      ? '引体/仰卧'
                      : FitnessTestItem.upperStrength.label(gender),
              score: result.resultFor(FitnessTestItem.upperStrength)?.score,
              field: _numberField(
                controller: _strength,
                semanticsLabel:
                    gender == null
                        ? '引体向上或仰卧起坐次数'
                        : FitnessTestItem.upperStrength.label(gender),
                unit: '次',
                range: _strengthRange,
                integer: true,
              ),
            ),
            _metricRow(
              name:
                  gender == null
                      ? '耐力跑'
                      : FitnessTestItem.enduranceRun.label(gender),
              score: result.resultFor(FitnessTestItem.enduranceRun)?.score,
              field: _enduranceField(gender),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow({
    required String name,
    required Widget field,
    required int? score,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(name, style: theme.textTheme.bodyMedium, maxLines: 2),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: field),
          const SizedBox(width: 8),
          SizedBox(
            width: _scoreWidth,
            child: FitnessTestScoreText(score: score),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String semanticsLabel,
    required String unit,
    required _FieldRange range,
    bool integer = false,
    bool allowNegative = false,
  }) {
    final theme = Theme.of(context);
    final pattern =
        allowNegative
            ? RegExp(r'[0-9.\-]')
            : integer
            ? RegExp(r'[0-9]')
            : RegExp(r'[0-9.]');

    return Semantics(
      label: semanticsLabel,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !integer,
          signed: allowNegative,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(pattern),
          LengthLimitingTextInputFormatter(6),
        ],
        textInputAction: TextInputAction.next,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixText: unit,
          suffixStyle: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          errorText: _rangeError(controller, range, unit),
        ),
      ),
    );
  }

  /// 耐力跑用分与秒两格输入，成绩按合计秒数计算。
  Widget _enduranceField(FitnessTestGender? gender) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label:
                gender == null
                    ? '耐力跑分钟'
                    : '${FitnessTestItem.enduranceRun.label(gender)}分钟',
            child: TextField(
              controller: _enduranceMinutes,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                LengthLimitingTextInputFormatter(2),
              ],
              textInputAction: TextInputAction.next,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                suffixText: '分',
                suffixStyle: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                errorText: _enduranceError(_enduranceMinutes),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            label: '耐力跑秒',
            child: TextField(
              controller: _enduranceSeconds,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                LengthLimitingTextInputFormatter(2),
              ],
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                suffixText: '秒',
                suffixStyle: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                errorText: _enduranceError(_enduranceSeconds),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? _enduranceError(TextEditingController controller) {
    final isMinutes = controller == _enduranceMinutes;
    final range = isMinutes ? _enduranceMinutesRange : _enduranceSecondsRange;
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value != null && range.contains(value)) return null;
    return '0–${_trimZero(range.max)}';
  }

  /// 体重指数由身高体重导出，和输入行共用同一列位置。
  Widget _bmiValue(FitnessTestResult result) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bmi = result.bmi;
    final band = result.bmiBand;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerRight,
        // 大字体下指数与区间换行，而不是挤压成一列。
        child:
            bmi == null
                ? Text(
                  '自动计算',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
                : Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      bmi.toStringAsFixed(1),
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (band != null)
                      Text(
                        band.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}
