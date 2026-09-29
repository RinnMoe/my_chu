/// The source array used by a calendar event.  This is intentionally separate
/// from the integer `type` values used by [AcademicCalendarWeek].
enum AcademicCalendarEventKind { commonHoliday, special }

/// Normalizes labels emitted by different timetable and calendar endpoints
/// before matching the same academic semester.
String normalizeAcademicCalendarTermLabel(String value) {
  var normalized = value.trim().replaceAll(RegExp(r'\s+'), '');
  normalized = normalized
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-');
  normalized = normalized
      .replaceAll('秋季学期', '1')
      .replaceAll('秋学期', '1')
      .replaceAll('春季学期', '2')
      .replaceAll('春学期', '2');
  normalized = normalized
      .replaceAll('第一', '1')
      .replaceAll('第二', '2')
      .replaceAll('第三', '3')
      .replaceAll('第四', '4')
      .replaceAll('第五', '5')
      .replaceAll('第六', '6')
      .replaceAll('第七', '7')
      .replaceAll('第八', '8')
      .replaceAll('第九', '9')
      .replaceAll('第十', '10')
      .replaceAll('一', '1')
      .replaceAll('二', '2')
      .replaceAll('三', '3')
      .replaceAll('四', '4')
      .replaceAll('五', '5')
      .replaceAll('六', '6')
      .replaceAll('七', '7')
      .replaceAll('八', '8')
      .replaceAll('九', '9')
      .replaceAll('十', '10')
      .replaceAll('学年', '')
      .replaceAll('学期', '')
      .replaceAll('第', '');
  return normalized
      .replaceAll(RegExp(r'[^0-9a-zA-Z\u4e00-\u9fff]'), '')
      .toLowerCase();
}

bool academicCalendarTermLabelsMatch(String left, String right) {
  final leftKey = normalizeAcademicCalendarTermLabel(left);
  final rightKey = normalizeAcademicCalendarTermLabel(right);
  return leftKey.isNotEmpty && leftKey == rightKey;
}

class AcademicCalendarTerm {
  final String academicYear;
  final int semester;
  final String description;
  final DateTime? startDate;
  final String? color;

  const AcademicCalendarTerm({
    String? academicYear,
    int? semester,
    String? xn,
    int? xq,
    this.description = '',
    this.startDate,
    this.color,
  }) : academicYear = academicYear ?? xn ?? '',
       semester = semester ?? xq ?? 0;

  /// Names used by the mobile-campus response.
  String get xn => academicYear;
  int get xq => semester;

  String get id => '$academicYear.$semester';
  String get label => '${_displayAcademicYear(academicYear)}学年第$semester学期';

  AcademicCalendarTerm copyWith({
    String? academicYear,
    int? semester,
    String? description,
    DateTime? startDate,
    String? color,
  }) => AcademicCalendarTerm(
    academicYear: academicYear ?? this.academicYear,
    semester: semester ?? this.semester,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'academicYear': academicYear,
    'semester': semester,
    'description': description,
    'startDate': startDate?.toIso8601String(),
    'color': color,
  };

  factory AcademicCalendarTerm.fromJson(Map<String, dynamic> json) {
    final academicYear = _requiredText(json['academicYear']);
    final semester = _requiredPositiveInt(json['semester']);
    final startDate = _optionalDate(json['startDate']);
    return AcademicCalendarTerm(
      academicYear: academicYear,
      semester: semester,
      description: _text(json['description']),
      startDate: startDate,
      color: _nullableText(json['color']),
    );
  }
}

class AcademicCalendarWeek {
  final int week;
  final DateTime startDate;
  final DateTime endDate;
  final bool isHoliday;
  final String event;
  final String? eventColor;

  const AcademicCalendarWeek({
    int? week,
    int? zc,
    required this.startDate,
    required this.endDate,
    bool? isHoliday,
    int? type,
    this.event = '',
    this.eventColor,
  }) : week = week ?? zc ?? 0,
       isHoliday = isHoliday ?? type == 2;

  /// Names used by the mobile-campus response.
  int get zc => week;
  int get type => isHoliday ? 2 : 1;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  Map<String, dynamic> toJson() => {
    'week': week,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'isHoliday': isHoliday,
    'event': event,
    'eventColor': eventColor,
  };

  factory AcademicCalendarWeek.fromJson(Map<String, dynamic> json) {
    final week = _requiredPositiveInt(json['week']);
    final startDate = _requiredDate(json['startDate']);
    final endDate = _requiredDate(json['endDate']);
    if (endDate.isBefore(startDate)) {
      throw const FormatException('校历周日期范围无效');
    }
    final isHoliday = json['isHoliday'];
    if (isHoliday is! bool) {
      throw const FormatException('校历周类型缺失');
    }
    return AcademicCalendarWeek(
      week: week,
      startDate: startDate,
      endDate: endDate,
      isHoliday: isHoliday,
      event: _text(json['event']),
      eventColor: _nullableText(json['eventColor']),
    );
  }
}

class AcademicCalendarEvent {
  final DateTime date;
  final String title;
  final String? color;
  final AcademicCalendarEventKind kind;
  final int sourceType;

  const AcademicCalendarEvent({
    required this.date,
    required this.title,
    required this.kind,
    this.sourceType = 1,
    this.color,
  });

  bool get isCommonHoliday => kind == AcademicCalendarEventKind.commonHoliday;
  bool get isSpecial => kind == AcademicCalendarEventKind.special;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'title': title,
    'color': color,
    'kind': kind.name,
    'sourceType': sourceType,
  };

  factory AcademicCalendarEvent.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'];
    final kind = AcademicCalendarEventKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => throw const FormatException('校历事件类型无效'),
    );
    return AcademicCalendarEvent(
      date: _requiredDate(json['date']),
      title: _requiredText(json['title']),
      color: _nullableText(json['color']),
      kind: kind,
      sourceType: _requiredPositiveInt(json['sourceType']),
    );
  }
}

class AcademicCalendarData {
  final AcademicCalendarTerm term;
  final List<AcademicCalendarWeek> weeks;
  final List<AcademicCalendarEvent> events;

  AcademicCalendarData({
    required this.term,
    required List<AcademicCalendarWeek> weeks,
    required List<AcademicCalendarEvent> events,
  }) : weeks = List.unmodifiable(weeks),
       events = List.unmodifiable(events);

  AcademicCalendarWeek? weekFor(DateTime date) {
    for (final week in weeks) {
      if (week.contains(date)) return week;
    }
    return null;
  }

  AcademicCalendarData copyWith({
    AcademicCalendarTerm? term,
    List<AcademicCalendarWeek>? weeks,
    List<AcademicCalendarEvent>? events,
  }) => AcademicCalendarData(
    term: term ?? this.term,
    weeks: weeks ?? this.weeks,
    events: events ?? this.events,
  );

  Map<String, dynamic> toJson() => {
    'term': term.toJson(),
    'weeks': [for (final week in weeks) week.toJson()],
    'events': [for (final event in events) event.toJson()],
  };

  factory AcademicCalendarData.fromJson(Map<String, dynamic> json) {
    final term = json['term'];
    if (term is! Map) throw const FormatException('校历学期字段缺失');
    return AcademicCalendarData(
      term: AcademicCalendarTerm.fromJson(Map<String, dynamic>.from(term)),
      weeks: _requiredMaps(
        json['weeks'],
      ).map(AcademicCalendarWeek.fromJson).toList(growable: false),
      events: _requiredMaps(
        json['events'],
      ).map(AcademicCalendarEvent.fromJson).toList(growable: false),
    );
  }
}

/// A teaching week resolved from the academic calendar.
///
/// This value is only present when the current calendar interval is a normal
/// teaching week. Holiday and unknown-date states are represented by the
/// surrounding [AcademicCalendarState].
class CurrentTeachingWeek {
  final int week;
  final String term;
  final DateTime? termStartDate;

  const CurrentTeachingWeek({
    required this.week,
    required this.term,
    this.termStartDate,
  });
}

/// The canonical current academic-calendar state consumed by the host.
///
/// [teachingWeek] is null during a holiday interval or when the date is not
/// covered by any calendar interval. [calendarWeek] remains available for a
/// holiday interval, while [term] and [termStartDate] describe the selected
/// current term.
class AcademicCalendarState {
  final CurrentTeachingWeek? teachingWeek;
  final int? calendarWeek;
  final String term;
  final DateTime? termStartDate;
  final DateTime fetchedAt;
  final bool isHoliday;

  const AcademicCalendarState({
    required this.teachingWeek,
    this.calendarWeek,
    required this.term,
    required this.termStartDate,
    required this.fetchedAt,
    required this.isHoliday,
  });
}

String _text(Object? value) =>
    value is String ? value.trim() : '${value ?? ''}'.trim();

String _requiredText(Object? value) {
  final text = _text(value);
  if (text.isEmpty) throw const FormatException('校历文本字段缺失');
  return text;
}

String? _nullableText(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

int _requiredPositiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 1) {
    throw const FormatException('校历数字字段无效');
  }
  return parsed;
}

DateTime _requiredDate(Object? value) {
  final date = _optionalDate(value);
  if (date == null) throw const FormatException('校历日期字段无效');
  return date;
}

DateTime? _optionalDate(Object? value) {
  if (value == null || value is! String) {
    return value is DateTime
        ? DateTime(value.year, value.month, value.day)
        : null;
  }
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

List<Map<String, dynamic>> _requiredMaps(Object? value) {
  if (value is! List) throw const FormatException('校历数组字段缺失');
  final result = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is! Map) throw const FormatException('校历数组元素无效');
    result.add(Map<String, dynamic>.from(item));
  }
  return result;
}

String _displayAcademicYear(String value) {
  final year = int.tryParse(value);
  if (year == null || value.length != 4) return value;
  return '${year - 1}-$year';
}
