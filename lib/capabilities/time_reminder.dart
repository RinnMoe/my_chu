import 'package:flutter/foundation.dart';

enum TimeReminderCategory {
  course('课前提醒', 20, 5, 120, '分钟', 'feature.academic.schedule'),
  exam('考试提醒', 24, 1, 168, '小时', 'feature.academic.exams'),
  deadline('待办截止提醒', 24, 1, 168, '小时', 'feature.portal.personal');

  const TimeReminderCategory(
    this.label,
    this.defaultLead,
    this.minLead,
    this.maxLead,
    this.unit,
    this.targetAppId,
  );
  final String label;
  final int defaultLead;
  final int minLead;
  final int maxLead;
  final String unit;
  final String targetAppId;
  Duration lead(int value) =>
      this == course ? Duration(minutes: value) : Duration(hours: value);
}

@immutable
class TimeReminderSetting {
  const TimeReminderSetting({required this.enabled, required this.advance});
  final bool enabled;
  final int advance;
}

/// Business occurrence with an absolute UTC deadline/start, before lead policy.
@immutable
class TimeReminderEvent {
  const TimeReminderEvent({
    required this.id,
    required this.at,
    required this.title,
    this.body = '',
  });
  final String id;
  final DateTime at;
  final String title;
  final String body;
}

List<Map<String, Object>> buildTimeReminderPayloads(
  TimeReminderCategory category,
  TimeReminderSetting setting,
  List<TimeReminderEvent> events,
  DateTime now,
) {
  if (!setting.enabled) return const [];
  final horizon = now.toUtc().add(const Duration(days: 14));
  final unique = <String, Map<String, Object>>{};
  for (final event in events) {
    final at = event.at.toUtc();
    final trigger = at.subtract(category.lead(setting.advance));
    if (event.id.isEmpty ||
        event.title.trim().isEmpty ||
        !trigger.isAfter(now.toUtc()) ||
        trigger.isAfter(horizon)) {
      continue;
    }
    // Event identity excludes advance; changing settings cannot redeliver it.
    final identity = '${event.id}|${at.millisecondsSinceEpoch}';
    unique[identity] = {
      'eventId': identity,
      'category': category.name,
      'triggerAt': trigger.millisecondsSinceEpoch,
      'validUntil': at.millisecondsSinceEpoch,
      'title': event.title,
      'body': event.body,
      'targetAppId': category.targetAppId,
    };
  }
  final sorted =
      unique.values.toList()..sort(
        (a, b) => (a['triggerAt'] as int).compareTo(b['triggerAt'] as int),
      );
  return sorted.take(64).toList(growable: false);
}
