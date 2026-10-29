import 'package:flutter/foundation.dart';

/// 应用公告的统一领域模型。
///
/// Fenfa 与 Supabase 两种数据源都收敛到该模型，首页 Focus 聚合与公告展示只
/// 依赖它，不感知后端字段名或传输格式。
@immutable
class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    this.priority = 0,
    this.publishedAt,
    this.platforms = const <String>{},
    this.minAppVersionCode,
    this.maxAppVersionCode,
  });

  /// 跨版本稳定的公告 ID；用于 Focus 去重与展示状态。
  final String id;
  final String title;
  final String content;

  /// 越大越靠前；Fenfa 数据源没有该字段时统一为 0。
  final int priority;
  final DateTime? publishedAt;

  /// 目标平台集合（`HostPlatform.name`）；空集合表示不限制平台。
  final Set<String> platforms;

  /// 适用的宿主构建号区间；`null` 表示该端不设限制。
  final int? minAppVersionCode;
  final int? maxAppVersionCode;

  bool targetsPlatform(String platform) =>
      platforms.isEmpty || platforms.contains(platform);

  /// 构建号未知（`<= 0`）时不按版本过滤，避免错误隐藏公告。
  bool targetsVersionCode(int versionCode) {
    if (versionCode <= 0) return true;
    final min = minAppVersionCode;
    final max = maxAppVersionCode;
    if (min != null && versionCode < min) return false;
    if (max != null && versionCode > max) return false;
    return true;
  }

  bool targets({required String platform, required int versionCode}) =>
      targetsPlatform(platform) && targetsVersionCode(versionCode);
}
