import 'dart:convert';

import '../../capabilities/text_utils.dart';
import '../academic_affairs/academic_affairs_models.dart';

/// 在已加载的树维 EAMS 页面中执行的 JavaScript 与课表 JSON 解析。
///
/// WakeUp `shuwei` 分支的结论：不重新请求接口、不解析课表 HTML DOM，
/// 直接读取页面已经生成好的 `table0` 数据对象。本实现沿用该链路。
abstract final class ShuweiScheduleExtractor {
  /// 点击 EAMS 首页菜单里“我的课表”，让首页自身的脚本以 AJAX 把查询页
  /// 片段插入 `contentDiv`，保持 jQuery/bg/underscore 在同一文档中可用。
  static const openCourseTableScript = r'''
(function () {
  if (window.__mychuCourseTableRequested === true) {
    return true;
  }

  var links = document.querySelectorAll('a[href]');
  for (var i = 0; i < links.length; i++) {
    var href = String(links[i].getAttribute('href') || '');
    if (href.indexOf('/eams/courseTableForStd.action') === -1) {
      continue;
    }

    window.__mychuCourseTableRequested = true;
    links[i].click();
    return true;
  }
  return false;
})();
''';

  /// 阻止查询页通过原生 `form.submit()` 做整页跳转；页面自己的
  /// `searchTable()` 使用 `bg.form.submit` 的 AJAX 路径，不受影响。
  static const installSubmitGuardScript = r'''
(function () {
  if (window.__mychuOriginalFormSubmit) {
    window.__mychuBlockSubmit = true;
    return true;
  }
  var original = HTMLFormElement.prototype.submit;
  window.__mychuOriginalFormSubmit = original;
  HTMLFormElement.prototype.submit = function () {
    if (window.__mychuBlockSubmit === true) {
      return false;
    }
    return original.apply(this, arguments);
  };
  if (window.bg &&
      window.bg.form &&
      typeof window.bg.form.submit === 'function') {
    var originalBgSubmit = window.bg.form.submit;
    window.__mychuOriginalBgSubmit = originalBgSubmit;
    window.bg.form.submit = function (form, action, target) {
      if (window.__mychuBlockSubmit === true && !target) {
        return false;
      }
      return originalBgSubmit.apply(this, arguments);
    };
  }
  window.__mychuBlockSubmit = true;
  return true;
})();
''';

  /// 查询页已插入首页并完成基础初始化。
  static const pageReadyScript = r'''
(function () {
  try {
    if (document.readyState !== 'complete') return false;
    if (typeof jQuery !== 'function') return false;
    if (typeof bg === 'undefined' || bg === null) return false;
    if (typeof searchTable !== 'function') return false;
    if (!document.querySelector('#courseTableType')) return false;
    if (!document.querySelector('#semesterCalendar_target')) return false;
    return true;
  } catch (error) {
    return false;
  }
})();
''';

  /// 读取当前学期、学期标签与可选学期。
  static const semesterContextScript = r'''
(function () {
  try {
  var doc = document;

  function valueOf(doc, selector) {
    var element = doc.querySelector(selector);
    return element && element.value ? String(element.value).trim() : '';
  }

  function labelOf(doc) {
    var inputs = doc.querySelectorAll('input[value]');
    for (var i = 0; i < inputs.length; i++) {
      var value = String(inputs[i].value || '').trim();
      if (value.indexOf('学年') !== -1 && value.indexOf('学期') !== -1) {
        return value;
      }
    }
    var year = valueOf(doc, '#semesterCalendar_year');
    var term = valueOf(doc, '#semesterCalendar_term');
    return (year + ' ' + term).trim();
  }

  var options = [];
  var semesterId = valueOf(doc, '#semesterCalendar_target');
  var year = valueOf(doc, '#semesterCalendar_year');
  var cells = doc.querySelectorAll('#semesterCalendar_termTb td[val]');
  for (var c = 0; c < cells.length; c++) {
    var cellId = String(cells[c].getAttribute('val') || '').trim();
    if (!cellId) continue;
    var term = String(cells[c].textContent || '').trim();
    options.push({
      id: cellId,
      label: (year && term.indexOf(year) === -1 ? year + ' ' : '') + term,
      selected: cellId === semesterId
    });
  }

  // 老版 semesterCalendar 插件只把当前学年渲染进 termTb，但会把
  // dataQuery 返回的完整学期目录存到触发插件的 input.calendar-text 上。
  if (typeof jQuery === 'function') {
    var storedSemesters = null;
    var calendarInputs = doc.querySelectorAll('input.calendar-text');
    for (var ci = 0; ci < calendarInputs.length; ci++) {
      var candidate = jQuery(calendarInputs[ci]).data('semesters');
      if (candidate && typeof candidate === 'object') {
        storedSemesters = candidate;
        break;
      }
    }
    if (!storedSemesters) {
      var legacySemesters = jQuery('#semesterCalendar_target').data('semesters');
      if (legacySemesters && typeof legacySemesters === 'object') {
        storedSemesters = legacySemesters;
      }
    }
    if (storedSemesters && typeof storedSemesters === 'object') {
      options = [];
      var storedKeys = Object.keys(storedSemesters);
      for (var sk = 0; sk < storedKeys.length; sk++) {
        var storedList = storedSemesters[storedKeys[sk]];
        if (!storedList || !storedList.length) continue;
        for (var si = 0; si < storedList.length; si++) {
          var storedItem = storedList[si];
          if (!storedItem || !storedItem.id) continue;
          var storedId = String(storedItem.id);
          var schoolYear = String(storedItem.schoolYear || '');
          var termName = String(storedItem.name || '');
          options.push({
            id: storedId,
            label: (schoolYear && termName)
                ? schoolYear + '学年第' + termName + '学期'
                : schoolYear + termName,
            selected: storedId === semesterId
          });
        }
      }
    }
  }

  var label = labelOf(doc);
  if (semesterId || options.length > 0 || label) {
    if (options.length === 0 && semesterId) {
      options.push({id: semesterId, label: label, selected: true});
    }
    return JSON.stringify({
      semesterId: semesterId,
      semesterLabel: label,
      semesters: options
    });
  }
    return null;
  } catch (error) {
    return null;
  }
})();
''';

  /// 设置课表范围和目标学期后调用查询页自己的 `searchTable()`，以 AJAX
  /// 方式把课表渲染进 `contentDiv`，避免整页跳转后丢失 jQuery/bg/table0。
  static String selectScheduleScript(
    String semesterId, {
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) {
    final encodedSemester = jsonEncode(semesterId.trim());
    final encodedKind = jsonEncode(
      scope == AcademicScheduleScope.administrativeClass ? 'class' : 'std',
    );
    return '''
(function () {
  var requestedSemester = $encodedSemester;
  var requestedKind = $encodedKind;
  if (!requestedSemester) return false;
  var kind = document.querySelector('#courseTableType');
  var target = document.querySelector(
    '#semesterCalendar_target, input[name="semester.id"]'
  );
  if (!kind || !target) return false;
  kind.value = requestedKind;
  if (kind.value !== requestedKind) return false;
  target.value = requestedSemester;
  if (typeof searchTable === 'function') {
    window.__mychuScheduleQueryPending = true;
    jQuery(document).off('ajaxComplete.mychuSchedule');
    jQuery(document).on(
      'ajaxComplete.mychuSchedule',
      function (event, xhr, settings) {
        var url = String((settings && settings.url) || '');
        if (url.indexOf('courseTableForStd!courseTable.action') === -1) {
          return;
        }
        var data = settings && settings.data;
        var matches = false;
        if (typeof data === 'string') {
          matches = data.indexOf('setting.kind=' + requestedKind) !== -1;
        } else if (data && typeof data === 'object') {
          matches = String(data['setting.kind'] || '') === requestedKind;
        }
        if (matches) window.__mychuScheduleQueryPending = false;
      }
    );
    try {
      if (typeof table0 !== 'undefined') table0 = null;
    } catch (error) {}
    var frames = document.getElementsByTagName('iframe');
    for (var i = 0; i < frames.length; i++) {
      try {
        if (typeof frames[i].contentWindow.table0 !== 'undefined') {
          frames[i].contentWindow.table0 = null;
        }
      } catch (error) {}
    }
    searchTable();
    return true;
  }
  return false;
})();
''';
  }

  static String selectSemesterScript(String semesterId) =>
      selectScheduleScript(semesterId);

  /// 页面已生成可导入的 `table0`。
  static const table0ReadyScript = r'''
(function () {
  if (window.__mychuScheduleQueryPending === true) return false;
  try {
    if (typeof table0 !== 'undefined' &&
        table0 !== null &&
        Array.isArray(table0.activities)) {
      return true;
    }
  } catch (error) {
    return false;
  }
  var frames = document.getElementsByTagName('iframe');
  for (var i = 0; i < frames.length; i++) {
    try {
      var frameTable = frames[i].contentWindow.table0;
      if (typeof frameTable !== 'undefined' &&
          frameTable !== null &&
          Array.isArray(frameTable.activities)) {
        return true;
      }
    } catch (error) {
      // Ignore cross-origin frames.
    }
  }
  return false;
})();
''';

  /// WakeUp `shuwei` 分支的 `save2json()`：读取页面内 `table0` 并序列化。
  static const table0Script = r'''
(function () {
  function save2json() {
    var rawdata = undefined;
    var mode = undefined;

    function check_page_allow() {
      try {
        rawdata = table0;
        mode = "eams";
        if (window.hasOwnProperty("unitCount")) {
          rawdata.unitCount = unitCount;
        }
        return true;
      } catch (error) {
        // Continue with window.table0 lookup.
      }

      try {
        rawdata = window.table0;
        if (window.hasOwnProperty("unitCount")) {
          rawdata.unitCount = unitCount;
        }
        if (typeof rawdata !== "undefined") {
          mode = "eams";
          return true;
        }
      } catch (error) {
        // Continue with iframe lookup.
      }

      var ifrs = document.getElementsByTagName("iframe");
      for (var i = 0; i < ifrs.length; i++) {
        try {
          rawdata = ifrs[i].contentWindow.table0;
          if (ifrs[i].contentWindow.hasOwnProperty("unitCount")) {
            rawdata.unitCount = ifrs[i].contentWindow.unitCount;
          }
          if (typeof rawdata !== "undefined") {
            mode = "eams";
            return true;
          }
        } catch (error) {
          // Ignore cross-origin frames.
        }
      }
      return false;
    }

    if (!Boolean(window.$) || !check_page_allow()) {
      return null;
    }
    if (mode !== "eams") {
      return null;
    }

    rawdata["marshalContents"] = [];
    var courseJson = JSON.stringify(rawdata);
    var targetStr = "index.js');";
    var afterIndex = courseJson.indexOf(targetStr);
    if (afterIndex !== -1) {
      courseJson = courseJson.substring(afterIndex + targetStr.length);
    }
    return courseJson;
  }

  return save2json();
})();
''';

  /// InAppWebView may return either the JS string itself or a JSON-encoded
  /// string, depending on the Android WebView/plugin version.
  static String? stringResult(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == 'null') return null;
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (_) {
        // The result is already the raw JS string.
      }
      return value;
    }
    return '$value';
  }

  static ShuweiSemesterContext? semesterContext(Object? value) {
    final source = stringResult(value);
    if (source == null || source.trim().isEmpty) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final data = Map<String, dynamic>.from(decoded);
    final rawSemesters = data['semesters'];
    final semesters = <AcademicSemesterOption>[];
    final selectedSemesterId = '${data['semesterId'] ?? ''}'.trim();

    void addSemesters(Iterable<Object?> rawList) {
      for (final rawSemester in rawList) {
        final option = _semesterOption(rawSemester, selectedSemesterId);
        if (option != null) semesters.add(option);
      }
    }

    if (rawSemesters is List) {
      addSemesters(rawSemesters);
    } else if (rawSemesters is Map) {
      for (final group in rawSemesters.values) {
        if (group is List) addSemesters(group);
      }
    }
    return ShuweiSemesterContext(
      semesterId: '${data['semesterId'] ?? ''}'.trim(),
      semesterLabel: '${data['semesterLabel'] ?? ''}'.trim(),
      semesters: semesters.toList(growable: false),
    );
  }

  static AcademicSemesterOption? _semesterOption(
    Object? raw,
    String selectedSemesterId,
  ) {
    if (raw is! Map) return null;
    final semester = Map<String, dynamic>.from(raw);
    final id = '${semester['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;

    var label = '${semester['label'] ?? ''}'.trim();
    if (label.isEmpty) {
      final schoolYear = '${semester['schoolYear'] ?? ''}'.trim();
      final name = '${semester['name'] ?? ''}'.trim();
      label =
          schoolYear.isEmpty || name.isEmpty
              ? schoolYear + name
              : '$schoolYear学年第$name学期';
    }
    return AcademicSemesterOption(
      id: id,
      label: label,
      selected: semester['selected'] == true || id == selectedSemesterId,
    );
  }
}

class ShuweiSemesterContext {
  final String semesterId;
  final String semesterLabel;
  final List<AcademicSemesterOption> semesters;

  const ShuweiSemesterContext({
    required this.semesterId,
    required this.semesterLabel,
    required this.semesters,
  });
}

/// 把 `table0` JSON 转换成 MyCHU 的课表模型。
abstract final class ShuweiScheduleParser {
  static const _jsonPrefixMarker = "index.js');";

  static AcademicPersonalSchedule parse(
    String source, {
    String semesterId = '',
    String semesterLabel = '',
  }) {
    final root = _decodeRoot(source);
    final rawActivities = root['activities'];
    final unitCount = _unitCount(root, (rawActivities as List?)?.length ?? 0);
    return parseActivityGrid(
      unitCount,
      rawActivities,
      semesterId: semesterId,
      semesterLabel: semesterLabel,
    );
  }

  static AcademicPersonalSchedule parseActivityGrid(
    int unitCount,
    Object? rawActivities, {
    String semesterId = '',
    String semesterLabel = '',
  }) {
    if (rawActivities is! List) {
      throw const AcademicAffairsException('树维课表数据缺少课程活动');
    }
    if (unitCount < 1 || unitCount > 24) {
      throw const AcademicAffairsException('树维课表节次数据无效');
    }

    final groups = <String, _ShuweiScheduleGroup>{};
    for (var index = 0; index < rawActivities.length; index++) {
      final weekday = index ~/ unitCount + 1;
      if (weekday > 7) break;
      final period = index % unitCount + 1;
      final rawCell = rawActivities[index];
      if (rawCell is! List) continue;

      final seenInCell = <String>{};
      for (final rawActivity in rawCell) {
        final activity = _activity(rawActivity);
        if (activity == null) continue;
        final key = _groupKey(weekday, activity);
        if (!seenInCell.add(key)) continue;
        final group = groups.putIfAbsent(
          key,
          () => _ShuweiScheduleGroup(weekday: weekday, activity: activity),
        );
        group.periods.add(period);
      }
    }

    if (groups.isEmpty) {
      return AcademicPersonalSchedule(
        semesterId: semesterId.trim(),
        semesterLabel: semesterLabel.trim(),
        entries: const [],
        maxWeek: 26,
        fetchedAt: DateTime.now(),
      );
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

    final maxWeek = entries.fold<int>(26, (current, entry) {
      final weeks = [...entry.weeks, ...entry.practiceWeeks];
      if (weeks.isEmpty) return current;
      final entryMax = weeks.reduce(_max);
      if (entryMax <= current) return current;
      return entryMax > 53 ? 53 : entryMax;
    });
    return AcademicPersonalSchedule(
      semesterId: semesterId.trim(),
      semesterLabel: semesterLabel.trim(),
      entries: entries.toList(growable: false),
      maxWeek: maxWeek,
      fetchedAt: DateTime.now(),
    );
  }

  static Map<String, dynamic> _decodeRoot(String source) {
    var normalized = source.trim();
    final marker = normalized.indexOf(_jsonPrefixMarker);
    if (marker >= 0) {
      normalized = normalized.substring(marker + _jsonPrefixMarker.length);
    }
    if (normalized.isEmpty) {
      throw const AcademicAffairsException('当前页面未检测到树维课表数据');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(normalized);
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (_) {
      throw const AcademicAffairsException('树维课表数据格式无法识别');
    }
    if (decoded is! Map) {
      throw const AcademicAffairsException('树维课表数据结构无效');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static int _unitCount(Map<String, dynamic> root, int slotCount) {
    final explicit = _intValue(root['unitCount']);
    if (explicit != null && explicit > 0) return explicit;
    if (slotCount > 0 && slotCount % 7 == 0) return slotCount ~/ 7;
    final total = _intValue(root['unitCounts']);
    if (total != null && total > 0 && total % 7 == 0) return total ~/ 7;
    return 0;
  }

  static _ShuweiActivity? _activity(Object? raw) {
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    final rawCourseName = _stringValue(data['courseName']).trim();
    final courseId = _stringValue(data['courseId']).trim();
    final lessonNo = _stringValue(data['lessonNo']).trim();
    // lessonNo is the only user-visible code exposed by Shuwei.  courseId is
    // an opaque source identifier and must never become a display/code field.
    final courseSequence = lessonNo.ifEmpty(rawCourseName);
    if (rawCourseName.isEmpty && courseSequence.isEmpty) return null;

    // Shuwei exposes a visible lesson number separately from its opaque
    // course id. Keep the former as courseCode and only use the latter as
    // part of source identity; this prevents ids such as 53765(26ZY...) from
    // leaking into every timetable surface.
    final identity = normalizeScheduleCourseIdentity(
      courseName: rawCourseName,
      courseCode: lessonNo,
      courseSequence: courseSequence,
    );

    final weeks = _weeks(_stringValue(data['vaildWeeks']));
    final teacher = _stringValue(data['teacherName']).trim();
    final location = _stringValue(
      data['roomName'],
    ).trim().ifEmpty(_stringValue(data['roomId']).trim());
    final sourceId = _sourceId(
      data,
      courseSequence: courseSequence,
      courseId: courseId,
      courseName: rawCourseName,
      teacher: teacher,
      location: location,
      weeks: weeks,
    );
    return _ShuweiActivity(
      sourceId: sourceId,
      courseSequence: courseSequence,
      courseCode: identity.code,
      courseName: identity.name,
      teacher: teacher,
      location: location,
      weeks: weeks,
      weeksText: _weeksText(weeks),
    );
  }

  static String _sourceId(
    Map<String, dynamic> data, {
    required String courseSequence,
    required String courseId,
    required String courseName,
    required String teacher,
    required String location,
    required List<int> weeks,
  }) {
    for (final field in const [
      'activityId',
      'arrangementId',
      'taskId',
      'lessonId',
      'id',
    ]) {
      final value = _stringValue(data[field]).trim();
      if (value.isNotEmpty) return 'shuwei:$field:$value';
    }
    // Some page versions expose only TaskActivity fields. Keep a stable
    // arrangement fingerprint in that case; the period segment and weekday
    // are appended when the normalized entry is emitted.
    return 'shuwei:fallback:${jsonEncode([
      courseId,
      courseSequence,
      courseName,
      teacher,
      location,
      [...weeks]..sort(),
    ])}';
  }

  static String _groupKey(int weekday, _ShuweiActivity activity) => [
    weekday,
    activity.courseSequence,
    activity.courseCode,
    activity.courseName,
    activity.teacher,
    activity.location,
    activity.weeks.join(','),
  ].join('\u0000');

  static List<int> _weeks(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const [];
    if (RegExp(r'^[01]+$').hasMatch(value)) {
      return [
        // Supwisdom reserves bit 0; bit N represents teaching week N.
        for (var index = 1; index < value.length; index++)
          if (value.codeUnitAt(index) == 49) index,
      ];
    }
    final result = <int>{};
    for (final match in RegExp(r'\d+').allMatches(value)) {
      final week = int.tryParse(match.group(0) ?? '');
      if (week != null && week > 0 && week <= 53) result.add(week);
    }
    return result.toList()..sort();
  }

  static String _weeksText(List<int> weeks) {
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

  static String _stringValue(Object? value) =>
      value is String
          ? value
          : value == null
          ? ''
          : '$value';

  static int? _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  static int _max(int left, int right) => left > right ? left : right;
}

class _ShuweiActivity {
  final String sourceId;
  final String courseSequence;
  final String courseCode;
  final String courseName;
  final String teacher;
  final String location;
  final List<int> weeks;
  final String weeksText;

  const _ShuweiActivity({
    required this.sourceId,
    required this.courseSequence,
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.location,
    required this.weeks,
    required this.weeksText,
  });
}

class _ShuweiScheduleGroup {
  final int weekday;
  final _ShuweiActivity activity;
  final Set<int> periods = <int>{};

  _ShuweiScheduleGroup({required this.weekday, required this.activity});

  List<AcademicPersonalScheduleEntry> toEntries() {
    final sorted = periods.toList()..sort();
    final entries = <AcademicPersonalScheduleEntry>[];
    if (sorted.isEmpty) return entries;

    var start = sorted.first;
    var end = start;
    var segmentIndex = 0;
    for (final period in sorted.skip(1)) {
      if (period == end + 1) {
        end = period;
        continue;
      }
      entries.add(_entry(start, end, segmentIndex++));
      start = period;
      end = period;
    }
    entries.add(_entry(start, end, segmentIndex));
    return entries;
  }

  AcademicPersonalScheduleEntry _entry(
    int startPeriod,
    int endPeriod,
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
    weeksText: activity.weeksText,
    weeks: activity.weeks,
    practiceWeeks: const [],
  );
}
