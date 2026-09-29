import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../capabilities/android_device_compatibility.dart';
import 'app_log_event.dart';
import 'build_info.dart';
import 'error_feedback_service.dart';
import 'platform_environment.dart';

/// A bounded report made only from fields approved for user-visible support.
@immutable
class DiagnosticReport {
  static const defaultMaxFileBytes = 8 * 1024;
  static const defaultMaxFeedbackBytes = 1200;

  DiagnosticReport({
    required this.schemaVersion,
    required this.generatedAt,
    required this.appVersion,
    required this.appBuild,
    this.buildMode = 'unknown',
    this.buildChannel = 'unknown',
    this.gitSha = 'unknown',
    this.buildId = 'unknown',
    this.buildTimeUtc = 'unknown',
    required this.platform,
    required this.deviceFamily,
    required this.windowClass,
    this.deviceProfile,
    required Iterable<AppLogEvent> events,
  }) : events = UnmodifiableListView<AppLogEvent>(
         List<AppLogEvent>.unmodifiable(events),
       );

  final int schemaVersion;
  final DateTime generatedAt;
  final String appVersion;
  final String appBuild;
  final String buildMode;
  final String buildChannel;
  final String gitSha;
  final String buildId;
  final String buildTimeUtc;
  final String platform;
  final String design = 'material';
  final DeviceFamily deviceFamily;
  final WindowClass windowClass;
  final AndroidDeviceProfile? deviceProfile;
  final UnmodifiableListView<AppLogEvent> events;

  /// Renders the report with a byte limit suitable for saving as a text file.
  String toText({int maxBytes = defaultMaxFileBytes}) {
    final header = <String>[
      'MyCHU diagnostics',
      'schemaVersion: $schemaVersion',
      'generatedAt: ${generatedAt.toUtc().toIso8601String()}',
      'appVersion: ${_safeMetadata(appVersion)}',
      'appBuild: ${_safeMetadata(appBuild)}',
      'buildMode: ${_safeMetadata(buildMode)}',
      'buildChannel: ${_safeMetadata(buildChannel)}',
      'gitSha: ${_safeMetadata(gitSha)}',
      'buildId: ${_safeMetadata(buildId)}',
      'buildTimeUtc: ${_safeMetadata(buildTimeUtc)}',
      'platform: ${_safeMetadata(platform)}',
      'design: $design',
      'deviceFamily: ${deviceFamily.name}',
      'windowClass: ${windowClass.name}',
      if (deviceProfile != null) ...[
        'deviceBrand: ${_safeDeviceMetadata(deviceProfile!.brandName)}',
        'deviceMarketName: ${_safeDeviceMetadata(deviceProfile!.marketName)}',
        'androidOs: ${_safeDeviceMetadata(deviceProfile!.osName)}',
        'androidOsVersion: ${_safeDeviceMetadata(deviceProfile!.osVersionName)}',
        'androidOsMajorVersion: ${deviceProfile!.osMajorVersion ?? 'unknown'}',
        'androidSdkInt: ${deviceProfile!.androidSdkInt > 0 ? deviceProfile!.androidSdkInt : 'unknown'}',
      ],
      '',
      'events:',
    ];
    final eventLines = events.map((event) => event.toSafeLine()).toList();
    if (eventLines.isEmpty) eventLines.add('none');
    return _renderLatestWithinLimit(header, eventLines, maxBytes);
  }

  String toFeedbackText({int maxBytes = defaultMaxFeedbackBytes}) {
    return toText(maxBytes: maxBytes);
  }
}

/// Builds a report on demand from the shared safe runtime log.
///
/// The service never reads account state, files, URLs, or exception messages.
/// Callers choose when to build and save/share a report.
class DiagnosticReportService {
  static const maxEvents = 500;

  DiagnosticReportService({
    DiagnosticLogBuffer? diagnostics,
    DateTime Function()? clock,
    this.appVersion = 'unknown',
    this.appBuild = 'unknown',
    BuildInfo? buildInfo,
    PlatformEnvironment? environment,
    TargetPlatform? platform,
    bool? web,
    Iterable<AppLogEvent>? events,
    this.deviceProfile,
  }) : _diagnostics = diagnostics ?? sharedDiagnosticLogBuffer,
       _clock = clock ?? DateTime.now,
       _events =
           events == null
               ? null
               : UnmodifiableListView<AppLogEvent>(
                 List<AppLogEvent>.unmodifiable(events),
               ),
       _environment =
           environment ??
           const PlatformEnvironment(
             deviceFamily: DeviceFamily.phone,
             windowClass: WindowClass.compact,
           ),
       _platform = platform,
       _web = web,
       buildInfo = buildInfo ?? BuildInfo.current;

  final DiagnosticLogBuffer _diagnostics;
  final DateTime Function() _clock;
  final UnmodifiableListView<AppLogEvent>? _events;
  final PlatformEnvironment _environment;
  final TargetPlatform? _platform;
  final bool? _web;
  final String appVersion;
  final String appBuild;
  final BuildInfo buildInfo;
  final AndroidDeviceProfile? deviceProfile;

  /// The live event source shared with the Debug log when using the default.
  DiagnosticLogBuffer get diagnostics => _diagnostics;

  DiagnosticReport build() {
    final environment = _environment;
    final buildInfo = this.buildInfo;
    return DiagnosticReport(
      schemaVersion: 3,
      generatedAt: _clock(),
      appVersion: _safeMetadata(appVersion),
      appBuild: _safeMetadata(appBuild),
      buildMode: _safeMetadata(buildInfo.mode.name),
      buildChannel: _safeMetadata(buildInfo.channel.name),
      gitSha: _safeMetadata(buildInfo.gitSha),
      buildId: _safeMetadata(buildInfo.buildId),
      buildTimeUtc: _safeMetadata(buildInfo.buildTimeUtc),
      platform:
          (_web ?? kIsWeb) ? 'web' : (_platform ?? defaultTargetPlatform).name,
      deviceFamily: environment.deviceFamily,
      windowClass: environment.windowClass,
      deviceProfile: deviceProfile,
      events: _events ?? _diagnostics.snapshotEvents(maxEvents: maxEvents),
    );
  }

  String feedbackText({DiagnosticReport? report}) {
    return (report ?? build()).toFeedbackText();
  }

  String fileName({DiagnosticReport? report}) {
    final generatedAt = (report?.generatedAt ?? _clock()).toUtc();
    final version = report?.appVersion ?? appVersion;
    final timestamp =
        [
          generatedAt.year.toString().padLeft(4, '0'),
          generatedAt.month.toString().padLeft(2, '0'),
          generatedAt.day.toString().padLeft(2, '0'),
          '-',
          generatedAt.hour.toString().padLeft(2, '0'),
          generatedAt.minute.toString().padLeft(2, '0'),
          generatedAt.second.toString().padLeft(2, '0'),
        ].join();
    return 'MyCHU-diagnostics-${_safeFilePart(version)}-$timestamp.txt';
  }
}

String _safeMetadata(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'unknown';
  return normalized.replaceAll(RegExp(r'[^A-Za-z0-9._+\-]'), '_');
}

String _safeDeviceMetadata(String value) {
  final normalized = value.trim().replaceAll(
    RegExp(r'[\u0000-\u001f\u007f\r\n\t|]'),
    ' ',
  );
  if (normalized.isEmpty ||
      RegExp(
        r'https?://|(?:cookie|token|ticket|password|authorization)\s*[:=]',
        caseSensitive: false,
      ).hasMatch(normalized)) {
    return 'unknown';
  }
  return _truncateUtf8(normalized, 128);
}

String _safeFilePart(String value) {
  final normalized = _safeMetadata(value);
  return normalized.isEmpty ? 'unknown' : normalized;
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) return '';
  final encoded = utf8.encode(value);
  if (encoded.length <= maxBytes) return value;

  final result = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final characterBytes = utf8.encode(character).length;
    if (used + characterBytes > maxBytes) break;
    result.write(character);
    used += characterBytes;
  }
  return result.toString();
}

String _renderLatestWithinLimit(
  List<String> header,
  List<String> eventLines,
  int maxBytes,
) {
  if (maxBytes <= 0) return '';
  final prefix = header.join('\n');
  final prefixBytes = utf8.encode(prefix).length;
  if (prefixBytes >= maxBytes) return _truncateUtf8(prefix, maxBytes);

  final selected = <String>[];
  var used = prefixBytes;
  for (final line in eventLines.reversed) {
    final separatorBytes = selected.isEmpty ? 1 : 1;
    final lineBytes = utf8.encode(line).length;
    if (used + separatorBytes + lineBytes > maxBytes) break;
    selected.add(line);
    used += separatorBytes + lineBytes;
  }
  if (selected.isEmpty) return prefix;
  return '$prefix\n${selected.reversed.join('\n')}';
}
