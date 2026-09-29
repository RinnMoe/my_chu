import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'logger_service.dart';

/// 宿主（MyCHU）版本读取：进程内缓存一次 `PackageInfo`，供应用兼容性校验。
class AppHostVersion {
  static String? _cached;
  static int? _cachedBuild;

  /// 测试钩子：设置后 [current] 直接返回该值。
  @visibleForTesting
  static String? debugOverride;

  /// 测试钩子：设置后 [buildNumber] 直接返回该值。
  @visibleForTesting
  static int? debugBuildOverride;

  /// 当前宿主版本（如 `0.1.0`，不含构建号）。
  static Future<String> get current async {
    final override = debugOverride;
    if (override != null) return override;
    final cached = _cached;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    _cached = info.version;
    return info.version;
  }

  /// 当前宿主构建号（如 `3`，来自 `0.2.0+3` 的 `+3`）。
  ///
  /// 解析失败回退 0（调用方据此跳过更新提示）并记一条 warn。
  static Future<int> get buildNumber async {
    final override = debugBuildOverride;
    if (override != null) return override;
    final cached = _cachedBuild;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    final parsed = int.tryParse(info.buildNumber);
    if (parsed == null || parsed < 0) {
      AppLogger.warn('宿主 buildNumber 解析失败（"${info.buildNumber}"），回退为 0');
      _cachedBuild = 0;
      return 0;
    }
    _cachedBuild = parsed;
    return parsed;
  }

  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _cachedBuild = null;
  }
}
