/// 体测计算器的领域模型：性别、年级组、单项指标、等级与输入/结果值对象。
///
/// 这里只有不可变数据；权重、评分表与加分规则属于
/// 《国家学生体质健康标准（2014 年修订）》，定义在
/// `fitness_test_standard.dart`。
library;

/// 评分表按性别分开，男女的引体向上/仰卧起坐与 1000 米/800 米互换。
enum FitnessTestGender {
  male('男'),
  female('女');

  const FitnessTestGender(this.label);

  final String label;
}

/// 大学阶段只分两组：大一·大二为一组，大三·大四为一组。
/// 评分表只分两个年级组：大一·大二一列，大三·大四一列。
enum FitnessTestGradeGroup {
  lower('大一·大二'),
  upper('大三·大四');

  const FitnessTestGradeGroup(this.label);

  final String label;
}

/// 用户实际选择的年级；两个年级共用一张评分表。
enum FitnessTestGradeYear {
  freshman('大一', 1),
  sophomore('大二', 2),
  junior('大三', 3),
  senior('大四', 4);

  const FitnessTestGradeYear(this.label, this.year);

  final String label;

  /// 1 至 4，用于从学号推算年级。
  final int year;

  /// 大一、大二用同一张评分表，大三、大四用另一张。
  FitnessTestGradeGroup get gradeGroup =>
      year <= 2 ? FitnessTestGradeGroup.lower : FitnessTestGradeGroup.upper;

  static FitnessTestGradeYear? forYear(int year) {
    for (final gradeYear in FitnessTestGradeYear.values) {
      if (gradeYear.year == year) return gradeYear;
    }
    return null;
  }
}

/// 大学阶段的七个单项指标与各自的权重。
///
/// 权重之和为 100，与标准中「单项指标与权重」表一致。
enum FitnessTestItem {
  bmi(weightPercent: 15),
  vitalCapacity(weightPercent: 15),
  sprint50m(weightPercent: 20),
  sitAndReach(weightPercent: 10),
  standingJump(weightPercent: 10),
  upperStrength(weightPercent: 10),
  enduranceRun(weightPercent: 20);

  const FitnessTestItem({required this.weightPercent});

  final int weightPercent;

  /// 指标名称；力量与耐力指标的名称由性别决定。
  String label(FitnessTestGender gender) {
    return switch (this) {
      FitnessTestItem.bmi => '体重指数',
      FitnessTestItem.vitalCapacity => '肺活量',
      FitnessTestItem.sprint50m => '50 米跑',
      FitnessTestItem.sitAndReach => '坐位体前屈',
      FitnessTestItem.standingJump => '立定跳远',
      FitnessTestItem.upperStrength =>
        gender == FitnessTestGender.male ? '引体向上' : '一分钟仰卧起坐',
      FitnessTestItem.enduranceRun =>
        gender == FitnessTestGender.male ? '1000 米跑' : '800 米跑',
    };
  }

  /// 输入单位；BMI 是由身高体重导出的指数，没有输入单位。
  String? unit(FitnessTestGender gender) {
    return switch (this) {
      FitnessTestItem.bmi => null,
      FitnessTestItem.vitalCapacity => 'ml',
      FitnessTestItem.sprint50m => '秒',
      FitnessTestItem.sitAndReach => '厘米',
      FitnessTestItem.standingJump => '厘米',
      FitnessTestItem.upperStrength => '次',
      FitnessTestItem.enduranceRun => '分 秒',
    };
  }

  /// 只有力量与耐力指标参与加分，且每项最多 10 分。
  bool get isBonusItem =>
      this == FitnessTestItem.upperStrength ||
      this == FitnessTestItem.enduranceRun;

  /// 时间类指标是低优指标：数值越小得分越高。
  bool get isLowerValueBetter =>
      this == FitnessTestItem.sprint50m || this == FitnessTestItem.enduranceRun;
}

/// 学年总分等级。分界值与标准一致：90 优秀、80 良好、60 及格。
enum FitnessTestGrade {
  excellent('优秀', 90),
  good('良好', 80),
  pass('及格', 60),
  fail('不及格', 0);

  const FitnessTestGrade(this.label, this.minimumScore);

  final String label;
  final double minimumScore;

  static FitnessTestGrade forScore(double score) {
    for (final grade in FitnessTestGrade.values) {
      if (score >= grade.minimumScore) return grade;
    }
    return FitnessTestGrade.fail;
  }

  /// 需要向上跨越的等级；已是优秀时为 null。
  FitnessTestGrade? get next {
    return switch (this) {
      FitnessTestGrade.fail => FitnessTestGrade.pass,
      FitnessTestGrade.pass => FitnessTestGrade.good,
      FitnessTestGrade.good => FitnessTestGrade.excellent,
      FitnessTestGrade.excellent => null,
    };
  }
}

/// 体重指数的四个区间，正常 100 分，低体重与超重 80 分，肥胖 60 分。
enum FitnessTestBmiBand {
  lowWeight('低体重'),
  normal('正常'),
  overweight('超重'),
  obese('肥胖');

  const FitnessTestBmiBand(this.label);

  final String label;
}

/// 一次计算的全部输入。缺项的字段为 null，未选择的维度也为 null。
class FitnessTestInput {
  const FitnessTestInput({
    this.gender,
    this.gradeGroup,
    this.heightCm,
    this.weightKg,
    this.vitalCapacityMl,
    this.sprint50mSeconds,
    this.sitAndReachCm,
    this.standingJumpCm,
    this.upperStrengthCount,
    this.enduranceRunSeconds,
  });

  final FitnessTestGender? gender;
  final FitnessTestGradeGroup? gradeGroup;
  final double? heightCm;
  final double? weightKg;
  final int? vitalCapacityMl;

  /// 50 米成绩，单位秒。
  final double? sprint50mSeconds;

  /// 坐位体前屈成绩，单位厘米，允许负值。
  final double? sitAndReachCm;

  /// 立定跳远成绩，单位厘米。
  final double? standingJumpCm;

  /// 引体向上（男）或一分钟仰卧起坐（女）次数。
  final int? upperStrengthCount;

  /// 1000 米（男）或 800 米（女）成绩，单位秒。
  final int? enduranceRunSeconds;

  /// 性别与年级组决定用哪一列评分表，未选全时不能计算单项得分。
  bool get hasProfile => gender != null && gradeGroup != null;
}

/// 单个指标的评分结果。[score] 为 null 表示该项还没有可计算的成绩。
class FitnessTestItemResult {
  const FitnessTestItemResult({
    required this.item,
    this.value,
    this.score,
    this.bonus = 0,
    this.bmiBand,
  });

  final FitnessTestItem item;

  /// 参与评分的成绩：BMI 为指数值，时间类为秒数。
  final double? value;

  /// 单项得分，0 至 100。
  final int? score;

  /// 附加分，只有加分指标可能大于 0，单项最多 10 分。
  final int bonus;

  /// 仅体重指数指标有区间。
  final FitnessTestBmiBand? bmiBand;

  bool get isScored => score != null;

  /// 单项得分乘权重，作为标准分的一部分。
  double? get weightedScore {
    final score = this.score;
    if (score == null) return null;
    return score * item.weightPercent / 100;
  }
}

/// 一次计算的完整结果。总分 = 标准分 + 附加分，标准分满分 100，总分满分 120。
class FitnessTestResult {
  const FitnessTestResult({
    required this.items,
    required this.standardScore,
    required this.bonusScore,
    required this.totalScore,
    required this.grade,
    required this.bmi,
    required this.bmiBand,
  });

  /// 未选择性别或年级组时的空结果。
  static const FitnessTestResult empty = FitnessTestResult(
    items: [],
    standardScore: null,
    bonusScore: 0,
    totalScore: null,
    grade: null,
    bmi: null,
    bmiBand: null,
  );

  final List<FitnessTestItemResult> items;

  /// 各单项得分与权重乘积之和，保留一位小数。
  final double? standardScore;

  /// 加分指标之和，满分 20。
  final int bonusScore;

  /// 标准分加附加分，保留一位小数。
  final double? totalScore;

  final FitnessTestGrade? grade;

  /// 由身高体重导出的指数；身高或体重缺失时为 null。
  final double? bmi;

  final FitnessTestBmiBand? bmiBand;

  bool get isComplete => totalScore != null;

  /// 已经有成绩的指标数量，用于表达还差几项。
  int get scoredItemCount => items.where((item) => item.isScored).length;

  FitnessTestItemResult? resultFor(FitnessTestItem item) {
    for (final result in items) {
      if (result.item == item) return result;
    }
    return null;
  }

  /// 当前等级之上还需要跨越的等级。
  FitnessTestGrade? get nextGrade => grade?.next;

  /// 距离下一等级还差多少分；已是优秀或尚未出分时为 null。
  double? get pointsToNextGrade {
    final next = nextGrade;
    final total = totalScore;
    if (next == null || total == null) return null;
    return next.minimumScore - total;
  }
}
