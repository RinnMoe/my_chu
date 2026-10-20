import '../capabilities/academic_schedule/recent_schedule.dart';
import '../capabilities/east8_time.dart';

/// Host/Android contract for the course live activity.
///
/// The shared layer owns course projection, the settings gate and the account
/// boundary. The native layer owns persistence, exact scheduling and the
/// platform rendering of one selected course. Nothing here fetches campus
/// data, and the native plan carries no account, credential or full timetable.
const String courseLiveActivityChannel = 'mychu/course_live_activity';

/// Bumped whenever a native build must reject an older shared plan.
const int courseLiveActivityPlanVersion = 1;

/// Versioned global preference record. It holds the switch plus the random
/// ownership token for the currently bound account.
const String courseLiveActivitySettingsKey =
    'preferences.course_live_activity.v1';

/// Existing stable root destination for a course tap.
const String courseLiveActivityTargetAppId = 'feature.academic.schedule';

/// Pre-class lead; the same activity continues until the course ends.
const Duration courseLiveActivityLead = Duration(minutes: 30);

enum CourseLivePhase {
  /// Before the pre-class window opens.
  idle,

  /// Inside `[start - lead, start)`.
  before,

  /// Inside [start, end), with a measurable lesson progress.
  ongoing,

  /// At or after the course end.
  ended,
}

/// One grouped course block spanning pre-class and ongoing stages.
class CourseLivePlanCourse {
  const CourseLivePlanCourse({
    required this.eventId,
    required this.name,
    required this.location,
    required this.businessDate,
    required this.startAt,
    required this.endAt,
    required this.windowStart,
    required this.windowEnd,
  });

  final String eventId;
  final String name;
  final String location;

  /// Business date (`yyyy-MM-dd`) in the fixed UTC+8 calendar.
  final String businessDate;
  final DateTime startAt;
  final DateTime endAt;

  /// Full display window for this course.
  final DateTime windowStart;
  final DateTime windowEnd;

  CourseLivePhase phaseAt(DateTime now) {
    final instant = now.toUtc();
    if (instant.isBefore(windowStart.toUtc())) return CourseLivePhase.idle;
    if (instant.isBefore(startAt.toUtc())) return CourseLivePhase.before;
    if (instant.isBefore(endAt.toUtc())) return CourseLivePhase.ongoing;
    return CourseLivePhase.ended;
  }

  Map<String, Object?> toPayload() => {
    'eventId': eventId,
    'name': name,
    'location': location,
    'businessDate': businessDate,
    'startAt': startAt.toUtc().millisecondsSinceEpoch,
    'endAt': endAt.toUtc().millisecondsSinceEpoch,
    'windowStart': windowStart.toUtc().millisecondsSinceEpoch,
    'windowEnd': windowEnd.toUtc().millisecondsSinceEpoch,
  };
}

/// What the native layer stores. The native layer never receives the account,
/// the credentials or the full timetable.
class CourseLiveActivityPlan {
  const CourseLiveActivityPlan({
    required this.owner,
    required this.generation,
    required this.generatedAt,
    required this.windowStart,
    required this.windowEnd,
    required this.courses,
  });

  final String owner;
  final int generation;
  final DateTime generatedAt;
  final DateTime windowStart;
  final DateTime windowEnd;
  final List<CourseLivePlanCourse> courses;

  Map<String, Object?> toPayload() => {
    'version': courseLiveActivityPlanVersion,
    'owner': owner,
    'generation': generation,
    'generatedAt': generatedAt.toUtc().millisecondsSinceEpoch,
    'windowStart': windowStart.toUtc().millisecondsSinceEpoch,
    'windowEnd': windowEnd.toUtc().millisecondsSinceEpoch,
    'leadMinutes': courseLiveActivityLead.inMinutes,
    'targetAppId': courseLiveActivityTargetAppId,
    'courses': [for (final course in courses) course.toPayload()],
  };

  /// Parses a payload previously handed to the native layer. Used when this
  /// process restarted and the only surviving plan is the persisted one, so a
  /// partial projection can still merge against it.
  static CourseLiveActivityPlan? fromPayload(Object? raw) {
    if (raw is! Map) return null;
    if (raw['version'] != courseLiveActivityPlanVersion) return null;
    final owner = raw['owner'];
    if (owner is! String || !RegExp(r'^[a-f0-9]{48}$').hasMatch(owner)) {
      return null;
    }
    final generation = raw['generation'];
    final windowStart = raw['windowStart'];
    final windowEnd = raw['windowEnd'];
    if (generation is! int ||
        generation < 0 ||
        windowStart is! int ||
        windowEnd is! int) {
      return null;
    }
    final rawCourses = raw['courses'];
    if (rawCourses is! List) return null;
    final courses = <CourseLivePlanCourse>[];
    for (final entry in rawCourses) {
      if (entry is! Map) return null;
      final eventId = entry['eventId'];
      final name = entry['name'];
      final location = entry['location'];
      final businessDate = entry['businessDate'];
      final startAt = entry['startAt'];
      final endAt = entry['endAt'];
      if (eventId is! String ||
          eventId.isEmpty ||
          name is! String ||
          name.trim().isEmpty ||
          location is! String ||
          businessDate is! String ||
          startAt is! int ||
          endAt is! int ||
          endAt <= startAt) {
        return null;
      }
      final start = DateTime.fromMillisecondsSinceEpoch(startAt, isUtc: true);
      final end = DateTime.fromMillisecondsSinceEpoch(endAt, isUtc: true);
      courses.add(
        CourseLivePlanCourse(
          eventId: eventId,
          name: name.trim(),
          location: location.trim(),
          businessDate: businessDate,
          startAt: start,
          endAt: end,
          windowStart: start.subtract(courseLiveActivityLead),
          windowEnd: end,
        ),
      );
    }
    return CourseLiveActivityPlan(
      owner: owner,
      generation: generation,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        raw['generatedAt'] is int ? raw['generatedAt'] as int : 0,
        isUtc: true,
      ),
      windowStart: DateTime.fromMillisecondsSinceEpoch(
        windowStart,
        isUtc: true,
      ),
      // Normalize either v1 window shape using course end times, preserving
      // ownership and still-running courses.
      windowEnd:
          courses.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(windowEnd, isUtc: true)
              : courses
                  .map((course) => course.endAt)
                  .reduce((left, right) => left.isAfter(right) ? left : right),
      courses: List.unmodifiable(courses),
    );
  }
}

/// Accounts for a pick that found nothing worth surfacing.
class CourseLivePlanOutcome {
  const CourseLivePlanOutcome(this.plan, {this.authoritative = true});

  /// `null` means "an available projection produced no displayable course".
  final CourseLiveActivityPlan? plan;

  /// `false` means at least one requested business date was unavailable, so an
  /// unexpired native plan must be kept instead of being replaced by a partial
  /// result.
  final bool authoritative;

}

/// Result of asking the device what it can actually do. Reported separately
/// from "the interface call returned successfully".
class CourseLiveActivityStatus {
  const CourseLiveActivityStatus({
    this.notifications = false,
    this.exact = false,
    this.promoted = false,
  });

  /// Notification permission granted and the channel not disabled.
  final bool notifications;

  /// Exact-alarm special access granted.
  final bool exact;

  /// The system accepted a promoted live-update style for this notification.
  final bool promoted;

}

/// Fixed UTC+8 business date helpers.
DateTime courseLiveActivityBusinessDate(DateTime instant) {
  final east8 = instant.toUtc().add(east8Offset);
  return DateTime.utc(east8.year, east8.month, east8.day);
}

List<DateTime> courseLiveActivityBusinessDates(DateTime now, {int days = 7}) {
  final today = courseLiveActivityBusinessDate(now);
  return [
    for (var offset = 0; offset < days; offset++)
      today.add(Duration(days: offset)),
  ];
}

/// Stable occurrence identity: source course id, business date and start
/// instant. Deliberately independent of the course name, the room and any
/// user-visible text.
String courseLiveActivityEventId({
  required String courseId,
  required DateTime start,
}) =>
    '$courseId|${recentScheduleDate(start)}|${east8WallClockToUtcInstant(start).millisecondsSinceEpoch}';

/// Exact transitions: pre-class opening, course start, and course end.
DateTime? courseLiveActivityNextBoundary(
  CourseLivePlanCourse course,
  DateTime now,
) => switch (course.phaseAt(now)) {
  CourseLivePhase.idle => course.windowStart.toUtc(),
  CourseLivePhase.before => course.startAt.toUtc(),
  CourseLivePhase.ongoing => course.endAt.toUtc(),
  CourseLivePhase.ended => null,
};

/// Foreground progress updates use a five-minute grid, without network access.
DateTime? courseLiveActivityNextUpdate(CourseLivePlanCourse course, DateTime now) {
  final boundary = courseLiveActivityNextBoundary(course, now);
  if (course.phaseAt(now) != CourseLivePhase.ongoing) return boundary;
  const grid = 5 * 60 * 1000;
  final next = DateTime.fromMillisecondsSinceEpoch(
    (now.toUtc().millisecondsSinceEpoch ~/ grid + 1) * grid, isUtc: true);
  return boundary != null && boundary.isBefore(next) ? boundary : next;
}

/// Builds the native plan from an already resolved schedule window.
///
/// [days] must be the ordered business-date projection. A day whose source is
/// unavailable makes the outcome advisory instead of authoritative so the
/// native layer keeps its unexpired plan for the uncovered dates.
CourseLivePlanOutcome projectCourseLiveActivityPlan({
  required String owner,
  required int generation,
  required DateTime now,
  required List<RecentScheduleDay> days,
  required List<DateTime> dates,
  int maxCourses = 64,
}) {
  assert(days.length == dates.length);
  final authoritative = days.every((day) => day.available);
  final courses = <(CourseLivePlanCourse, DateTime)>[];
  for (var index = 0; index < days.length; index++) {
    final day = days[index];
    if (!day.available) continue;
    final date = dates[index];
    final businessDate = recentScheduleDate(date);
    // Adjacent lessons grouped for display share one activity block. The
    // block keeps the first lesson identity and spans the merged interval.
    for (final block in groupRecentCourseRows(day.courses)) {
      final name = block.name.trim();
      if (name.isEmpty || block.id.trim().isEmpty) continue;
      final start = east8WallClockToUtcInstant(block.start);
      final end = east8WallClockToUtcInstant(block.end);
      if (!end.isAfter(start)) continue;
      courses.add((
        CourseLivePlanCourse(
          eventId: courseLiveActivityEventId(
            courseId: block.id,
            start: block.start,
          ),
          name: name,
          location: block.location.trim(),
          businessDate: businessDate,
          startAt: start,
          endAt: end,
          windowStart: start.subtract(courseLiveActivityLead),
          windowEnd: end,
        ),
        date,
      ));
    }
  }
  courses.sort((left, right) {
    final byDate = left.$2.compareTo(right.$2);
    if (byDate != 0) return byDate;
    final byStart = left.$1.startAt.compareTo(right.$1.startAt);
    if (byStart != 0) return byStart;
    return left.$1.eventId.compareTo(right.$1.eventId);
  });
  final planned = <CourseLivePlanCourse>[];
  final seen = <String>{};
  for (final (course, _) in courses) {
    if (!seen.add(course.eventId)) continue;
    planned.add(course);
    if (planned.length >= maxCourses) break;
  }
  if (planned.isEmpty) {
    return CourseLivePlanOutcome(null, authoritative: authoritative);
  }
  return CourseLivePlanOutcome(
    CourseLiveActivityPlan(
      owner: owner,
      generation: generation,
      generatedAt: now.toUtc(),
      windowStart: planned.first.windowStart,
      windowEnd: planned
          .map((course) => course.windowEnd)
          .reduce((left, right) => left.isAfter(right) ? left : right),
      courses: List.unmodifiable(planned),
    ),
    authoritative: authoritative,
  );
}

/// Merges a projection that only confirmed some business dates with the courses
/// the device already holds for the dates that stayed unavailable.
///
/// A day whose source is unavailable carries no information about that day, so
/// replacing the whole plan would delete courses that are still valid and could
/// even revoke an activity that is on screen right now.
CourseLiveActivityPlan mergeCourseLiveActivityPlan({
  required CourseLiveActivityPlan? previous,
  required List<CourseLivePlanCourse> confirmed,
  required Set<String> confirmedDates,
  required DateTime now,
  required String owner,
  required int generation,
  int maxCourses = 64,
}) {
  final merged = <String, CourseLivePlanCourse>{};
  for (final course in confirmed) {
    merged[course.eventId] = course;
  }
  for (final course in previous?.courses ?? const <CourseLivePlanCourse>[]) {
    if (course.eventId.isEmpty || merged.containsKey(course.eventId)) continue;
    // Only a date that this projection did not confirm may be preserved.
    if (confirmedDates.contains(course.businessDate)) continue;
    // Nothing that has already ended is worth keeping.
    if (!course.endAt.isAfter(now)) continue;
    merged[course.eventId] = course;
  }
  final courses =
      merged.values.toList()..sort((left, right) {
        final byStart = left.startAt.compareTo(right.startAt);
        if (byStart != 0) return byStart;
        return left.eventId.compareTo(right.eventId);
      });
  if (courses.isEmpty) {
    // Nothing survived. The caller publishes this as an explicit clear, so the
    // window is empty rather than reduced from a missing element.
    return CourseLiveActivityPlan(
      owner: owner,
      generation: generation,
      generatedAt: now,
      windowStart: now,
      windowEnd: now,
      courses: const [],
    );
  }
  return CourseLiveActivityPlan(
    owner: owner,
    generation: generation,
    generatedAt: now,
    windowStart: courses
        .map((course) => course.windowStart)
        .reduce((left, right) => left.isBefore(right) ? left : right),
    windowEnd: courses
        .map((course) => course.windowEnd)
        .reduce((left, right) => left.isAfter(right) ? left : right),
    courses: courses.take(maxCourses).toList(growable: false),
  );
}
