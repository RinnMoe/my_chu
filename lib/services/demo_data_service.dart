import 'package:flutter/foundation.dart';

import '../apps/academic_affairs/academic_affairs_models.dart';

/// 数据 Demo 的全局配置。
///
/// 只在当前进程内生效；关闭总开关或退出应用后，真实数据源恢复原状。
class DemoDataConfig {
  final bool holiday;
  final bool focusError;
  final int focusCount;
  final int quickAppCount;
  final int courseCount;
  final bool scheduleError;
  final bool gradeNotification;
  final bool balanceNotification;
  final bool liveUpdateNotification;
  final bool systemBanner;

  const DemoDataConfig({
    this.holiday = false,
    this.focusError = false,
    this.focusCount = 3,
    this.quickAppCount = 4,
    this.courseCount = 3,
    this.scheduleError = false,
    this.gradeNotification = true,
    this.balanceNotification = true,
    this.liveUpdateNotification = true,
    this.systemBanner = true,
  });

  DemoDataConfig copyWith({
    bool? holiday,
    bool? focusError,
    int? focusCount,
    int? quickAppCount,
    int? courseCount,
    bool? scheduleError,
    bool? gradeNotification,
    bool? balanceNotification,
    bool? liveUpdateNotification,
    bool? systemBanner,
  }) {
    return DemoDataConfig(
      holiday: holiday ?? this.holiday,
      focusError: focusError ?? this.focusError,
      focusCount: focusCount ?? this.focusCount,
      quickAppCount: quickAppCount ?? this.quickAppCount,
      courseCount: courseCount ?? this.courseCount,
      scheduleError: scheduleError ?? this.scheduleError,
      gradeNotification: gradeNotification ?? this.gradeNotification,
      balanceNotification: balanceNotification ?? this.balanceNotification,
      liveUpdateNotification:
          liveUpdateNotification ?? this.liveUpdateNotification,
      systemBanner: systemBanner ?? this.systemBanner,
    );
  }
}

/// 全局数据 Demo 状态。
///
/// 真实页面在 Demo 开启时优先使用这里的替换数据，关闭后继续走原数据链路。
/// 该状态仅存在于当前进程，不写入账号缓存或 SharedPreferences。
class DemoDataService {
  DemoDataService._();

  static final DemoDataService instance = DemoDataService._();

  /// 配置或总开关变化时 bump，页面与服务据此刷新。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _enabled = false;
  DemoDataConfig _config = const DemoDataConfig();

  bool get enabled => _enabled;

  DemoDataConfig get config => _config;

  DateTime get now => DateTime(2026, 8, 13, 9);

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    revision.value++;
  }

  void updateConfig(DemoDataConfig config) {
    _config = config;
    revision.value++;
  }

  void debugReset() {
    _enabled = false;
    _config = const DemoDataConfig();
    revision.value++;
  }

  List<AcademicPersonalScheduleEntry>? todayCourses() {
    if (!_enabled) return null;
    if (_config.holiday || _config.scheduleError) return const [];
    const names = [
      '高等数学',
      '大学英语',
      '程序设计基础',
      '体育',
      '形势与政策',
      '数据结构',
      '线性代数',
      '大学物理',
    ];
    return [
      for (var index = 0; index < _config.courseCount; index++)
        AcademicPersonalScheduleEntry(
          courseSequence: 'DEMO${index + 1}',
          courseCode: '',
          courseName: names[index % names.length],
          teacher: '示例教师',
          location: 'WM3101',
          weekday: now.weekday,
          startPeriod: index * 2 + 1,
          endPeriod: index * 2 + 2,
          weeksText: '5',
          weeks: const [5],
          practiceWeeks: const [],
        ),
    ];
  }
}
