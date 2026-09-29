import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import '../live_update.dart';
import '../../services/campus_settings_service.dart';
import '../../services/teaching_schedule_service.dart';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../apps/academic_calendar/academic_calendar_service.dart';
import 'academic_schedule_store.dart';
import 'academic_schedule_utils.dart';

const academicScheduleLiveUpdateDefinition = SystemLiveActivityDefinition(
  id: 'feature.academic.schedule.live_update',
  title: '课程实时动态',
  targetAppId: 'feature.academic.schedule',
  load: _loadAcademicScheduleLiveUpdate,
);

const _leadTime = Duration(minutes: 30);

Future<LiveUpdateContent> _loadAcademicScheduleLiveUpdate(
  LiveUpdateLoadContext context,
) async {
  try {
    final scheduleMode = await campusSettingsService.scheduleModeFor(
      context.accountKey,
    );
    final schedule = await AcademicScheduleStore().readCachedCurrentSchedule(
      context.accountKey,
    );
    if (schedule == null) {
      return LiveUpdateContent.error(message: '打开我的课表更新课程', now: context.now);
    }

    final state = await AcademicCalendarService().fetchCurrentCalendarState(
      force: context.forceRefresh,
    );
    final teachingWeek = state.teachingWeek;
    if (teachingWeek == null) {
      return LiveUpdateContent.inactive(now: context.now);
    }
    final week = scheduleWeekForTeachingWeek(schedule, teachingWeek);
    if (week == null) {
      return LiveUpdateContent.inactive(now: context.now);
    }

    final today = DateTime(
      context.now.year,
      context.now.month,
      context.now.day,
    );
    final teaching = teachingScheduleFor(scheduleMode);
    final blocks = _blocksFor(
      filterScheduleEntriesForDay(
        schedule.entries,
        weekday: today.weekday,
        week: week,
      ),
      today,
      teaching,
    );

    if (blocks.isEmpty) {
      return LiveUpdateContent.inactive(now: context.now);
    }
    return _buildContent(blocks, context.now);
  } catch (_) {
    return LiveUpdateContent.error(now: context.now);
  }
}

List<_CourseBlock> _blocksFor(
  Iterable<AcademicPersonalScheduleEntry> entries,
  DateTime date,
  TeachingSchedule teaching,
) {
  final result = <_CourseBlock>[];
  for (final entry in entries) {
    final time = teaching.range(entry.startPeriod, entry.endPeriod);
    if (time == null) continue;
    result.add(
      _CourseBlock(
        id:
            '${entry.courseSequence}:${date.toIso8601String()}:'
            '${entry.startPeriod}',
        name: entry.displayName.trim(),
        location: entry.location.trim(),
        startAt: time.startAt(date),
        endAt: time.endAt(date),
      ),
    );
  }
  result.sort((left, right) => left.startAt.compareTo(right.startAt));
  return result;
}

LiveUpdateContent _buildContent(List<_CourseBlock> blocks, DateTime now) {
  final boundaries = <LiveUpdateBoundaryRender>[];
  for (final block in blocks) {
    final leadAt = block.startAt.subtract(_leadTime);
    if (leadAt.isAfter(now)) {
      boundaries.add(
        LiveUpdateBoundaryRender(at: leadAt, render: _before(block)),
      );
    }
    if (block.startAt.isAfter(now)) {
      boundaries.add(
        LiveUpdateBoundaryRender(at: block.startAt, render: _active(block)),
      );
    }
    if (block.endAt.isAfter(now)) {
      boundaries.add(
        LiveUpdateBoundaryRender(
          at: block.endAt,
          render: _placeholder('课程已结束'),
          cancel: true,
        ),
      );
    }
  }
  boundaries.sort((left, right) => left.at.compareTo(right.at));

  _CourseBlock? current;
  _CourseBlock? upcoming;
  for (final block in blocks) {
    if (!now.isBefore(block.startAt) && now.isBefore(block.endAt)) {
      current = block;
      break;
    }
    if (block.startAt.isAfter(now)) {
      upcoming = block;
      break;
    }
  }
  if (current != null) {
    return LiveUpdateContent.active(
      render: _active(current, now: now),
      boundaries: boundaries,
      validUntil: current.endAt,
      now: now,
    );
  }
  if (upcoming == null) return LiveUpdateContent.inactive(now: now);

  final inLeadTime = upcoming.startAt.difference(now) <= _leadTime;
  return LiveUpdateContent.active(
    render: inLeadTime ? _before(upcoming) : _placeholder('还没有即将开始的课程'),
    boundaries: boundaries,
    postImmediately: inLeadTime,
    cancelExisting: !inLeadTime,
    validUntil: upcoming.startAt,
    now: now,
  );
}

LiveUpdateRender _before(_CourseBlock block) {
  final body = [
    if (block.location.isNotEmpty) block.location,
    '${_timeText(block.startAt)}-${_timeText(block.endAt)}',
  ].join(' · ');
  return LiveUpdateRender(
    title: block.name,
    body: body,
    // Keep the room visible within the Status Chip's seven-character budget;
    // the expanded notification carries the course and complete time.
    shortCriticalText: truncateLiveUpdateChipText(block.location),
    trackerEmoji: '🎓',
    progress: 0,
    progressMax: 1,
    requestPromoted: true,
    ongoing: true,
    phase: LiveUpdatePhase.upcoming,
    startAt: block.startAt,
    endAt: block.endAt,
    // The system surface remains valid through the whole course window;
    // ActivityKit may otherwise mark the upcoming card stale at the start
    // boundary before the active-state reconciliation runs.
    validUntil: block.endAt,
  );
}

LiveUpdateRender _active(_CourseBlock block, {DateTime? now}) {
  final body = [
    if (block.location.isNotEmpty) block.location,
    '下课 ${_timeText(block.endAt)}',
  ].join(' · ');
  final duration = block.endAt.difference(block.startAt).inSeconds;
  return LiveUpdateRender(
    title: block.name,
    body: body,
    shortCriticalText: truncateLiveUpdateChipText(block.location),
    trackerEmoji: '🎓',
    countdownAt: block.endAt,
    progress: _activeProgress(block, now ?? block.startAt),
    progressMax: duration > 0 ? duration : 1,
    requestPromoted: true,
    ongoing: true,
    phase: LiveUpdatePhase.active,
    startAt: block.startAt,
    endAt: block.endAt,
    validUntil: block.endAt,
  );
}

int _activeProgress(_CourseBlock block, DateTime now) {
  final duration = block.endAt.difference(block.startAt).inSeconds;
  if (duration <= 0) return 0;
  final elapsed = now.difference(block.startAt).inSeconds;
  return elapsed.clamp(0, duration).toInt();
}

LiveUpdateRender _placeholder(String message) {
  return LiveUpdateRender(
    title: '课程实时动态',
    body: message,
    progress: 0,
    progressMax: 0,
    requestPromoted: false,
    ongoing: false,
    phase: LiveUpdatePhase.ended,
  );
}

String _timeText(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}

class _CourseBlock {
  final String id;
  final String name;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  const _CourseBlock({
    required this.id,
    required this.name,
    required this.location,
    required this.startAt,
    required this.endAt,
  });
}

/// Test-only preview input used to verify the course feature's Live Update
/// state machine without loading real schedule caches or network data.
@immutable
class CourseLiveUpdatePreviewCourse {
  final String name;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  const CourseLiveUpdatePreviewCourse({
    required this.name,
    required this.location,
    required this.startAt,
    required this.endAt,
  });
}

@visibleForTesting
LiveUpdateContent buildCourseLiveUpdatePreview({
  required List<CourseLiveUpdatePreviewCourse> courses,
  required DateTime now,
}) {
  final blocks = [
    for (final course in courses)
      _CourseBlock(
        id: 'preview:${course.name}:${course.startAt}',
        name: course.name,
        location: course.location,
        startAt: course.startAt,
        endAt: course.endAt,
      ),
  ];
  return _buildContent(blocks, now);
}
