import 'dart:async';

import '../../services/auth_service.dart';
import 'fitness_test_models.dart';

/// 按学号与当前学年推算年级，只在能确定为在读本科生年级时返回。
///
/// 学号前四位是入学年份（如 `2023…`），学年从 9 月开始，所以 9 月之前仍算
/// 上一学年。延期毕业、休学、转专业、专升本与研究生学制无法从学号判断，
/// 因此结果只作为页面上可随时改选的初始值，不写入任何持久化状态。
FitnessTestGradeYear? gradeYearForStudentNumber(
  String studentNumber, {
  required DateTime now,
  String? identity,
}) {
  // 研究生学制不是四学年，直接用同一套推算会得到错误年级。
  if (identity == null || !identity.contains('本科')) return null;

  final match = RegExp(r'^(\d{4})').firstMatch(studentNumber.trim());
  final enrollmentYear = match == null ? null : int.tryParse(match.group(1)!);
  if (enrollmentYear == null || enrollmentYear < 2000) return null;

  final academicStartYear = now.month >= 9 ? now.year : now.year - 1;
  return FitnessTestGradeYear.forYear(academicStartYear - enrollmentYear + 1);
}

/// 用本机已回填的账号资料推算年级。
///
/// 只读最小可用的资料：不发起网络请求，不读取密码或 Cookie，也不把学号
/// 返回给页面。资料未回填、非本科生或学年推不出 1–4 时返回 null。
Future<FitnessTestGradeYear?> detectCurrentGradeYear() async {
  try {
    final account = await AuthService.getCurrentAccount();
    if (account == null) return null;
    final studentNumber = account.uid?.trim();
    if (studentNumber == null || studentNumber.isEmpty) return null;
    return gradeYearForStudentNumber(
      studentNumber,
      now: DateTime.now(),
      identity: account.identity,
    );
  } catch (_) {
    // 预选失败不影响手动选择，也不向外抛错。
    return null;
  }
}
