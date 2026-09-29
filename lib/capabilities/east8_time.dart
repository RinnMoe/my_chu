const Duration east8Offset = Duration(hours: 8);

/// 应用内展示时间统一使用东八区墙钟。
///
/// 返回值按墙钟字段读取，不依赖设备时区；不要依赖 [DateTime.toUtc] 或
/// [DateTime.isUtc] 解释这些值的绝对时刻。
DateTime east8Now() {
  final shifted = DateTime.now().toUtc().add(east8Offset);
  return _wallClock(shifted);
}

/// Converts a DateTime whose fields represent an East-8 wall-clock value to
/// the corresponding absolute UTC instant.
///
/// [wallClock] is intentionally read by fields rather than by its existing
/// timezone metadata because values returned by [east8Now] and [parseEast8]
/// are display wall clocks, not instants.
DateTime east8WallClockToUtcInstant(DateTime wallClock) {
  return DateTime.utc(
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour,
    wallClock.minute,
    wallClock.second,
    wallClock.millisecond,
    wallClock.microsecond,
  ).subtract(east8Offset);
}

/// 解析服务端/本地时间字符串为东八区墙钟。
///
/// 无时区字符串按原字段保留；带 `Z` 或显式偏移的字符串映射为东八区墙钟。
DateTime? parseEast8(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (text.endsWith('Z') ||
      text.endsWith('z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text)) {
    return _wallClock(parsed.toUtc().add(east8Offset));
  }
  return _wallClock(parsed);
}

DateTime _wallClock(DateTime value) {
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}
