import 'fitness_test_models.dart';

/// 《国家学生体质健康标准（2014 年修订）》大学阶段的评分规则。
///
/// 数据来自标准附表「大学男生评分标准」「大学女生评分标准」
/// 「体重指数评分表」与「加分指标评分表」。评分表按大一·大二与
/// 大三·大四两列给出成绩门槛，因此每个指标带两列阈值。
abstract final class FitnessTestStandard {
  /// 标准分满分：各单项得分与权重乘积之和。
  static const double maximumStandardScore = 100;

  /// 附加分满分：男生的引体向上与 1000 米跑、女生的仰卧起坐与 800 米跑，
  /// 每项最多 10 分。
  static const int maximumBonusScore = 20;

  /// 学年总分满分。
  static const double maximumTotalScore = 120;

  /// 单项附加分的上限。
  static const int maximumItemBonus = 10;

  /// 男生 1000 米跑加分档要求的提速秒数，下标加一即加分值。
  static const List<int> _run1000BonusSteps = [
    4,
    8,
    12,
    16,
    20,
    23,
    26,
    29,
    32,
    35,
  ];

  /// 女生一分钟仰卧起坐加分档要求超过 100 分标准的次数。
  static const List<int> _sitUpBonusSteps = [2, 4, 6, 7, 8, 9, 10, 11, 12, 13];

  /// 女生 800 米跑加分档要求的提速秒数。
  static const List<int> _run800BonusSteps = [
    5,
    10,
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
  ];

  /// 按身高体重计算体重指数，保留一位小数。
  ///
  /// 标准用 17.9～23.9 这类一位小数的区间描述等级，所以先统一到一位小数
  /// 再判档，避免 23.95 既不属于正常也不属于超重。
  static double bmiFor({required double heightCm, required double weightKg}) {
    final meters = heightCm / 100;
    return _roundToTenth(weightKg / (meters * meters));
  }

  /// 体重指数区间；男女的正常区间下界不同（17.9 与 17.2）。
  static FitnessTestBmiBand bmiBandFor(
    double bmi, {
    required FitnessTestGender gender,
  }) {
    final lowWeightCeiling = gender == FitnessTestGender.male ? 17.8 : 17.1;
    if (bmi <= lowWeightCeiling) return FitnessTestBmiBand.lowWeight;
    if (bmi <= 23.9) return FitnessTestBmiBand.normal;
    if (bmi <= 27.9) return FitnessTestBmiBand.overweight;
    return FitnessTestBmiBand.obese;
  }

  /// 体重指数得分：正常 100，低体重与超重 80，肥胖 60。
  static int bmiScoreFor(FitnessTestBmiBand band) {
    return switch (band) {
      FitnessTestBmiBand.normal => 100,
      FitnessTestBmiBand.lowWeight || FitnessTestBmiBand.overweight => 80,
      FitnessTestBmiBand.obese => 60,
    };
  }

  /// 计算整套结果。缺项或未选性别/年级时对应单项没有得分，
  /// 此时总分为 null 而不是把缺项当成 0 分。
  static FitnessTestResult evaluate(FitnessTestInput input) {
    final gender = input.gender;
    final gradeGroup = input.gradeGroup;
    final heightCm = input.heightCm;
    final weightKg = input.weightKg;

    final hasBodyMetrics =
        heightCm != null && weightKg != null && heightCm > 0 && weightKg > 0;
    final bmi =
        hasBodyMetrics ? bmiFor(heightCm: heightCm, weightKg: weightKg) : null;
    // 区间的下界按性别区分，未选性别时只能给出指数本身。
    final band =
        bmi == null || gender == null ? null : bmiBandFor(bmi, gender: gender);

    final items = <FitnessTestItemResult>[
      FitnessTestItemResult(
        item: FitnessTestItem.bmi,
        value: bmi,
        score: band == null ? null : bmiScoreFor(band),
        bmiBand: band,
      ),
      _scoreItem(
        FitnessTestItem.vitalCapacity,
        input.vitalCapacityMl?.toDouble(),
        gender: gender,
        gradeGroup: gradeGroup,
      ),
      _scoreItem(
        FitnessTestItem.sprint50m,
        input.sprint50mSeconds,
        gender: gender,
        gradeGroup: gradeGroup,
      ),
      _scoreItem(
        FitnessTestItem.sitAndReach,
        input.sitAndReachCm,
        gender: gender,
        gradeGroup: gradeGroup,
      ),
      _scoreItem(
        FitnessTestItem.standingJump,
        input.standingJumpCm,
        gender: gender,
        gradeGroup: gradeGroup,
      ),
      _scoreItem(
        FitnessTestItem.upperStrength,
        input.upperStrengthCount?.toDouble(),
        gender: gender,
        gradeGroup: gradeGroup,
      ),
      _scoreItem(
        FitnessTestItem.enduranceRun,
        input.enduranceRunSeconds?.toDouble(),
        gender: gender,
        gradeGroup: gradeGroup,
      ),
    ];

    var rawStandardScore = 0.0;
    var bonusScore = 0;
    var scoredCount = 0;
    for (final item in items) {
      final weighted = item.weightedScore;
      if (weighted != null) {
        scoredCount += 1;
        rawStandardScore += weighted;
      }
      bonusScore += item.bonus;
    }

    final isComplete = scoredCount == items.length;
    // 权重之和为 100、加分指标只有两项，天然不会超过满分；上限只作为
    // 表格被改坏时的兜底，避免把错误数据当成合法总分。
    final standardScore =
        isComplete
            ? _roundToTenth(
              rawStandardScore,
            ).clamp(0, maximumStandardScore).toDouble()
            : null;
    final totalScore =
        standardScore == null
            ? null
            : _roundToTenth(standardScore + bonusScore);

    return FitnessTestResult(
      items: items,
      standardScore: standardScore,
      bonusScore: isComplete ? bonusScore.clamp(0, maximumBonusScore) : 0,
      totalScore: totalScore,
      grade: totalScore == null ? null : FitnessTestGrade.forScore(totalScore),
      bmi: bmi,
      bmiBand: band,
    );
  }

  static FitnessTestItemResult _scoreItem(
    FitnessTestItem item,
    double? value, {
    required FitnessTestGender? gender,
    required FitnessTestGradeGroup? gradeGroup,
  }) {
    if (value == null) return FitnessTestItemResult(item: item);
    if (gender == null || gradeGroup == null) {
      return FitnessTestItemResult(item: item, value: value);
    }
    return FitnessTestItemResult(
      item: item,
      value: value,
      score: scoreFor(
        item,
        value: value,
        gender: gender,
        gradeGroup: gradeGroup,
      ),
      bonus: bonusFor(
        item,
        value: value,
        gender: gender,
        gradeGroup: gradeGroup,
      ),
    );
  }

  /// 取该指标已达到的最高单项得分；低于最低门槛时记 0 分。
  ///
  /// 时间类指标按低优处理，其余按高优处理，与标准表的门槛方向一致。
  static int scoreFor(
    FitnessTestItem item, {
    required double value,
    required FitnessTestGender gender,
    required FitnessTestGradeGroup gradeGroup,
  }) {
    final rows = switch (item) {
      FitnessTestItem.bmi => const <_ScoreRow>[],
      FitnessTestItem.vitalCapacity =>
        gender == FitnessTestGender.male
            ? _maleVitalCapacity
            : _femaleVitalCapacity,
      FitnessTestItem.sprint50m =>
        gender == FitnessTestGender.male ? _maleSprint50m : _femaleSprint50m,
      FitnessTestItem.sitAndReach =>
        gender == FitnessTestGender.male
            ? _maleSitAndReach
            : _femaleSitAndReach,
      FitnessTestItem.standingJump =>
        gender == FitnessTestGender.male
            ? _maleStandingJump
            : _femaleStandingJump,
      FitnessTestItem.upperStrength =>
        gender == FitnessTestGender.male
            ? _maleUpperStrength
            : _femaleUpperStrength,
      FitnessTestItem.enduranceRun =>
        gender == FitnessTestGender.male
            ? _maleEnduranceRun
            : _femaleEnduranceRun,
    };

    for (final row in rows) {
      final threshold =
          gradeGroup == FitnessTestGradeGroup.lower
              ? row.lowerGrade
              : row.upperGrade;
      final reached =
          item.isLowerValueBetter ? value <= threshold : value >= threshold;
      if (reached) return row.score;
    }
    return 0;
  }

  /// 加分只来自两项加分指标，且必须先达到该项的 100 分标准。
  static int bonusFor(
    FitnessTestItem item, {
    required double value,
    required FitnessTestGender gender,
    required FitnessTestGradeGroup gradeGroup,
  }) {
    if (!item.isBonusItem) return 0;
    final achieved = value.round();
    final isMale = gender == FitnessTestGender.male;

    if (item == FitnessTestItem.upperStrength) {
      if (isMale) {
        // 引体向上每多拉一次加 1 分。
        final extra = achieved - _pullUpStandardCount(gradeGroup);
        if (extra <= 0) return 0;
        return extra > maximumItemBonus ? maximumItemBonus : extra;
      }
      // 仰卧起坐的加分档不是等距的，按标准表逐档判断。
      final extra = achieved - _sitUpStandardCount(gradeGroup);
      return _stepBonus(extra, _sitUpBonusSteps);
    }

    final standardSeconds =
        isMale
            ? _run1000StandardSeconds(gradeGroup)
            : _run800StandardSeconds(gradeGroup);
    final savedSeconds = standardSeconds - achieved;
    return _stepBonus(
      savedSeconds,
      isMale ? _run1000BonusSteps : _run800BonusSteps,
    );
  }

  static int _stepBonus(int extra, List<int> steps) {
    if (extra <= 0) return 0;
    var bonus = 0;
    for (var index = 0; index < steps.length; index += 1) {
      if (extra < steps[index]) break;
      bonus = index + 1;
    }
    return bonus;
  }

  /// 男生引体向上 100 分标准：大一·大二 19 次，大三·大四 20 次。
  static int _pullUpStandardCount(FitnessTestGradeGroup gradeGroup) {
    return gradeGroup == FitnessTestGradeGroup.lower ? 19 : 20;
  }

  /// 女生一分钟仰卧起坐 100 分标准：大一·大二 56 次，大三·大四 57 次。
  static int _sitUpStandardCount(FitnessTestGradeGroup gradeGroup) {
    return gradeGroup == FitnessTestGradeGroup.lower ? 56 : 57;
  }

  /// 男生 1000 米跑 100 分标准：大一·大二 3'17"，大三·大四 3'15"。
  static int _run1000StandardSeconds(FitnessTestGradeGroup gradeGroup) {
    return gradeGroup == FitnessTestGradeGroup.lower ? 197 : 195;
  }

  /// 女生 800 米跑 100 分标准：大一·大二 3'18"，大三·大四 3'16"。
  static int _run800StandardSeconds(FitnessTestGradeGroup gradeGroup) {
    return gradeGroup == FitnessTestGradeGroup.lower ? 198 : 196;
  }

  static double _roundToTenth(double value) =>
      (value * 10).roundToDouble() / 10;

  /// 大学男生 肺活量（毫升）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _maleVitalCapacity = [
    _ScoreRow(100, 5040, 5140),
    _ScoreRow(95, 4920, 5020),
    _ScoreRow(90, 4800, 4900),
    _ScoreRow(85, 4550, 4650),
    _ScoreRow(80, 4300, 4400),
    _ScoreRow(78, 4180, 4280),
    _ScoreRow(76, 4060, 4160),
    _ScoreRow(74, 3940, 4040),
    _ScoreRow(72, 3820, 3920),
    _ScoreRow(70, 3700, 3800),
    _ScoreRow(68, 3580, 3680),
    _ScoreRow(66, 3460, 3560),
    _ScoreRow(64, 3340, 3440),
    _ScoreRow(62, 3220, 3320),
    _ScoreRow(60, 3100, 3200),
    _ScoreRow(50, 2940, 3030),
    _ScoreRow(40, 2780, 2860),
    _ScoreRow(30, 2620, 2690),
    _ScoreRow(20, 2460, 2520),
    _ScoreRow(10, 2300, 2350),
  ];

  /// 大学女生 肺活量（毫升）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _femaleVitalCapacity = [
    _ScoreRow(100, 3400, 3450),
    _ScoreRow(95, 3350, 3400),
    _ScoreRow(90, 3300, 3350),
    _ScoreRow(85, 3150, 3200),
    _ScoreRow(80, 3000, 3050),
    _ScoreRow(78, 2900, 2950),
    _ScoreRow(76, 2800, 2850),
    _ScoreRow(74, 2700, 2750),
    _ScoreRow(72, 2600, 2650),
    _ScoreRow(70, 2500, 2550),
    _ScoreRow(68, 2400, 2450),
    _ScoreRow(66, 2300, 2350),
    _ScoreRow(64, 2200, 2250),
    _ScoreRow(62, 2100, 2150),
    _ScoreRow(60, 2000, 2050),
    _ScoreRow(50, 1960, 2010),
    _ScoreRow(40, 1920, 1970),
    _ScoreRow(30, 1880, 1930),
    _ScoreRow(20, 1840, 1890),
    _ScoreRow(10, 1800, 1850),
  ];

  /// 大学男生 50 米跑（秒）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _maleSprint50m = [
    _ScoreRow(100, 6.7, 6.6),
    _ScoreRow(95, 6.8, 6.7),
    _ScoreRow(90, 6.9, 6.8),
    _ScoreRow(85, 7, 6.9),
    _ScoreRow(80, 7.1, 7),
    _ScoreRow(78, 7.3, 7.2),
    _ScoreRow(76, 7.5, 7.4),
    _ScoreRow(74, 7.7, 7.6),
    _ScoreRow(72, 7.9, 7.8),
    _ScoreRow(70, 8.1, 8),
    _ScoreRow(68, 8.3, 8.2),
    _ScoreRow(66, 8.5, 8.4),
    _ScoreRow(64, 8.7, 8.6),
    _ScoreRow(62, 8.9, 8.8),
    _ScoreRow(60, 9.1, 9),
    _ScoreRow(50, 9.3, 9.2),
    _ScoreRow(40, 9.5, 9.4),
    _ScoreRow(30, 9.7, 9.6),
    _ScoreRow(20, 9.9, 9.8),
    _ScoreRow(10, 10.1, 10),
  ];

  /// 大学女生 50 米跑（秒）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _femaleSprint50m = [
    _ScoreRow(100, 7.5, 7.4),
    _ScoreRow(95, 7.6, 7.5),
    _ScoreRow(90, 7.7, 7.6),
    _ScoreRow(85, 8, 7.9),
    _ScoreRow(80, 8.3, 8.2),
    _ScoreRow(78, 8.5, 8.4),
    _ScoreRow(76, 8.7, 8.6),
    _ScoreRow(74, 8.9, 8.8),
    _ScoreRow(72, 9.1, 9),
    _ScoreRow(70, 9.3, 9.2),
    _ScoreRow(68, 9.5, 9.4),
    _ScoreRow(66, 9.7, 9.6),
    _ScoreRow(64, 9.9, 9.8),
    _ScoreRow(62, 10.1, 10),
    _ScoreRow(60, 10.3, 10.2),
    _ScoreRow(50, 10.5, 10.4),
    _ScoreRow(40, 10.7, 10.6),
    _ScoreRow(30, 10.9, 10.8),
    _ScoreRow(20, 11.1, 11),
    _ScoreRow(10, 11.3, 11.2),
  ];

  /// 大学男生 坐位体前屈（厘米）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _maleSitAndReach = [
    _ScoreRow(100, 24.9, 25.1),
    _ScoreRow(95, 23.1, 23.3),
    _ScoreRow(90, 21.3, 21.5),
    _ScoreRow(85, 19.5, 19.9),
    _ScoreRow(80, 17.7, 18.2),
    _ScoreRow(78, 16.3, 16.8),
    _ScoreRow(76, 14.9, 15.4),
    _ScoreRow(74, 13.5, 14),
    _ScoreRow(72, 12.1, 12.6),
    _ScoreRow(70, 10.7, 11.2),
    _ScoreRow(68, 9.3, 9.8),
    _ScoreRow(66, 7.9, 8.4),
    _ScoreRow(64, 6.5, 7),
    _ScoreRow(62, 5.1, 5.6),
    _ScoreRow(60, 3.7, 4.2),
    _ScoreRow(50, 2.7, 3.2),
    _ScoreRow(40, 1.7, 2.2),
    _ScoreRow(30, 0.7, 1.2),
    _ScoreRow(20, -0.3, 0.2),
    _ScoreRow(10, -1.3, -0.8),
  ];

  /// 大学女生 坐位体前屈（厘米）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _femaleSitAndReach = [
    _ScoreRow(100, 25.8, 26.3),
    _ScoreRow(95, 24, 24.4),
    _ScoreRow(90, 22.2, 22.4),
    _ScoreRow(85, 20.6, 21),
    _ScoreRow(80, 19, 19.5),
    _ScoreRow(78, 17.7, 18.2),
    _ScoreRow(76, 16.4, 16.9),
    _ScoreRow(74, 15.1, 15.6),
    _ScoreRow(72, 13.8, 14.3),
    _ScoreRow(70, 12.5, 13),
    _ScoreRow(68, 11.2, 11.7),
    _ScoreRow(66, 9.9, 10.4),
    _ScoreRow(64, 8.6, 9.1),
    _ScoreRow(62, 7.3, 7.8),
    _ScoreRow(60, 6, 6.5),
    _ScoreRow(50, 5.2, 5.7),
    _ScoreRow(40, 4.4, 4.9),
    _ScoreRow(30, 3.6, 4.1),
    _ScoreRow(20, 2.8, 3.3),
    _ScoreRow(10, 2, 2.5),
  ];

  /// 大学男生 立定跳远（厘米）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _maleStandingJump = [
    _ScoreRow(100, 273, 275),
    _ScoreRow(95, 268, 270),
    _ScoreRow(90, 263, 265),
    _ScoreRow(85, 256, 258),
    _ScoreRow(80, 248, 250),
    _ScoreRow(78, 244, 246),
    _ScoreRow(76, 240, 242),
    _ScoreRow(74, 236, 238),
    _ScoreRow(72, 232, 234),
    _ScoreRow(70, 228, 230),
    _ScoreRow(68, 224, 226),
    _ScoreRow(66, 220, 222),
    _ScoreRow(64, 216, 218),
    _ScoreRow(62, 212, 214),
    _ScoreRow(60, 208, 210),
    _ScoreRow(50, 203, 205),
    _ScoreRow(40, 198, 200),
    _ScoreRow(30, 193, 195),
    _ScoreRow(20, 188, 190),
    _ScoreRow(10, 183, 185),
  ];

  /// 大学女生 立定跳远（厘米）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _femaleStandingJump = [
    _ScoreRow(100, 207, 208),
    _ScoreRow(95, 201, 202),
    _ScoreRow(90, 195, 196),
    _ScoreRow(85, 188, 189),
    _ScoreRow(80, 181, 182),
    _ScoreRow(78, 178, 179),
    _ScoreRow(76, 175, 176),
    _ScoreRow(74, 172, 173),
    _ScoreRow(72, 169, 170),
    _ScoreRow(70, 166, 167),
    _ScoreRow(68, 163, 164),
    _ScoreRow(66, 160, 161),
    _ScoreRow(64, 157, 158),
    _ScoreRow(62, 154, 155),
    _ScoreRow(60, 151, 152),
    _ScoreRow(50, 146, 147),
    _ScoreRow(40, 141, 142),
    _ScoreRow(30, 136, 137),
    _ScoreRow(20, 131, 132),
    _ScoreRow(10, 126, 127),
  ];

  /// 大学男生 引体向上（次）/ 一分钟仰卧起坐（次）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _maleUpperStrength = [
    _ScoreRow(100, 19, 20),
    _ScoreRow(95, 18, 19),
    _ScoreRow(90, 17, 18),
    _ScoreRow(85, 16, 17),
    _ScoreRow(80, 15, 16),
    _ScoreRow(76, 14, 15),
    _ScoreRow(72, 13, 14),
    _ScoreRow(68, 12, 13),
    _ScoreRow(64, 11, 12),
    _ScoreRow(60, 10, 11),
    _ScoreRow(50, 9, 10),
    _ScoreRow(40, 8, 9),
    _ScoreRow(30, 7, 8),
    _ScoreRow(20, 6, 7),
    _ScoreRow(10, 5, 6),
  ];

  /// 大学女生 引体向上（次）/ 一分钟仰卧起坐（次）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _femaleUpperStrength = [
    _ScoreRow(100, 56, 57),
    _ScoreRow(95, 54, 55),
    _ScoreRow(90, 52, 53),
    _ScoreRow(85, 49, 50),
    _ScoreRow(80, 46, 47),
    _ScoreRow(78, 44, 45),
    _ScoreRow(76, 42, 43),
    _ScoreRow(74, 40, 41),
    _ScoreRow(72, 38, 39),
    _ScoreRow(70, 36, 37),
    _ScoreRow(68, 34, 35),
    _ScoreRow(66, 32, 33),
    _ScoreRow(64, 30, 31),
    _ScoreRow(62, 28, 29),
    _ScoreRow(60, 26, 27),
    _ScoreRow(50, 24, 25),
    _ScoreRow(40, 22, 23),
    _ScoreRow(30, 20, 21),
    _ScoreRow(20, 18, 19),
    _ScoreRow(10, 16, 17),
  ];

  /// 大学男生 1000 米跑（秒）/ 800 米跑（秒）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _maleEnduranceRun = [
    _ScoreRow(100, 197, 195),
    _ScoreRow(95, 202, 200),
    _ScoreRow(90, 207, 205),
    _ScoreRow(85, 214, 212),
    _ScoreRow(80, 222, 220),
    _ScoreRow(78, 227, 225),
    _ScoreRow(76, 232, 230),
    _ScoreRow(74, 237, 235),
    _ScoreRow(72, 242, 240),
    _ScoreRow(70, 247, 245),
    _ScoreRow(68, 252, 250),
    _ScoreRow(66, 257, 255),
    _ScoreRow(64, 262, 260),
    _ScoreRow(62, 267, 265),
    _ScoreRow(60, 272, 270),
    _ScoreRow(50, 292, 290),
    _ScoreRow(40, 312, 310),
    _ScoreRow(30, 332, 330),
    _ScoreRow(20, 352, 350),
    _ScoreRow(10, 372, 370),
  ];

  /// 大学女生 1000 米跑（秒）/ 800 米跑（秒）；第一个值为大一·大二，第二个值为大三·大四。
  static const List<_ScoreRow> _femaleEnduranceRun = [
    _ScoreRow(100, 198, 196),
    _ScoreRow(95, 204, 202),
    _ScoreRow(90, 210, 208),
    _ScoreRow(85, 217, 215),
    _ScoreRow(80, 224, 222),
    _ScoreRow(78, 229, 227),
    _ScoreRow(76, 234, 232),
    _ScoreRow(74, 239, 237),
    _ScoreRow(72, 244, 242),
    _ScoreRow(70, 249, 247),
    _ScoreRow(68, 254, 252),
    _ScoreRow(66, 259, 257),
    _ScoreRow(64, 264, 262),
    _ScoreRow(62, 269, 267),
    _ScoreRow(60, 274, 272),
    _ScoreRow(50, 284, 282),
    _ScoreRow(40, 294, 292),
    _ScoreRow(30, 304, 302),
    _ScoreRow(20, 314, 312),
    _ScoreRow(10, 324, 322),
  ];
}

/// 评分表的一行：单项得分与该得分要求的成绩门槛。
///
/// [lowerGrade] 对应大一·大二，[upperGrade] 对应大三·大四。
class _ScoreRow {
  const _ScoreRow(this.score, this.lowerGrade, this.upperGrade);

  final int score;
  final double lowerGrade;
  final double upperGrade;
}
