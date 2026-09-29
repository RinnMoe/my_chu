import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_models.dart';

String normalizeAcademicSemesterLabel(String value) =>
    normalizeAcademicCalendarTermLabel(value);

/// Returns semester options in newest-first order for user-facing selectors.
///
/// Academic-affairs pages do not all return the same label shape, so ordering
/// uses the starting academic year and the explicit semester number when
/// available, with a label/id fallback for opaque values.
List<AcademicSemesterOption> academicSemestersNewestFirst(
  Iterable<AcademicSemesterOption> options,
) {
  final result = options.toList();
  result.sort(_compareAcademicSemestersNewestFirst);
  return result;
}

int _compareAcademicSemestersNewestFirst(
  AcademicSemesterOption left,
  AcademicSemesterOption right,
) {
  final leftYear = _academicSemesterYear(left.label);
  final rightYear = _academicSemesterYear(right.label);
  if (leftYear != null || rightYear != null) {
    if (leftYear == null) return 1;
    if (rightYear == null) return -1;
    final yearOrder = rightYear.compareTo(leftYear);
    if (yearOrder != 0) return yearOrder;
  }

  final leftTerm = _academicSemesterTerm(left.label);
  final rightTerm = _academicSemesterTerm(right.label);
  if (leftTerm != null || rightTerm != null) {
    if (leftTerm == null) return 1;
    if (rightTerm == null) return -1;
    final termOrder = rightTerm.compareTo(leftTerm);
    if (termOrder != 0) return termOrder;
  }

  final labelOrder = right.label.compareTo(left.label);
  if (labelOrder != 0) return labelOrder;
  return right.id.compareTo(left.id);
}

int? _academicSemesterYear(String label) {
  final match = RegExp(
    r'(?<!\d)(\d{4})(?:\s*[-－—–]\s*\d{4})?',
  ).firstMatch(label);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? _academicSemesterTerm(String label) {
  if (RegExp(r'秋(?:季)?学期').hasMatch(label)) return 1;
  if (RegExp(r'春(?:季)?学期').hasMatch(label)) return 2;

  final match = RegExp(
    r'(?:第\s*)?([0-9]+|一|二|三|四|五|六|七|八|九|十)\s*学期',
  ).firstMatch(label);
  if (match == null) return null;
  final value = match.group(1)!;
  return int.tryParse(value) ?? _chineseSemesterNumbers[value];
}

const _chineseSemesterNumbers = <String, int>{
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
  '十': 10,
};

String cleanScheduleLocation(String value) {
  return value
      .split(' / ')
      .map((part) => part.trim().replaceFirst(RegExp(r'^[*＊]+'), '').trim())
      .where((part) => part.isNotEmpty)
      .join(' / ');
}

bool academicSemesterLabelsMatch(String left, String right) {
  final leftKey = normalizeAcademicSemesterLabel(left);
  final rightKey = normalizeAcademicSemesterLabel(right);
  return leftKey.isNotEmpty && leftKey == rightKey;
}

AcademicSemesterOption? matchCurrentTeachingWeekSemester({
  required CurrentTeachingWeek teachingWeek,
  required Iterable<AcademicSemesterOption> options,
}) {
  for (final option in options) {
    if (academicSemesterLabelsMatch(teachingWeek.term, option.label)) {
      return option;
    }
  }
  return null;
}

/// Merges a schedule's selected semester into a catalog.
///
/// Empty ids are ignored, duplicate ids collapse to the last catalog entry,
/// and the schedule semester is appended when the catalog does not contain it.
/// The returned list keeps the caller's order; callers that display a selector
/// can continue to apply [academicSemestersNewestFirst].
List<AcademicSemesterOption> mergeScheduleSemesterSelection(
  Iterable<AcademicSemesterOption> semesters,
  AcademicPersonalSchedule schedule,
) {
  final selectedId = schedule.semesterId.trim();
  final byId = <String, AcademicSemesterOption>{};
  for (final semester in semesters) {
    final id = semester.id.trim();
    if (id.isEmpty) continue;
    byId[id] = AcademicSemesterOption(id: id, label: semester.label);
  }
  if (selectedId.isNotEmpty) {
    byId.putIfAbsent(
      selectedId,
      () =>
          AcademicSemesterOption(id: selectedId, label: schedule.semesterLabel),
    );
  }
  return [
    for (final semester in byId.values)
      AcademicSemesterOption(
        id: semester.id,
        label: semester.label,
        selected: semester.id == selectedId,
      ),
  ];
}

/// Whether a schedule belongs to the supplied academic term.
bool academicScheduleSemesterMatches(
  AcademicPersonalSchedule schedule,
  String term,
) {
  final label = schedule.semesterLabel.trim();
  return label.isEmpty ||
      label == '当前学期' ||
      label == '本学期' ||
      academicSemesterLabelsMatch(term, label);
}

/// Returns the schedule week represented by [teachingWeek], or null when the
/// schedule belongs to another term or the week is outside its bounds.
int? scheduleWeekForTeachingWeek(
  AcademicPersonalSchedule schedule,
  CurrentTeachingWeek teachingWeek,
) {
  if (!academicScheduleSemesterMatches(schedule, teachingWeek.term)) {
    return null;
  }
  if (teachingWeek.week < 1 || teachingWeek.week > schedule.maxWeek) {
    return null;
  }
  return teachingWeek.week;
}

/// Returns the schedule week containing [date], or null when the schedule
/// belongs to another term, has no term start date, or the date is outside the
/// schedule's week range.
int? scheduleWeekForDate(
  AcademicPersonalSchedule schedule,
  CurrentTeachingWeek teachingWeek,
  DateTime date,
) {
  if (!academicScheduleSemesterMatches(schedule, teachingWeek.term)) {
    return null;
  }
  final termStart = teachingWeek.termStartDate;
  if (termStart == null) return null;

  final calendarDate = DateTime(date.year, date.month, date.day);
  final termStartDate = DateTime(
    termStart.year,
    termStart.month,
    termStart.day,
  );
  final daysSinceTermStart = calendarDate.difference(termStartDate).inDays;
  if (daysSinceTermStart < 0) return null;

  final week = daysSinceTermStart ~/ 7 + 1;
  if (week < 1 || week > schedule.maxWeek) return null;
  return week;
}

List<AcademicPersonalScheduleEntry> filterScheduleEntriesForWeek(
  Iterable<AcademicPersonalScheduleEntry> entries,
  int? week,
) {
  if (week == null) return entries.toList(growable: false);
  return [
    for (final entry in entries)
      if (entry.isVisibleInWeek(week)) entry,
  ];
}

/// The entries of one rendered week, split by how the week grid shows them.
class AcademicScheduleWeekSplit {
  /// Entries that run in the rendered week; always shown in full color.
  final List<AcademicPersonalScheduleEntry> current;

  /// Entries from other weeks that share no cell with a current entry; shown
  /// dimmed when the "show non-current-week" preference is on.
  final List<AcademicPersonalScheduleEntry> faded;

  /// Entries from other weeks hidden behind a current entry in the same
  /// cell; surfaced only inside the tapped cell's detail sheet.
  final List<AcademicPersonalScheduleEntry> hidden;

  const AcademicScheduleWeekSplit({
    required this.current,
    required this.faded,
    required this.hidden,
  });
}

/// Splits [entries] for [week] into current, faded, and hidden groups.
///
/// A non-current entry is hidden when it shares a weekday and overlapping
/// periods with a current-week entry (the current course wins the cell);
/// otherwise it is faded so the week grid can show it dimmed.
AcademicScheduleWeekSplit classifyScheduleEntriesForWeek(
  Iterable<AcademicPersonalScheduleEntry> entries,
  int week,
) {
  final current = <AcademicPersonalScheduleEntry>[];
  final nonCurrent = <AcademicPersonalScheduleEntry>[];
  for (final entry in entries) {
    (entry.isVisibleInWeek(week) ? current : nonCurrent).add(entry);
  }
  final faded = <AcademicPersonalScheduleEntry>[];
  final hidden = <AcademicPersonalScheduleEntry>[];
  for (final entry in nonCurrent) {
    // Only show non-current entries that have future occurrences; entries
    // whose weeks are all before the displayed week have already ended.
    final hasFuture =
        entry.weeks.any((w) => w > week) ||
        entry.practiceWeeks.any((w) => w > week);
    if (!hasFuture) continue;
    final covered = current.any(
      (other) => scheduleEntriesShareCell(other, entry),
    );
    (covered ? hidden : faded).add(entry);
  }
  return AcademicScheduleWeekSplit(
    current: current.toList(growable: false),
    faded: faded.toList(growable: false),
    hidden: hidden.toList(growable: false),
  );
}

/// Whether two entries occupy the same grid cell: same weekday with
/// overlapping period ranges.
bool scheduleEntriesShareCell(
  AcademicPersonalScheduleEntry left,
  AcademicPersonalScheduleEntry right,
) {
  return left.weekday == right.weekday && _overlaps(left, right);
}

/// Whether [edited] conflicts with an existing entry in [schedule].
///
/// A conflict requires the same weekday, overlapping periods, and at least one
/// common visible week. [excluding] is the entry currently being edited, so it
/// does not conflict with itself.
bool academicScheduleEntryConflicts(
  AcademicPersonalSchedule schedule,
  AcademicPersonalScheduleEntry edited, {
  AcademicPersonalScheduleEntry? excluding,
}) {
  for (final other in schedule.entries) {
    if (identical(other, excluding) || other.weekday != edited.weekday) {
      continue;
    }
    if (other.endPeriod < edited.startPeriod ||
        edited.endPeriod < other.startPeriod) {
      continue;
    }
    for (var week = 1; week <= schedule.maxWeek; week++) {
      if (other.isVisibleInWeek(week) && edited.isVisibleInWeek(week)) {
        return true;
      }
    }
  }
  return false;
}

/// A full-width timetable cell containing every distinct merged course whose
/// period range belongs to the same connected overlap cluster on one weekday.
class AcademicScheduleCellGroup {
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final List<AcademicPersonalScheduleEntry> entries;

  AcademicScheduleCellGroup({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required Iterable<AcademicPersonalScheduleEntry> entries,
  }) : entries = List<AcademicPersonalScheduleEntry>.unmodifiable(entries);

  bool overlaps(AcademicPersonalScheduleEntry entry) {
    return weekday == entry.weekday &&
        startPeriod <= entry.endPeriod &&
        entry.startPeriod <= endPeriod;
  }
}

/// Groups timetable entries into full-width cells by weekday and connected
/// period overlap. Adjacent but non-overlapping entries remain separate.
List<AcademicScheduleCellGroup> groupScheduleEntriesByOverlap(
  Iterable<AcademicPersonalScheduleEntry> entries,
) {
  final byWeekday = <int, List<AcademicPersonalScheduleEntry>>{};
  for (final entry in entries) {
    byWeekday.putIfAbsent(entry.weekday, () => []).add(entry);
  }

  final weekdays = byWeekday.keys.toList()..sort();
  final groups = <AcademicScheduleCellGroup>[];
  for (final weekday in weekdays) {
    final dayEntries = byWeekday[weekday]!..sort(_compareScheduleEntries);
    var cluster = <AcademicPersonalScheduleEntry>[];
    var clusterStart = 0;
    var clusterEnd = -1;

    void flushCluster() {
      if (cluster.isEmpty) return;
      groups.add(
        AcademicScheduleCellGroup(
          weekday: weekday,
          startPeriod: clusterStart,
          endPeriod: clusterEnd,
          entries: cluster,
        ),
      );
      cluster = <AcademicPersonalScheduleEntry>[];
      clusterStart = 0;
      clusterEnd = -1;
    }

    for (final entry in dayEntries) {
      if (cluster.isNotEmpty && entry.startPeriod > clusterEnd) {
        flushCluster();
      }
      if (cluster.isEmpty) clusterStart = entry.startPeriod;
      cluster.add(entry);
      if (entry.endPeriod > clusterEnd) clusterEnd = entry.endPeriod;
    }
    flushCluster();
  }
  return groups;
}

/// Returns entries for one calendar day in [week], using the shared week
/// filter and timetable ordering.
List<AcademicPersonalScheduleEntry> filterScheduleEntriesForDay(
  Iterable<AcademicPersonalScheduleEntry> entries, {
  required int weekday,
  int? week,
}) {
  final weekEntries = filterScheduleEntriesForWeek(entries, week);
  return [
    for (final entry in weekEntries)
      if (entry.weekday == weekday) entry,
  ]..sort(_compareScheduleEntries);
}

int _compareScheduleEntries(
  AcademicPersonalScheduleEntry left,
  AcademicPersonalScheduleEntry right,
) {
  final periodCompare = left.startPeriod.compareTo(right.startPeriod);
  if (periodCompare != 0) return periodCompare;
  final endCompare = left.endPeriod.compareTo(right.endPeriod);
  if (endCompare != 0) return endCompare;
  final sequenceCompare = left.courseSequence.compareTo(right.courseSequence);
  if (sequenceCompare != 0) return sequenceCompare;
  return left.displayName.compareTo(right.displayName);
}

bool _overlaps(
  AcademicPersonalScheduleEntry left,
  AcademicPersonalScheduleEntry right,
) {
  return left.startPeriod <= right.endPeriod &&
      right.startPeriod <= left.endPeriod;
}

int stableCourseColorIndex(String courseSequence, {int colorCount = 8}) {
  if (colorCount <= 0) throw ArgumentError.value(colorCount, 'colorCount');
  var hash = 0;
  for (final codeUnit in courseSequence.trim().codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash % colorCount;
}

/// Result of merging schedule entries that share a cell.
class MergedScheduleEntries {
  final List<AcademicPersonalScheduleEntry> entries;
  final Map<AcademicPersonalScheduleEntry, List<AcademicPersonalScheduleEntry>>
  sources;

  const MergedScheduleEntries({required this.entries, required this.sources});
}

/// Merges entries with the same course code (or name), weekday, and period
/// range into a single entry. The merged entry's weeks are the union of all
/// source entries' weeks, so it appears in every week covered by any source.
MergedScheduleEntries mergeScheduleEntries(
  Iterable<AcademicPersonalScheduleEntry> entries,
) => _mergeScheduleEntries(entries, keyOf: _mergeKey);

/// Merges class-schedule records that represent the same course in the same
/// weekday and period range. Class timetable responses can emit one record per
/// teacher, and those records may carry different lesson/course identifiers;
/// the display should keep one readable block while retaining every source in
/// [MergedScheduleEntries.sources].
MergedScheduleEntries mergeClassScheduleEntries(
  Iterable<AcademicPersonalScheduleEntry> entries,
) => _mergeScheduleEntries(entries, keyOf: _classMergeKey);

MergedScheduleEntries _mergeScheduleEntries(
  Iterable<AcademicPersonalScheduleEntry> entries, {
  required String Function(AcademicPersonalScheduleEntry entry) keyOf,
}) {
  final groups = <String, List<AcademicPersonalScheduleEntry>>{};
  for (final entry in entries) {
    final key = keyOf(entry);
    groups.putIfAbsent(key, () => []).add(entry);
  }

  final merged = <AcademicPersonalScheduleEntry>[];
  final sources =
      <AcademicPersonalScheduleEntry, List<AcademicPersonalScheduleEntry>>{};

  for (final group in groups.values) {
    if (group.length == 1) {
      merged.add(group.first);
      continue;
    }

    final sorted = List<AcademicPersonalScheduleEntry>.from(group)
      ..sort(_compareByFirstWeek);

    final allWeeks = <int>{};
    final allPracticeWeeks = <int>{};
    final allLocations = <String>{};
    final allWeeksText = <String>{};

    for (final entry in sorted) {
      allWeeks.addAll(entry.weeks);
      allPracticeWeeks.addAll(entry.practiceWeeks);
      if (entry.location.trim().isNotEmpty) {
        allLocations.add(entry.location.trim());
      }
      if (entry.weeksText.trim().isNotEmpty) {
        allWeeksText.add(entry.weeksText.trim());
      }
    }

    final primary = sorted.first;
    final mergedEntry = AcademicPersonalScheduleEntry(
      courseSequence: primary.courseSequence,
      courseCode: primary.courseCode,
      courseName: primary.courseName,
      teacher: primary.teacher,
      location: allLocations.join(' / '),
      weekday: primary.weekday,
      startPeriod: primary.startPeriod,
      endPeriod: primary.endPeriod,
      weeksText: allWeeksText.join('、'),
      weeks: allWeeks.toList()..sort(),
      practiceWeeks: allPracticeWeeks.toList()..sort(),
    );

    merged.add(mergedEntry);
    sources[mergedEntry] = sorted;
  }

  return MergedScheduleEntries(entries: merged, sources: sources);
}

int _compareByFirstWeek(
  AcademicPersonalScheduleEntry left,
  AcademicPersonalScheduleEntry right,
) {
  final l =
      left.weeks.isNotEmpty
          ? left.weeks.first
          : (left.practiceWeeks.isNotEmpty ? left.practiceWeeks.first : 0);
  final r =
      right.weeks.isNotEmpty
          ? right.weeks.first
          : (right.practiceWeeks.isNotEmpty ? right.practiceWeeks.first : 0);
  return l.compareTo(r);
}

String _mergeKey(AcademicPersonalScheduleEntry entry) {
  final courseKey =
      entry.courseCode.trim().isNotEmpty
          ? entry.courseCode.trim()
          : entry.courseName.trim();
  return '$courseKey|${entry.weekday}|${entry.startPeriod}|${entry.endPeriod}';
}

String _classMergeKey(AcademicPersonalScheduleEntry entry) {
  final courseKey = _classCourseKey(entry);
  return '$courseKey|${entry.weekday}|${entry.startPeriod}|${entry.endPeriod}';
}

String _classCourseKey(AcademicPersonalScheduleEntry entry) {
  // An empty imported name must fall back to the visible course code before
  // the source sequence; displayName would already fall back to sequence and
  // could prevent class-schedule rows sharing one code from merging.
  final cleanedName = entry.courseName.trim();
  final value =
      cleanedName.isNotEmpty
          ? cleanedName
          : entry.courseCode.trim().isNotEmpty
          ? entry.courseCode.trim()
          : entry.courseSequence.trim();
  return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
