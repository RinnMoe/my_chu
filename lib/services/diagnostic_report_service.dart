import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../capabilities/android_device_compatibility.dart';
import 'build_info.dart';
import 'logging/logger.dart';

/// Text formatting does not enable recording or replay diagnostics to analytics.
class DiagnosticReportService {
  DiagnosticReportService({
    this.appVersion = 'unknown',
    this.appBuild = 'unknown',
    this.deviceProfile,
  });
  final String appVersion;
  final String appBuild;
  final AndroidDeviceProfile? deviceProfile;

  String buildText() {
    final snapshot = AppLogger.entries;
    return <String>[
      'MyCHU 错误日志',
      '生成时间: ${DateTime.now().toIso8601String()}',
      '应用版本: $appVersion ($appBuild)',
      '构建: ${BuildInfo.current.displayIdentity}',
      '平台: ${defaultTargetPlatform.name}',
      if (deviceProfile != null) ...[
        '设备: ${deviceProfile!.brandName} ${deviceProfile!.marketName}',
        '系统: ${deviceProfile!.osName} ${deviceProfile!.osVersionName}',
        'Android SDK: ${deviceProfile!.androidSdkInt}',
      ],
      '记录数: ${snapshot.length}',
      '',
      for (final entry in snapshot) '${entry.toText()}\n',
    ].join('\n');
  }

  String feedbackText() {
    if (AppLogger.entries.isEmpty) return '';
    final text = [
      'MyCHU 诊断摘要',
      '应用版本: $appVersion ($appBuild)',
      if (deviceProfile != null) ...[
        '设备: ${deviceProfile!.brandName} ${deviceProfile!.marketName}',
        '系统: ${deviceProfile!.osName} ${deviceProfile!.osVersionName}',
        'Android SDK: ${deviceProfile!.androidSdkInt}',
      ],
      AppLogger.entries.last.toText(),
    ].join('\n');
    final bytes = utf8.encode(text);
    if (bytes.length <= 1200) return text;
    var end = 1200;
    while (end > 0 && (bytes[end] & 0xc0) == 0x80) {
      end--;
    }
    return utf8.decode(bytes.sublist(0, end));
  }

  String fileName() =>
      'MyCHU-errors-${DateTime.now().millisecondsSinceEpoch}.log';
}
