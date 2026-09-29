import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'academic_affairs_models.dart';
import 'academic_schedule_place.dart';

class _AcademicAffairsQueryPage {
  static final _scriptInputPattern = RegExp(
    r'''bg\.form\.addInput\s*\(\s*form\s*,\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']\s*(?:,\s*[^)]*)?\)''',
  );
  static Map<String, String> formValues(Document document) {
    final values = <String, String>{};
    for (final input in document.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      final value = input.attributes['value']?.trim();
      if (name != null && value != null && value.isNotEmpty) {
        values[name] = value;
      }
    }
    for (final select in document.querySelectorAll('select[name]')) {
      final name = select.attributes['name'];
      if (name == null || name.isEmpty) continue;
      Element? valueOption;
      for (final option in select.querySelectorAll('option')) {
        final value = option.attributes['value']?.trim() ?? '';
        if (value.isEmpty) continue;
        valueOption ??= option;
        if (option.attributes.containsKey('selected')) {
          valueOption = option;
          break;
        }
      }
      final value = valueOption?.attributes['value']?.trim() ?? '';
      if (value.isNotEmpty) values[name] = value;
    }
    for (final script in document.querySelectorAll('script')) {
      for (final match in _scriptInputPattern.allMatches(script.text)) {
        final name = match.group(1)?.trim() ?? '';
        final value = match.group(2)?.trim() ?? '';
        if (name.isNotEmpty && value.isNotEmpty) values[name] = value;
      }
    }
    return values;
  }
}

class AcademicAffairsHtmlParser {
  static Map<String, String> formValues(Document document) =>
      _AcademicAffairsQueryPage.formValues(document);

  static bool hasExams(Document document) =>
      _tableWithHeaders(document, const ['课程序号', '课程名称', '考试日期', '考场座位号']) !=
      null;

  static List<AcademicSemesterOption> semesterOptions(Document document) {
    final select = document.querySelector('select[name="semester.id"]');
    if (select != null) {
      final options = <AcademicSemesterOption>[];
      for (final option in select.querySelectorAll('option')) {
        final value = option.attributes['value']?.trim() ?? '';
        if (value.isEmpty) continue;
        options.add(
          AcademicSemesterOption(
            id: value,
            label: _text(option),
            selected: option.attributes.containsKey('selected'),
          ),
        );
      }
      if (options.isNotEmpty) return options;
    }

    // The current EAMS page uses a calendar widget instead of a select. Its
    // term cells carry the real semester id in `val`.
    final target =
        document
            .querySelector('#semesterCalendar_target')
            ?.attributes['value']
            ?.trim() ??
        '';
    final year = _calendarValue(document, '#semesterCalendar_year');
    final options = <AcademicSemesterOption>[];
    for (final cell in document.querySelectorAll(
      '#semesterCalendar_termTb td',
    )) {
      final value = cell.attributes['val']?.trim() ?? '';
      if (value.isEmpty) continue;
      final term = _text(cell);
      final label = year.isEmpty || term.contains(year) ? term : '$year $term';
      options.add(
        AcademicSemesterOption(
          id: value,
          label: label,
          selected: value == target,
        ),
      );
    }
    if (options.isNotEmpty) return options;

    if (target.isNotEmpty) {
      return [
        AcademicSemesterOption(
          id: target,
          label: scheduleSemesterLabel(document),
          selected: true,
        ),
      ];
    }
    return const [];
  }

  static String scheduleSemesterLabel(Document document) {
    final inputLabel = document
        .querySelectorAll('input')
        .map((input) => input.attributes['value']?.trim() ?? '')
        .firstWhere(
          (value) => value.contains('学年') && value.contains('学期'),
          orElse: () => '',
        );
    if (inputLabel.isNotEmpty) return inputLabel;

    final year = _calendarValue(document, '#semesterCalendar_year');
    final term = _calendarValue(document, '#semesterCalendar_term');
    if (year.isNotEmpty && term.isNotEmpty) return '$year $term';
    return [year, term].where((value) => value.isNotEmpty).join(' ');
  }

  static String? syllabusSemesterTagId(Document document) {
    for (final input in document.querySelectorAll('input')) {
      final classes = (input.attributes['class'] ?? '').split(RegExp(r'\s+'));
      if (classes.contains('calendar-text')) {
        return input.attributes['id'];
      }
    }
    return null;
  }

  static String syllabusDefaultSemester(Document document) {
    for (final script in document.querySelectorAll('script')) {
      final match = _syllabusDefaultSemesterPattern.firstMatch(script.text);
      if (match != null) return match.group(1) ?? '';
    }
    return '';
  }

  static List<AcademicSemesterOption> graduateSemesterOptions(
    Document document,
  ) {
    final yearSelect = document.querySelector('select[name="kkxn"]');
    final termSelect = document.querySelector('select[name="kckkxj"]');
    if (yearSelect == null || termSelect == null) {
      throw const AcademicAffairsException('未找到研究生排课学期参数');
    }
    final years = yearSelect
        .querySelectorAll('option')
        .where(
          (option) => (option.attributes['value']?.trim() ?? '').isNotEmpty,
        );
    final terms = termSelect
        .querySelectorAll('option')
        .where(
          (option) => (option.attributes['value']?.trim() ?? '').isNotEmpty,
        );
    final selectedYear =
        years
            .where((option) => option.attributes.containsKey('selected'))
            .firstOrNull;
    final selectedTerm =
        terms
            .where((option) => option.attributes.containsKey('selected'))
            .firstOrNull;
    final options = <AcademicSemesterOption>[];
    for (final year in years) {
      final yearId = year.attributes['value']!.trim();
      for (final term in terms) {
        final termId = term.attributes['value']!.trim();
        options.add(
          AcademicSemesterOption(
            id: 'yjs:$yearId:$termId',
            label: '${_text(year)} 学年${_text(term)}',
            selected:
                identical(year, selectedYear) && identical(term, selectedTerm),
          ),
        );
      }
    }
    return options;
  }

  /// Research graduate student pages use `xn`/`xj` rather than the syllabus
  /// page's `kkxn`/`kckkxj` controls. The composite ID keeps both values in the
  /// existing semester selector without leaking raw form state into widgets.
  static List<AcademicSemesterOption> graduateStudentSemesterOptions(
    Document document, {
    String? selectedId,
  }) => _graduateStudentSemesterOptions(
    document,
    yearName: 'xn',
    termName: 'xj',
    selectedId: selectedId,
  );

  static List<AcademicSemesterOption> graduateScheduleSemesterOptions(
    Document document, {
    String? selectedId,
  }) => graduateStudentSemesterOptions(document, selectedId: selectedId);

  static ({String year, String term}) graduateScheduleSelection(
    Document document,
  ) {
    final year = _selectedValue(document, 'xn');
    final term = _selectedValue(document, 'xj');
    return (year: year, term: term);
  }

  static List<int> graduateWeekOptions(Document document) {
    final select = document.querySelector('select[name="zc"]');
    if (select == null) return const [];
    final values = <int>{};
    for (final option in select.querySelectorAll('option')) {
      final value = int.tryParse(option.attributes['value']?.trim() ?? '');
      if (value != null && value > 0 && value <= 53) values.add(value);
    }
    return values.toList()..sort();
  }

  static int? graduateSelectedWeek(Document document) {
    final selected = _selectedValue(document, 'zc');
    final week = int.tryParse(selected);
    return week != null && week > 0 && week <= 53 ? week : null;
  }

  static ({String year, String term}) parseGraduateStudentSemesterId(
    String id,
  ) {
    final parts = id.split(':');
    if (parts.length != 3 ||
        parts.first != 'yjs' ||
        parts[1].trim().isEmpty ||
        parts[2].trim().isEmpty) {
      throw const AcademicAffairsException('研究生课表学期参数无效');
    }
    return (year: parts[1].trim(), term: parts[2].trim());
  }

  static List<AcademicExam> parseGraduateExams(Document document) {
    _GraduateExamTable? result;
    for (final table in document.querySelectorAll('table')) {
      for (final row in table.querySelectorAll('tr')) {
        final headers = _cells(row);
        if (_graduateExamHeader(headers)) {
          result = _GraduateExamTable(table: table, headers: headers);
          break;
        }
      }
      if (result != null) break;
    }
    // The graduate page deliberately renders no table when the selected term
    // has no examinations. Treat that as a valid empty result.
    if (result == null) return const [];

    final headers = result.headers;
    final sequenceIndex = _headerIndex(headers, const [
      '课程序号',
      '课程编号',
      '课程号',
      '课程代码',
      '开课号',
    ]);
    final nameIndex = _headerIndex(headers, const ['课程名称', '课程名']);
    final typeIndex = _headerIndex(headers, const ['考试类别', '考试类型', '考试性质']);
    final dateIndex = _headerIndex(headers, const ['考试日期', '考试时间', '日期']);
    final arrangementIndex = _headerIndex(headers, const [
      '考试安排',
      '考试时段',
      '时间',
    ]);
    final locationIndex = _headerIndex(headers, const ['考试地点', '考场', '地点']);
    final seatIndex = _headerIndex(headers, const ['考场座位号', '座位号', '座位']);
    final statusIndex = _headerIndex(headers, const ['考试情况', '状态']);
    final noteIndex = _headerIndex(headers, const ['其它说明', '其他说明', '备注']);
    final exams = <AcademicExam>[];
    for (final row in result.table.querySelectorAll('tr')) {
      final values = _cells(row);
      if (values.isEmpty || _sameValues(values, headers)) continue;
      final sequence = _valueAt(values, sequenceIndex);
      final name = _valueAt(values, nameIndex);
      if (sequence.isEmpty && name.isEmpty) continue;
      final rawDate = _valueAt(values, dateIndex);
      final rawArrangement =
          arrangementIndex == dateIndex
              ? ''
              : _valueAt(values, arrangementIndex);
      final split = _splitGraduateExamDateTime(rawDate, rawArrangement);
      var examDate = split.date;
      var arrangement = split.arrangement;
      if (examDate.isNotEmpty && arrangement.isEmpty) {
        arrangement = examDate.contains('未安排') ? '未安排' : '时间待定';
      }
      exams.add(
        AcademicExam(
          courseSequence: sequence,
          courseName: name,
          examType: _valueAt(values, typeIndex),
          examDate: examDate,
          arrangement: arrangement,
          location: _valueAt(values, locationIndex),
          seat: _valueAt(values, seatIndex),
          status: _valueAt(values, statusIndex),
          note: _valueAt(values, noteIndex),
        ),
      );
    }
    exams.sort((left, right) {
      if (left.isScheduled != right.isScheduled) {
        return left.isScheduled ? -1 : 1;
      }
      return left.examDate.compareTo(right.examDate);
    });
    return exams;
  }

  static AcademicPersonalSchedule parseGraduateSchedule(
    Map<int, Document> documents, {
    required String semesterId,
    required String semesterLabel,
    required int maxWeek,
  }) {
    final groups = <String, _GraduateScheduleGroup>{};
    final weekLimit = maxWeek <= 0 ? 53 : maxWeek;
    for (final item in documents.entries) {
      final table = _graduateScheduleTable(item.value);
      if (table == null) continue;
      final rows = table.querySelectorAll('tr');
      if (rows.isEmpty) continue;
      final dayColumns = _graduateScheduleDayColumns(rows.first);
      if (dayColumns.isEmpty) continue;
      final firstDayColumn = dayColumns.keys.reduce(
        (left, right) => left < right ? left : right,
      );
      var fallbackPeriod = 0;
      for (final row in rows.skip(1)) {
        final cells = row.children
            .where((cell) => cell.localName == 'td' || cell.localName == 'th')
            .toList(growable: false);
        if (cells.isEmpty) continue;
        final period = _graduateSchedulePeriod(cells) ?? ++fallbackPeriod;
        if (period > fallbackPeriod) fallbackPeriod = period;
        final dayStart = cells.length >= 9 ? 2 : 1;
        for (final entry in dayColumns.entries) {
          final cellIndex = dayStart + entry.key - firstDayColumn;
          if (cellIndex < 0 || cellIndex >= cells.length) continue;
          final cell = cells[cellIndex];
          for (final activity in _graduateScheduleActivities(cell, item.key)) {
            final parsedWeeks = activity.weeks
                .where((week) => week > 0 && week <= weekLimit)
                .toList(growable: false);
            final weeks = parsedWeeks.isEmpty ? <int>[item.key] : parsedWeeks;
            final key = [
              entry.value,
              activity.courseSequence,
              activity.courseName,
              activity.teacher,
              activity.location,
            ].join('\u0000');
            final group = groups.putIfAbsent(
              key,
              () => _GraduateScheduleGroup(
                weekday: entry.value,
                activity: activity,
              ),
            );
            final rowSpan =
                int.tryParse(cell.attributes['rowspan']?.trim() ?? '') ?? 1;
            final activityPeriods =
                activity.periods.isNotEmpty
                    ? activity.periods
                    : [
                      for (var index = 0; index < rowSpan; index++)
                        period + index,
                    ];
            group.periods.addAll(activityPeriods);
            group.weeks.addAll(weeks);
          }
        }
      }
    }

    final entries = <AcademicPersonalScheduleEntry>[];
    for (final group in groups.values) {
      entries.addAll(group.toEntries());
    }
    entries.sort((left, right) {
      final byDay = left.weekday.compareTo(right.weekday);
      if (byDay != 0) return byDay;
      final byPeriod = left.startPeriod.compareTo(right.startPeriod);
      if (byPeriod != 0) return byPeriod;
      return left.courseSequence.compareTo(right.courseSequence);
    });
    var resolvedMaxWeek = maxWeek < 1 ? 1 : maxWeek;
    for (final entry in entries) {
      for (final week in [...entry.weeks, ...entry.practiceWeeks]) {
        if (week > resolvedMaxWeek) resolvedMaxWeek = week;
      }
    }
    return AcademicPersonalSchedule(
      semesterId: semesterId.trim(),
      semesterLabel: semesterLabel.trim(),
      entries: entries.toList(growable: false),
      maxWeek: resolvedMaxWeek,
      fetchedAt: DateTime.now(),
    );
  }

  static ({String year, String term}) parseGraduateSemesterId(String id) {
    final parts = id.split(':');
    if (parts.length != 3 ||
        parts.first != 'yjs' ||
        parts[1].isEmpty ||
        parts[2].isEmpty) {
      throw const AcademicAffairsException('研究生排课学期参数无效');
    }
    return (year: parts[1], term: parts[2]);
  }

  static List<AcademicSemesterOption> parseSemesterCalendar(Document document) {
    final text = document.body?.text ?? '';
    final selected =
        _syllabusCalendarIdPattern.firstMatch(text)?.group(1) ?? '';
    final options = <AcademicSemesterOption>[];
    for (final match in _syllabusCalendarEntryPattern.allMatches(text)) {
      final id = match.group(1) ?? '';
      final schoolYear =
          (match.group(2) ?? '')
              .replaceAll('\u0022', '')
              .replaceAll('\u0027', '')
              .trim();
      final name =
          (match.group(3) ?? '')
              .replaceAll('\u0022', '')
              .replaceAll('\u0027', '')
              .trim();
      if (id.isEmpty || schoolYear.isEmpty || name.isEmpty) continue;
      options.add(
        AcademicSemesterOption(
          id: id,
          label: '$schoolYear 学年$name 学期',
          selected: id == selected,
        ),
      );
    }
    return options;
  }

  static SyllabusPageData parseSyllabus(Document document) {
    final table = _syllabusTable(document);
    if (table == null) {
      throw const AcademicAffairsException('未找到排课查询结果');
    }
    final headers = _findHeaderRow(table, const [
      '课程序号',
      '课程代码',
      '课程名称',
      '课程类别',
      '教学班',
      '教师',
      '实际',
      '上限',
      '学分',
      '学时/周',
      '起止周',
    ]);
    final pageInfo = _syllabusPageInfo(document);
    final pageNo = pageInfo[0];
    final pageSize = pageInfo[1];
    final total = pageInfo[2];
    final contents = _parseSyllabusContents(document);
    final rows = <SyllabusCourseRow>[];
    for (final row in table.querySelectorAll('tr')) {
      final checkbox = row.querySelector('input[name="lesson.id"]');
      final lessonId = checkbox?.attributes['value']?.trim() ?? '';
      final values = _cells(row);
      if (lessonId.isEmpty || values.length <= 1) continue;
      final data = _rowData(headers, values.sublist(1));
      final sequence = data['课程序号'] ?? '';
      final name = data['课程名称'] ?? '';
      if (sequence.isEmpty && name.isEmpty) continue;
      rows.add(
        SyllabusCourseRow(
          lessonId: lessonId,
          courseSequence: sequence,
          courseCode: data['课程代码'] ?? '',
          courseName: name,
          category: data['课程类别'] ?? '',
          teachClass: data['教学班'] ?? '',
          teachers: data['教师'] ?? '',
          actualCount: data['实际'] ?? '',
          limitCount: data['上限'] ?? '',
          credits: data['学分'] ?? '',
          periodPerWeek: data['学时/周'] ?? '',
          weekState: data['起止周'] ?? '',
          scheduleEntries: contents[lessonId] ?? const [],
        ),
      );
    }
    return SyllabusPageData(
      pageNo: pageNo,
      pageSize: pageSize,
      total: total,
      hasMore: pageNo * pageSize < total,
      rows: rows,
    );
  }

  static SyllabusPageData parseGraduateSyllabus(
    Document document, {
    required int pageNo,
  }) {
    final table = _tableWithHeaders(document, const [
      '学年',
      '学期',
      '开课号',
      '课程名称',
      '开课学院',
      '主讲教师',
      '上课时间地点',
    ]);
    if (table == null) {
      throw const AcademicAffairsException('未找到研究生排课查询结果');
    }
    final headers = _findHeaderRow(table, const [
      '学年',
      '学期',
      '开课号',
      '课程名称',
      '开课学院',
      '主讲教师',
      '上课时间地点',
    ]);
    final rows = <SyllabusCourseRow>[];
    for (final row in table.querySelectorAll('tr')) {
      final values = _cells(row);
      if (values.isEmpty || values.first == '学年') continue;
      final data = _rowData(headers, values);
      final openingNo = data['开课号'] ?? '';
      final name = data['课程名称'] ?? '';
      if (openingNo.isEmpty && name.isEmpty) continue;
      final rawSchedule = data['上课时间地点'] ?? '';
      rows.add(
        SyllabusCourseRow(
          lessonId: 'yjs:$pageNo:${rows.length}:$openingNo',
          courseSequence: openingNo,
          courseCode: '',
          courseName: name,
          category: data['开课学院'] ?? '',
          teachClass: '',
          teachers: data['主讲教师'] ?? '',
          actualCount: '',
          limitCount: data['容量'] ?? '',
          credits: data['学分'] ?? '',
          periodPerWeek: data['学时'] ?? '',
          weekState: '',
          language: data['上课语言'] ?? '',
          campus: data['上课校区'] ?? '',
          scheduleEntries: _parseScheduleEntries(rawSchedule),
        ),
      );
    }
    final totalMatch = RegExp(
      '共\\s*(\\d+)\\s*条',
    ).firstMatch(document.body?.text ?? '');
    final total = int.tryParse(totalMatch?.group(1) ?? '') ?? rows.length;
    const pageSize = 20;
    return SyllabusPageData(
      pageNo: pageNo,
      pageSize: pageSize,
      total: total,
      hasMore:
          totalMatch != null
              ? pageNo * pageSize < total
              : rows.length >= pageSize,
      rows: rows,
    );
  }

  static Element? _syllabusTable(Document document) =>
      _tableWithHeaders(document, const [
        '课程序号',
        '课程代码',
        '课程名称',
        '课程类别',
        '教学班',
        '教师',
        '实际',
        '上限',
        '学分',
        '学时/周',
        '起止周',
      ]);

  static List<int> _syllabusPageInfo(Document document) {
    final text = document.body?.text ?? '';
    final match = _syllabusPageInfoPattern.firstMatch(text);
    if (match == null) return const [1, 20, 0];
    final pageNo = int.tryParse(match.group(1) ?? '');
    final pageSize = int.tryParse(match.group(2) ?? '');
    final total = int.tryParse(match.group(3) ?? '');
    if (pageNo == null || pageSize == null || total == null) {
      return const [1, 20, 0];
    }
    return [pageNo, pageSize, total];
  }

  static Map<String, List<SyllabusScheduleEntry>> _parseSyllabusContents(
    Document document,
  ) {
    final text = document.body?.text ?? '';
    final contents = <String, List<SyllabusScheduleEntry>>{};
    for (final match in _syllabusContentsPattern.allMatches(text)) {
      final lessonId = match.group(1) ?? '';
      final raw = match.group(2) ?? '';
      if (lessonId.isEmpty) continue;
      contents[lessonId] = _parseScheduleEntries(raw);
    }
    return contents;
  }

  static List<SyllabusScheduleEntry> _parseScheduleEntries(String raw) {
    final normalized = raw
        .replaceAll(RegExp('<br\\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ');
    final entries = <SyllabusScheduleEntry>[];
    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      entries.add(_parseScheduleEntry(trimmed));
    }
    return entries;
  }

  static SyllabusScheduleEntry _parseScheduleEntry(String line) {
    final weekdayMatch = RegExp('星期[一二三四五六日天]').firstMatch(line);
    final weekdayLabel = weekdayMatch?.group(0) ?? '';
    final periodMatch = RegExp('\\d{1,2}-\\d{1,2}').firstMatch(line);
    final periodText = periodMatch?.group(0) ?? '';
    final weeksMatch = RegExp('\\[([^\\]]+)\\]').firstMatch(line);
    final weeksText = weeksMatch?.group(1)?.trim() ?? '';
    final teachers =
        weekdayLabel.isEmpty ? '' : line.split(weekdayLabel).first.trim();
    return SyllabusScheduleEntry(
      teachers: teachers,
      weekdayLabel: weekdayLabel,
      periodText: periodText,
      weeksText: weeksText,
      location: AcademicSchedulePlace.extractLocation(line) ?? '',
      rawText: line,
    );
  }

  static final _syllabusDefaultSemesterPattern = RegExp('value:\\s*([0-9]+)');
  static final _syllabusCalendarIdPattern = RegExp('semesterId:\\s*([0-9]+)');
  static final _syllabusCalendarEntryPattern = RegExp(
    '\\{id:\\s*([0-9]+)\\s*,\\s*schoolYear:\\s*([^,}]+)\\s*,\\s*name:\\s*([^,}]+)\\s*\\}',
  );
  static final _syllabusPageInfoPattern = RegExp(
    r'pageInfo\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',
  );
  static final _syllabusContentsPattern = RegExp(
    'contents\\[\u0027([^\u0027]+)\u0027\\]=\u0027([^\u0027]*)\u0027',
  );

  static AcademicGradeReport parseGrades(Document document) {
    final summaryTable = _tableWithHeaders(document, const ['学年度', '平均绩点']);
    if (summaryTable == null) {
      throw const AcademicAffairsException('未找到成绩汇总表');
    }

    AcademicEnrollmentSummary? enrollmentSummary;
    final termSummaries = <AcademicTermSummary>[];
    var statisticsAt = '';
    for (final row in summaryTable.querySelectorAll('tr')) {
      final cells = _cells(row);
      if (cells.length >= 5 && _isAcademicYear(cells.first)) {
        termSummaries.add(
          AcademicTermSummary(
            academicYear: cells[0],
            semester: cells[1],
            courseCount: cells[2],
            totalCredits: cells[3],
            averageGpa: cells[4],
          ),
        );
      } else if (cells.length >= 4 && cells.first == '在校汇总') {
        enrollmentSummary = AcademicEnrollmentSummary(
          courseCount: cells[1],
          totalCredits: cells[2],
          averageGpa: cells[3],
        );
      } else if (cells.isNotEmpty && cells.first.startsWith('统计时间')) {
        statisticsAt = cells.first.replaceFirst('统计时间:', '').trim();
      }
    }

    final gradeTables = document
        .querySelectorAll('table')
        .where(
          (table) => _findHeaderRow(table, const ['课程代码', '课程名称']).isNotEmpty,
        )
        .toList(growable: false);
    if (gradeTables.isEmpty) {
      throw const AcademicAffairsException('未找到课程成绩表');
    }

    final majorGrades = _parseGradeTable(
      gradeTables.first,
      CourseGradeScope.major,
    );
    final minorGrades =
        gradeTables.length > 1
            ? _parseGradeTable(gradeTables[1], CourseGradeScope.minor)
            : const <AcademicCourseGrade>[];
    return AcademicGradeReport(
      enrollmentSummary: enrollmentSummary,
      termSummaries: termSummaries,
      majorGrades: majorGrades,
      minorGrades: minorGrades,
      statisticsAt: statisticsAt,
    );
  }

  static AcademicGradeReport parseGraduateGrades(Document document) {
    final table = _tableWithHeaders(document, const [
      '开课学年',
      '开课学期',
      '课程编号',
      '课程名称',
      '成绩',
    ]);
    if (table == null) {
      throw const AcademicAffairsException('未找到研究生成绩表');
    }
    final headers = _findHeaderRow(table, const [
      '开课学年',
      '开课学期',
      '课程编号',
      '课程名称',
      '成绩',
    ]);
    final grades = <AcademicCourseGrade>[];
    for (final row in table.querySelectorAll('tr')) {
      final values = _cells(row);
      if (values.isEmpty || values.first == '开课学年') continue;
      final data = _rowData(headers, values);
      final code = data['课程编号'] ?? '';
      final name = data['课程名称'] ?? '';
      if (code.isEmpty && name.isEmpty) continue;
      final year = data['开课学年'] ?? '';
      final term = data['开课学期'] ?? '';
      grades.add(
        AcademicCourseGrade(
          scope: CourseGradeScope.major,
          term: [year, term].where((value) => value.isNotEmpty).join(' '),
          courseCode: code,
          courseSequence: code,
          courseName: name,
          category: '',
          credit: data['学分'] ?? '',
          midtermScore: '',
          finalExamScore: '',
          usualScore: '',
          totalScore: data['成绩'] ?? '',
          labScore: '',
          finalScore: data['成绩'] ?? '',
          gradePoint: '',
          makeupScore: data['补考成绩'] ?? '',
          retakeStatus: data['是否重修'] ?? '',
          teacher: data['任课教师'] ?? '',
          scoreSystem: data['成绩记分制'] ?? '',
          note: data['备注'] ?? '',
        ),
      );
    }
    return AcademicGradeReport(
      enrollmentSummary: null,
      termSummaries: const [],
      majorGrades: grades,
      minorGrades: const [],
      statisticsAt: '',
    );
  }

  static List<AcademicExam> parseExams(Document document) {
    final table = _tableWithHeaders(document, const [
      '课程序号',
      '课程名称',
      '考试日期',
      '考场座位号',
    ]);
    if (table == null) {
      throw const AcademicAffairsException('未找到考试安排表');
    }
    final headers = _findHeaderRow(table, const [
      '课程序号',
      '课程名称',
      '考试日期',
      '考场座位号',
    ]);
    final exams = <AcademicExam>[];
    for (final row in table.querySelectorAll('tr')) {
      final values = _cells(row);
      if (values.isEmpty || values.first == '课程序号') continue;
      final data = _rowData(headers, values);
      final sequence = data['课程序号'] ?? '';
      final name = data['课程名称'] ?? '';
      if (sequence.isEmpty && name.isEmpty) continue;
      exams.add(
        AcademicExam(
          courseSequence: sequence,
          courseName: name,
          examType: data['考试类别'] ?? '',
          examDate: data['考试日期'] ?? '',
          arrangement: data['考试安排'] ?? '',
          location: data['考试地点'] ?? '',
          seat: data['考场座位号'] ?? '',
          status: data['考试情况'] ?? '',
          note: data['其它说明'] ?? '',
        ),
      );
    }
    exams.sort((left, right) {
      if (left.isScheduled != right.isScheduled) {
        return left.isScheduled ? -1 : 1;
      }
      return left.examDate.compareTo(right.examDate);
    });
    return exams;
  }

  /// 考试批次下拉选项（`select[name="examBatch.id"]`），值 0 表示全部批次。
  static List<AcademicExamBatchOption> examBatchOptions(Document document) {
    final select = document.querySelector('select[name="examBatch.id"]');
    if (select == null) return const [];
    final options = <AcademicExamBatchOption>[];
    for (final option in select.querySelectorAll('option')) {
      final value = option.attributes['value']?.trim() ?? '';
      if (value.isEmpty) continue;
      options.add(
        AcademicExamBatchOption(
          id: value,
          label: _text(option),
          selected: option.attributes.containsKey('selected'),
        ),
      );
    }
    return options;
  }

  static List<AcademicSemesterOption> _graduateStudentSemesterOptions(
    Document document, {
    required String yearName,
    required String termName,
    String? selectedId,
  }) {
    final yearSelect = document.querySelector('select[name="$yearName"]');
    final termSelect = document.querySelector('select[name="$termName"]');
    if (yearSelect == null || termSelect == null) return const [];
    final years = yearSelect
        .querySelectorAll('option')
        .where(
          (option) => (option.attributes['value']?.trim() ?? '').isNotEmpty,
        )
        .toList(growable: false);
    final terms = termSelect
        .querySelectorAll('option')
        .where(
          (option) => (option.attributes['value']?.trim() ?? '').isNotEmpty,
        )
        .toList(growable: false);
    final selectedYear = _selectedValue(document, yearName);
    final selectedTerm = _selectedValue(document, termName);
    final selected = selectedId?.trim();
    return [
      for (final year in years)
        for (final term in terms)
          AcademicSemesterOption(
            id:
                'yjs:${year.attributes['value']!.trim()}:${term.attributes['value']!.trim()}',
            label: '${_text(year)}学年${_text(term)}',
            selected:
                selected ==
                    'yjs:${year.attributes['value']!.trim()}:${term.attributes['value']!.trim()}' ||
                (selected == null &&
                    year.attributes['value']?.trim() == selectedYear &&
                    term.attributes['value']?.trim() == selectedTerm),
          ),
    ];
  }

  static String _selectedValue(Document document, String name) {
    final select = document.querySelector('select[name="$name"]');
    if (select == null) return '';
    final selected = select.querySelector('option[selected]');
    final fallback = select.querySelector('option[value]');
    return (selected ?? fallback)?.attributes['value']?.trim() ?? '';
  }

  static bool _graduateExamHeader(List<String> headers) {
    final hasName = _headerIndex(headers, const ['课程名称', '课程名']) >= 0;
    final hasDate =
        _headerIndex(headers, const ['考试日期', '考试时间', '日期', '时间']) >= 0;
    return hasName && hasDate;
  }

  static int _headerIndex(List<String> headers, List<String> aliases) {
    for (var index = 0; index < headers.length; index++) {
      final header = headers[index].replaceAll(RegExp(r'\s+'), '');
      for (final alias in aliases) {
        final normalized = alias.replaceAll(RegExp(r'\s+'), '');
        if (header == normalized) return index;
      }
    }
    for (var index = 0; index < headers.length; index++) {
      final header = headers[index].replaceAll(RegExp(r'\s+'), '');
      for (final alias in aliases) {
        final normalized = alias.replaceAll(RegExp(r'\s+'), '');
        if (header.contains(normalized)) return index;
      }
    }
    return -1;
  }

  static String _valueAt(List<String> values, int index) {
    if (index < 0 || index >= values.length) return '';
    return values[index].trim();
  }

  static bool _sameValues(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static ({String date, String arrangement}) _splitGraduateExamDateTime(
    String dateValue,
    String arrangementValue,
  ) {
    var date = dateValue.trim();
    var arrangement = arrangementValue.trim();
    final match = RegExp(
      r'(\d{4})\s*(?:[-/.年])\s*(\d{1,2})\s*(?:[-/.月])\s*(\d{1,2})日?',
    ).firstMatch(date);
    if (match != null) {
      final year = match.group(1)!;
      final month = match.group(2)!.padLeft(2, '0');
      final day = match.group(3)!.padLeft(2, '0');
      date = '$year-$month-$day';
      if (arrangement.isEmpty) {
        arrangement =
            dateValue
                .substring(match.end)
                .replaceFirst(RegExp(r'^[\s，,：:]+'), '')
                .trim();
      }
    }
    return (date: date, arrangement: arrangement);
  }

  static Element? _graduateScheduleTable(Document document) {
    for (final table in document.querySelectorAll('table')) {
      final header = table.querySelector('tr');
      if (header == null) continue;
      final values = _cells(header);
      final weekdayCount =
          values.where((value) => _weekdayNumber(value) != null).length;
      if (weekdayCount >= 5) return table;
    }
    return null;
  }

  static Map<int, int> _graduateScheduleDayColumns(Element header) {
    final columns = <int, int>{};
    final cells = header.children
        .where((cell) => cell.localName == 'th' || cell.localName == 'td')
        .toList(growable: false);
    for (var index = 0; index < cells.length; index++) {
      final weekday = _weekdayNumber(_text(cells[index]));
      if (weekday != null) columns[index] = weekday;
    }
    return columns;
  }

  static int? _weekdayNumber(String value) {
    final text = value.trim();
    const labels = <String, int>{
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    for (final entry in labels.entries) {
      if (text.contains('星期${entry.key}') || text.contains('周${entry.key}')) {
        return entry.value;
      }
    }
    return null;
  }

  static int? _graduateSchedulePeriod(List<Element> cells) {
    for (final cell in cells) {
      final match = RegExp(r'第\s*(\d+)\s*节').firstMatch(_text(cell));
      final period = int.tryParse(match?.group(1) ?? '');
      if (period != null && period > 0 && period <= 24) return period;
    }
    return null;
  }

  static List<int> _graduateSchedulePeriodRange(String line) {
    if (line.trim().isEmpty) return const [];
    final range = RegExp(
      r'第\s*(\d+)\s*节?\s*(?:--?|—|–|~|至|到)\s*第?\s*(\d+)\s*节',
    ).firstMatch(line);
    if (range != null) {
      final start = int.tryParse(range.group(1) ?? '');
      final end = int.tryParse(range.group(2) ?? '');
      if (start != null &&
          end != null &&
          start > 0 &&
          end >= start &&
          end <= 24) {
        return [for (var period = start; period <= end; period++) period];
      }
    }
    final matches = RegExp(r'第\s*(\d+)\s*节').allMatches(line).toList();
    if (matches.isEmpty) return const [];
    final start = int.tryParse(matches.first.group(1) ?? '');
    final end = int.tryParse(
      (matches.length > 1 ? matches.last : matches.first).group(1) ?? '',
    );
    if (start == null || end == null || start < 1 || end < start || end > 24) {
      return const [];
    }
    return [for (var period = start; period <= end; period++) period];
  }

  static List<_GraduateScheduleActivity> _graduateScheduleActivities(
    Element cell,
    int currentWeek,
  ) {
    final anchors = cell
        .querySelectorAll('a')
        .where(
          (anchor) => (anchor.attributes['href'] ?? '').contains('xkkcxx.htm'),
        )
        .toList(growable: false);
    final elements = anchors.isEmpty ? [cell] : anchors;
    final result = <_GraduateScheduleActivity>[];
    for (final element in elements) {
      final lines = _graduateScheduleLines(element);
      if (lines.isEmpty) continue;
      final strong = element.querySelector('strong');
      final name = (strong == null ? lines.first : _text(strong)).trim();
      if (name.isEmpty) continue;
      final weekLine = lines.firstWhere(
        _hasGraduateWeekMarker,
        orElse: () => '',
      );
      final weeks =
          weekLine.isEmpty
              ? <int>[currentWeek]
              : _graduateWeekValues(weekLine, currentWeek);
      final timeLine = lines.firstWhere(
        (line) =>
            line != weekLine &&
            (_weekdayNumber(line) != null ||
                RegExp(r'\d{1,2}:\d{2}').hasMatch(line)),
        orElse: () => '',
      );
      final periodLine = lines.firstWhere(
        (line) => line != weekLine && RegExp(r'第\s*\d+\s*节').hasMatch(line),
        orElse: () => '',
      );
      final periods = _graduateSchedulePeriodRange(periodLine);
      final remaining = [
        for (final line in lines.skip(1))
          if (line != weekLine &&
              line != timeLine &&
              line != periodLine &&
              line.trim().isNotEmpty)
            line.trim(),
      ];
      final location =
          remaining.isEmpty
              ? (AcademicSchedulePlace.extractLocation(element.text) ?? '')
              : remaining.last;
      final teacher =
          remaining.length >= 2 ? remaining[remaining.length - 2] : '';
      final href = element.attributes['href'] ?? '';
      final courseSequence =
          Uri.tryParse(href)?.queryParameters['kcId']?.trim() ?? name;
      final resolvedCourseSequence =
          courseSequence.isEmpty ? name : courseSequence;
      final identity = normalizeScheduleCourseIdentity(
        courseName: name,
        courseSequence: resolvedCourseSequence,
      );
      final sourceId =
          'graduate:${jsonEncode([resolvedCourseSequence, teacher, location])}';
      result.add(
        _GraduateScheduleActivity(
          sourceId: sourceId,
          courseSequence: resolvedCourseSequence,
          courseCode: identity.code,
          courseName: identity.name,
          teacher: teacher,
          location: location,
          weeksText: weekLine,
          weeks: weeks,
          periods: periods,
        ),
      );
    }
    return result;
  }

  static List<String> _graduateScheduleLines(Element element) {
    var markup = element.innerHtml.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    markup = markup.replaceAll(RegExp(r'<[^>]+>'), '');
    final decoded = html_parser.parseFragment(markup).text ?? '';
    return decoded
        .split('\n')
        .map((line) => line.replaceAll('\u00a0', ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static List<int> _graduateWeekValues(String line, int fallbackWeek) {
    final match = RegExp(r'[（(]\s*([^）)]+)[）)]').firstMatch(line);
    final raw = (match?.group(1) ?? line).trim();
    if (raw.contains('单周')) {
      return [for (var week = 1; week <= 53; week += 2) week];
    }
    if (raw.contains('双周')) {
      return [for (var week = 2; week <= 53; week += 2) week];
    }
    if (raw.contains('每周') || raw.contains('全周')) {
      return [for (var week = 1; week <= 53; week++) week];
    }
    final values = <int>{};
    for (final range in RegExp(r'(\d+)\s*[-~至到]\s*(\d+)').allMatches(raw)) {
      final start = int.tryParse(range.group(1) ?? '');
      final end = int.tryParse(range.group(2) ?? '');
      if (start == null || end == null) continue;
      for (var week = start; week <= end && week <= 53; week++) {
        if (week > 0) values.add(week);
      }
    }
    if (values.isEmpty) {
      for (final value in RegExp(r'\d+').allMatches(raw)) {
        final week = int.tryParse(value.group(0) ?? '');
        if (week != null && week > 0 && week <= 53) values.add(week);
      }
    }
    if (values.isEmpty) values.add(fallbackWeek);
    return values.toList()..sort();
  }

  static bool _hasGraduateWeekMarker(String line) {
    return RegExp(r'[（(][^）)]+[）)]').hasMatch(line) ||
        RegExp(r'\d+\s*[-~至到]\s*\d+\s*周').hasMatch(line) ||
        line.contains('单周') ||
        line.contains('双周') ||
        line.contains('每周') ||
        line.contains('全周');
  }

  static List<AcademicCourseGrade> _parseGradeTable(
    Element table,
    CourseGradeScope scope,
  ) {
    final headers = _findHeaderRow(table, const ['课程代码', '课程名称']);
    final grades = <AcademicCourseGrade>[];
    for (final row in table.querySelectorAll('tr')) {
      final values = _cells(row);
      if (values.isEmpty || values.first == '学年学期') continue;
      final data = _rowData(headers, values);
      final courseName = data['课程名称'] ?? '';
      final courseCode = data['课程代码'] ?? '';
      if (courseName.isEmpty && courseCode.isEmpty) continue;
      grades.add(
        AcademicCourseGrade(
          scope: scope,
          term: data['学年学期'] ?? '',
          courseCode: courseCode,
          courseSequence: data['课程序号'] ?? '',
          courseName: courseName,
          category: data['课程类别'] ?? '',
          credit: data['学分'] ?? '',
          midtermScore: data['期中成绩'] ?? '',
          finalExamScore: data['期末成绩'] ?? '',
          usualScore: data['平时成绩'] ?? '',
          totalScore: data['总评成绩'] ?? '',
          labScore: data['实验成绩'] ?? '',
          finalScore: data['最终'] ?? '',
          gradePoint: data['绩点'] ?? '',
        ),
      );
    }
    return grades;
  }

  static String _calendarValue(Document document, String selector) {
    final element = document.querySelector(selector);
    if (element == null) return '';
    return (element.attributes['value'] ?? _text(element)).trim();
  }

  static Element? _tableWithHeaders(Document document, List<String> required) {
    for (final table in document.querySelectorAll('table')) {
      if (_findHeaderRow(table, required).isNotEmpty) return table;
    }
    return null;
  }

  static List<String> _findHeaderRow(Element table, List<String> required) {
    for (final row in table.querySelectorAll('tr')) {
      final values = _cells(row);
      if (required.every(values.contains)) return values;
    }
    return const [];
  }

  static List<String> _cells(Element row) {
    return row.children
        .where((cell) => cell.localName == 'td' || cell.localName == 'th')
        .map(_text)
        .toList(growable: false);
  }

  static Map<String, String> _rowData(
    List<String> headers,
    List<String> values,
  ) {
    final data = <String, String>{};
    for (var index = 0; index < headers.length; index++) {
      data[headers[index]] = index < values.length ? values[index] : '';
    }
    return data;
  }

  static bool _isAcademicYear(String value) =>
      RegExp(r'^\d{4}-\d{4}$').hasMatch(value);

  static String _text(Element element) =>
      element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _GraduateExamTable {
  final Element table;
  final List<String> headers;

  const _GraduateExamTable({required this.table, required this.headers});
}

class _GraduateScheduleActivity {
  final String sourceId;
  final String courseSequence;
  final String courseCode;
  final String courseName;
  final String teacher;
  final String location;
  final String weeksText;
  final List<int> weeks;
  final List<int> periods;

  const _GraduateScheduleActivity({
    required this.sourceId,
    required this.courseSequence,
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.location,
    required this.weeksText,
    required this.weeks,
    required this.periods,
  });
}

class _GraduateScheduleGroup {
  final int weekday;
  final _GraduateScheduleActivity activity;
  final Set<int> periods = <int>{};
  final Set<int> weeks = <int>{};

  _GraduateScheduleGroup({required this.weekday, required this.activity});

  List<AcademicPersonalScheduleEntry> toEntries() {
    final sortedPeriods = periods.toList()..sort();
    if (sortedPeriods.isEmpty) return const [];
    final sortedWeeks = weeks.toList()..sort();
    final weeksText =
        activity.weeksText.trim().isNotEmpty
            ? activity.weeksText.trim()
            : _graduateWeeksText(sortedWeeks);
    final entries = <AcademicPersonalScheduleEntry>[];
    var start = sortedPeriods.first;
    var end = start;
    var segmentIndex = 0;
    for (final period in sortedPeriods.skip(1)) {
      if (period == end + 1) {
        end = period;
        continue;
      }
      entries.add(_entry(start, end, sortedWeeks, weeksText, segmentIndex++));
      start = period;
      end = period;
    }
    entries.add(_entry(start, end, sortedWeeks, weeksText, segmentIndex));
    return entries;
  }

  AcademicPersonalScheduleEntry _entry(
    int startPeriod,
    int endPeriod,
    List<int> sortedWeeks,
    String weeksText,
    int segmentIndex,
  ) => AcademicPersonalScheduleEntry(
    sourceId: '${activity.sourceId}:weekday:$weekday:segment:$segmentIndex',
    courseSequence: activity.courseSequence,
    courseCode: activity.courseCode,
    courseName: activity.courseName,
    teacher: activity.teacher,
    location: activity.location,
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    weeksText: weeksText,
    weeks: sortedWeeks,
    practiceWeeks: const [],
  );
}

String _graduateWeeksText(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final ranges = <String>[];
  var start = weeks.first;
  var end = start;
  for (final week in weeks.skip(1)) {
    if (week == end + 1) {
      end = week;
      continue;
    }
    ranges.add(start == end ? '$start周' : '$start-$end周');
    start = week;
    end = week;
  }
  ranges.add(start == end ? '$start周' : '$start-$end周');
  return ranges.join('、');
}
