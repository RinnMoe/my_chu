// 畅课应用数据模型：待办与课件。

import '../../capabilities/east8_time.dart';

class TronclassTodo {
  final String courseCode;
  final String courseId;
  final String courseName;
  final DateTime? endTime;
  final String id;
  final bool isLocked;
  final bool isStudent;
  final int notScoredNum;
  final int submitRate;
  final String title;
  final String type;

  const TronclassTodo({
    required this.courseCode,
    required this.courseId,
    required this.courseName,
    required this.endTime,
    required this.id,
    required this.isLocked,
    required this.isStudent,
    required this.notScoredNum,
    required this.submitRate,
    required this.title,
    required this.type,
  });

  factory TronclassTodo.fromJson(Map<String, dynamic> json) {
    return TronclassTodo(
      courseCode: _string(json['course_code']),
      courseId: _string(json['course_id']),
      courseName: _string(json['course_name']),
      endTime: _dateTime(json['end_time']),
      id: _string(json['id']),
      isLocked: json['is_locked'] == true,
      isStudent: json['is_student'] == true,
      notScoredNum: _int(json['not_scored_num']),
      submitRate: _int(json['submit_rate']),
      title: _string(json['title']),
      type: _string(json['type']),
    );
  }
}

class TronclassCourse {
  final String id;
  final String name;
  final String courseCode;
  final String secondName;
  final String departmentName;
  final List<String> instructorNames;
  final DateTime? startDate;

  const TronclassCourse({
    required this.id,
    required this.name,
    required this.courseCode,
    required this.secondName,
    required this.departmentName,
    required this.instructorNames,
    this.startDate,
  });

  /// 课程中文名：去掉名称中的英文翻译部分，仅用于列表展示。
  String get chineseName => stripCourseEnglishName(name);

  factory TronclassCourse.fromJson(Map<String, dynamic> json) {
    final department =
        json['department'] is Map
            ? Map<String, dynamic>.from(json['department'] as Map)
            : const <String, dynamic>{};
    final instructors = json['instructors'];
    return TronclassCourse(
      id: _string(json['id']),
      name: _string(json['display_name'] ?? json['name']),
      courseCode: _string(json['course_code']),
      secondName: _string(json['second_name']),
      departmentName: _string(department['name']),
      instructorNames: [
        if (instructors is List)
          for (final item in instructors.whereType<Map>())
            _string((Map<String, dynamic>.from(item))['name']),
      ],
      startDate: _dateTime(json['start_date']),
    );
  }
}

/// 课程列表分页结果。
class TronclassCoursePage {
  final List<TronclassCourse> courses;
  final int pages;

  const TronclassCoursePage({required this.courses, required this.pages});
}

class TronclassCoursewareFile {
  final String activityId;
  final String activityTitle;
  final String courseId;
  final String fileId;
  final String name;
  final int size;
  final String type;

  const TronclassCoursewareFile({
    required this.activityId,
    required this.activityTitle,
    required this.courseId,
    required this.fileId,
    required this.name,
    required this.size,
    required this.type,
  });

  factory TronclassCoursewareFile.fromJson(
    Map<String, dynamic> json, {
    required TronclassCourse course,
    required String activityId,
    required String activityTitle,
  }) {
    return TronclassCoursewareFile(
      activityId: activityId,
      activityTitle: activityTitle,
      courseId: course.id,
      fileId: _string(json['reference_id']),
      name: _string(json['name']),
      size: _int(json['size']),
      type: _string(json['type']),
    );
  }

  String get sizeLabel => formatFileSize(size);
}

class TronclassCoursewareProgress {
  final int completed;
  final int total;
  final int found;
  final int failed;
  final String? current;

  const TronclassCoursewareProgress({
    required this.completed,
    required this.total,
    required this.found,
    required this.failed,
    this.current,
  });

  bool get isDone => total > 0 && completed >= total;
}

class TronclassException implements Exception {
  final String message;

  const TronclassException(this.message);

  @override
  String toString() => message;
}

String formatFileSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final fractionDigits = unitIndex == 0 ? 0 : 2;
  return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

/// 去掉课程名称中的英文翻译（含中英文括号内的英文），保留中文课程名。
///
/// 与中文直接相连的字母/数字视为课程名一部分（如 “C语言程序设计”“大学英语A”）
/// 会被保留；以空白分隔的独立英文词段（如 “Linear Algebra”）会被移除。
String stripCourseEnglishName(String value) {
  var text = value.trim();
  if (text.isEmpty) return text;

  // 去掉含英文的括号内容（中文括号与英文括号）。
  text = text.replaceAllMapped(RegExp(r'[（(][^（）()]*[）)]'), (match) {
    final segment = match.group(0)!;
    return RegExp(r'[A-Za-z]').hasMatch(segment) ? ' ' : segment;
  });

  // 名称含中文时，去掉以空白分隔的纯英文/数字词段。
  final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  if (hasCjk) {
    final parts =
        text.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    text = parts
        .where((part) => RegExp(r'[\u4e00-\u9fff]').hasMatch(part))
        .join(' ');
  }

  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return value.trim();
  return text;
}

String _string(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return parseEast8(value);
}
