import '../../capabilities/east8_time.dart';
import 'academic_affairs_models.dart';

DateTime? academicExamStart(
  AcademicExam exam, {
  bool requireExplicitTime = false,
}) {
  if (!exam.isScheduled) return null;

  final date = parseEast8(exam.examDate);
  if (date == null) return null;

  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(exam.arrangement);
  if (match == null) {
    return requireExplicitTime
        ? null
        : DateTime(date.year, date.month, date.day);
  }

  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, hour, minute);
}
