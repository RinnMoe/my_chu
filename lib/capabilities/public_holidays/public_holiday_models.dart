// Typed public-holiday data shared by built-in Dart applications.
//
// This data is deliberately separate from the academic calendar model. A
// public holiday is only a date annotation; it never decides whether the
// university is teaching on that date.

import 'package:flutter/foundation.dart';

enum PublicHolidayYearStatus { available, empty, unavailable }

enum PublicHolidaySourceType { remote, cached, bundled, unavailable }

enum PublicHolidayDataOrigin { remote, cached, bundled, mixed, unavailable }

class PublicHolidayDay {
  final DateTime date;
  final String name;
  final bool isOffDay;
  final int sourceYear;

  PublicHolidayDay({
    required DateTime date,
    required this.name,
    required this.isOffDay,
    required this.sourceYear,
  }) : date = DateTime(date.year, date.month, date.day);

  /// User-facing label for the upstream `isOffDay` flag.
  ///
  /// `false` means that the holiday arrangement makes this a workday. The
  /// product uses “调休” as the concise user-facing label for this record.
  String get label => isOffDay ? '假期' : '调休';

  @override
  bool operator ==(Object other) {
    return other is PublicHolidayDay &&
        _sameDate(date, other.date) &&
        name == other.name &&
        isOffDay == other.isOffDay &&
        sourceYear == other.sourceYear;
  }

  @override
  int get hashCode =>
      Object.hash(date.year, date.month, date.day, name, isOffDay, sourceYear);
}

class PublicHolidayYear {
  final int sourceYear;
  final String sourceFile;
  final String? sourceUrl;
  final List<String> papers;
  final List<PublicHolidayDay> days;
  final PublicHolidayYearStatus status;
  final PublicHolidaySourceType sourceType;
  final DateTime? fetchedAt;

  PublicHolidayYear({
    required this.sourceYear,
    required List<String> papers,
    required List<PublicHolidayDay> days,
    required this.status,
    required this.sourceType,
    this.sourceUrl,
    this.fetchedAt,
    String? sourceFile,
  }) : sourceFile = sourceFile ?? '$sourceYear.json',
       papers = List.unmodifiable(papers),
       days = List.unmodifiable(days);

  bool get isAvailable => status != PublicHolidayYearStatus.unavailable;
}

class PublicHolidaySnapshot {
  final DateTime startDate;
  final DateTime endDate;
  final List<PublicHolidayDay> days;
  final List<PublicHolidayYear> years;
  final PublicHolidayDataOrigin origin;
  final DateTime? latestFetchedAt;

  PublicHolidaySnapshot({
    required DateTime startDate,
    required DateTime endDate,
    required List<PublicHolidayDay> days,
    required List<PublicHolidayYear> years,
    required this.origin,
    this.latestFetchedAt,
  }) : startDate = DateTime(startDate.year, startDate.month, startDate.day),
       endDate = DateTime(endDate.year, endDate.month, endDate.day),
       days = List.unmodifiable(days),
       years = List.unmodifiable(years);

  bool get hasData => days.isNotEmpty;

  bool get hasUnavailableYears =>
      years.any((year) => year.status == PublicHolidayYearStatus.unavailable);

  List<PublicHolidayDay> daysFor(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return [
      for (final day in days)
        if (_sameDate(day.date, dateOnly)) day,
    ];
  }
}

abstract interface class PublicHolidayProvider {
  Future<PublicHolidaySnapshot> loadRange(
    DateTime startDate,
    DateTime endDate, {
    bool force = false,
  });
}

/// Optional signal emitted when a provider's background refresh changes data.
///
/// Providers that only implement [PublicHolidayProvider] remain valid. Host
/// pages use this interface when available to re-project stale-while-
/// revalidate data without coupling themselves to the repository.
abstract interface class PublicHolidayRevisionSource {
  ValueListenable<int> get revision;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
