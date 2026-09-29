import 'dart:convert';

enum DesktopWidgetScheduleStatus {
  signedOut,
  noSchedule,
  calendarUnavailable,
  ready,
}

class DesktopWidgetOccurrenceV1 {
  final String id;
  final String date;
  final String courseName;
  final String location;
  final int startPeriod;
  final int endPeriod;
  final String periodLabel;
  final String? startTime;
  final String? endTime;

  const DesktopWidgetOccurrenceV1({
    required this.id,
    required this.date,
    required this.courseName,
    required this.location,
    required this.startPeriod,
    required this.endPeriod,
    required this.periodLabel,
    required this.startTime,
    required this.endTime,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date,
    'courseName': courseName,
    'location': location,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'periodLabel': periodLabel,
    'startTime': startTime,
    'endTime': endTime,
  };

  factory DesktopWidgetOccurrenceV1.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final id = json['id'];
    final courseName = json['courseName'];
    final location = json['location'];
    final periodLabel = json['periodLabel'];
    final startPeriod = json['startPeriod'];
    final endPeriod = json['endPeriod'];
    final startTime = json['startTime'];
    final endTime = json['endTime'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        id is! String ||
        id.isEmpty ||
        courseName is! String ||
        courseName.isEmpty ||
        location is! String ||
        periodLabel is! String ||
        startPeriod is! int ||
        endPeriod is! int ||
        startPeriod < 1 ||
        endPeriod < startPeriod ||
        (startTime != null && startTime is! String) ||
        (endTime != null && endTime is! String)) {
      throw const FormatException('桌面课表 occurrence 无效');
    }
    return DesktopWidgetOccurrenceV1(
      id: id,
      date: date,
      courseName: courseName,
      location: location,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      periodLabel: periodLabel,
      startTime: startTime as String?,
      endTime: endTime as String?,
    );
  }
}

class DesktopWidgetScheduleV1 {
  final DesktopWidgetScheduleStatus status;
  final String? semesterId;
  final int? currentWeek;
  final List<DesktopWidgetOccurrenceV1> occurrences;

  DesktopWidgetScheduleV1({
    required this.status,
    this.semesterId,
    this.currentWeek,
    List<DesktopWidgetOccurrenceV1> occurrences = const [],
  }) : occurrences = List.unmodifiable(occurrences) {
    if (status != DesktopWidgetScheduleStatus.ready && occurrences.isNotEmpty) {
      throw ArgumentError('只有 ready 课表可以包含课程 occurrence');
    }
    if (status != DesktopWidgetScheduleStatus.ready && semesterId != null) {
      throw ArgumentError('不可用课表不能包含 semesterId');
    }
    if (currentWeek != null && currentWeek! < 1) {
      throw ArgumentError('当前周次必须是正整数');
    }
    if (status != DesktopWidgetScheduleStatus.ready && currentWeek != null) {
      throw ArgumentError('不可用课表不能包含当前周次');
    }
    if (status == DesktopWidgetScheduleStatus.ready &&
        (semesterId == null || semesterId!.trim().isEmpty)) {
      throw ArgumentError('ready 课表必须包含 semesterId');
    }
  }

  Map<String, Object?> toJson() => {
    'status': status.name,
    if (semesterId != null) 'semesterId': semesterId,
    if (currentWeek != null) 'currentWeek': currentWeek,
    'occurrences': [for (final value in occurrences) value.toJson()],
  };

  factory DesktopWidgetScheduleV1.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'];
    if (statusName is! String) {
      throw const FormatException('桌面课表状态缺失');
    }
    final status = DesktopWidgetScheduleStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => throw const FormatException('桌面课表状态无效'),
    );
    final semesterId = json['semesterId'];
    final currentWeek = json['currentWeek'];
    final rawOccurrences = json['occurrences'];
    if ((semesterId != null && semesterId is! String) ||
        (currentWeek != null && currentWeek is! int) ||
        rawOccurrences is! List) {
      throw const FormatException('桌面课表字段无效');
    }
    final occurrences = rawOccurrences
        .map((raw) {
          if (raw is! Map) throw const FormatException('桌面课程字段无效');
          return DesktopWidgetOccurrenceV1.fromJson(
            Map<String, dynamic>.from(raw),
          );
        })
        .toList(growable: false);
    try {
      return DesktopWidgetScheduleV1(
        status: status,
        semesterId: semesterId as String?,
        currentWeek: currentWeek as int?,
        occurrences: occurrences,
      );
    } on ArgumentError {
      throw const FormatException('桌面课表状态与课程内容不匹配');
    }
  }
}

class DesktopWidgetSnapshotV1 {
  static const schemaVersion = 1;
  static const timezoneOffsetMinutes = 480;

  final DateTime generatedAt;
  final DesktopWidgetScheduleV1 schedule;

  DesktopWidgetSnapshotV1({
    required this.generatedAt,
    required this.schedule,
  });

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'schedule': schedule.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory DesktopWidgetSnapshotV1.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion ||
        json['timezoneOffsetMinutes'] != timezoneOffsetMinutes) {
      throw const FormatException('不支持的桌面 Widget snapshot 版本');
    }
    final generatedAtText = json['generatedAt'];
    final rawSchedule = json['schedule'];
    if (generatedAtText is! String ||
        rawSchedule is! Map) {
      throw const FormatException('桌面 Widget snapshot 字段无效');
    }
    final generatedAt = DateTime.tryParse(generatedAtText);
    if (generatedAt == null) {
      throw const FormatException('桌面 Widget snapshot 时间无效');
    }
    return DesktopWidgetSnapshotV1(
      generatedAt: generatedAt.toUtc(),
      schedule: DesktopWidgetScheduleV1.fromJson(
        Map<String, dynamic>.from(rawSchedule),
      ),
    );
  }

  factory DesktopWidgetSnapshotV1.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('桌面 Widget snapshot 必须是对象');
    }
    return DesktopWidgetSnapshotV1.fromJson(Map<String, dynamic>.from(decoded));
  }
}

class DesktopWidgetLaunchRequestV1 {
  static const schemaVersion = 1;

  final String targetId;

  const DesktopWidgetLaunchRequestV1({required this.targetId});

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'targetId': targetId,
  };

  String encode() => jsonEncode(toJson());

  factory DesktopWidgetLaunchRequestV1.fromJson(Map<String, dynamic> json) {
    final targetId = json['targetId'];
    if (json['schemaVersion'] != schemaVersion ||
        targetId is! String ||
        targetId.trim().isEmpty) {
      throw const FormatException('不支持的桌面 Widget launch request');
    }
    return DesktopWidgetLaunchRequestV1(targetId: targetId);
  }

  static DesktopWidgetLaunchRequestV1? tryDecode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return DesktopWidgetLaunchRequestV1.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on Object {
      return null;
    }
  }
}
