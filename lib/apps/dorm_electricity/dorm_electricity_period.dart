enum ElectricityScale { week, month, year }

/// Calendar dates use UTC fields for stable day arithmetic, never instants.
class ElectricityPeriod {
  ElectricityPeriod(this.scale, DateTime anchor)
    : anchor = DateTime.utc(anchor.year, anchor.month, anchor.day);
  final ElectricityScale scale;
  final DateTime anchor;

  DateTime get start => switch (scale) {
    ElectricityScale.week => anchor.subtract(
      Duration(days: anchor.weekday - 1),
    ),
    ElectricityScale.month => DateTime.utc(anchor.year, anchor.month),
    ElectricityScale.year => DateTime.utc(anchor.year),
  };
  DateTime get end => switch (scale) {
    ElectricityScale.week => start.add(const Duration(days: 7)),
    ElectricityScale.month => DateTime.utc(anchor.year, anchor.month + 1),
    ElectricityScale.year => DateTime.utc(anchor.year + 1),
  };
  String get key => '${scale.name}:${start.toIso8601String()}';
  static String monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
  String get label {
    if (scale == ElectricityScale.year) return '${start.year}年';
    if (scale == ElectricityScale.month) return '${start.year}年${start.month}月';
    final last = end.subtract(const Duration(days: 1));
    final suffix =
        last.year != start.year
            ? '${last.year}年${last.month}月${last.day}日'
            : last.month != start.month
            ? '${last.month}月${last.day}日'
            : '${last.day}日';
    return '${start.year}年${start.month}月${start.day}日—$suffix';
  }

  List<DateTime> get dates =>
      scale == ElectricityScale.year
          ? [
            for (var month = 1; month <= 12; month++)
              DateTime.utc(start.year, month),
          ]
          : [
            for (
              var date = start;
              date.isBefore(end);
              date = date.add(const Duration(days: 1))
            )
              date,
          ];
  List<String> monthsThrough(DateTime today) {
    final last = DateTime.utc(today.year, today.month);
    return [
      for (
        var date = DateTime.utc(start.year, start.month);
        date.isBefore(end) && !date.isAfter(last);
        date = DateTime.utc(date.year, date.month + 1)
      )
        monthKey(date),
    ];
  }

  ElectricityPeriod shifted(int delta) =>
      ElectricityPeriod(scale, switch (scale) {
        ElectricityScale.week => start.add(Duration(days: 7 * delta)),
        ElectricityScale.month => DateTime.utc(start.year, start.month + delta),
        ElectricityScale.year => DateTime.utc(start.year + delta),
      });
}
