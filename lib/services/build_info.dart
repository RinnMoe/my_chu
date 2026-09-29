import 'package:flutter/foundation.dart';

import 'host_platform.dart';

/// The Flutter compilation mode. This is intentionally independent from the
/// distribution channel so a Debug build can never become a release build by
/// changing a string or a persisted setting.
enum BuildMode { debug, profile, release, unknown }

/// The distribution channel used by the artifact.
enum BuildChannel { official, preview, unknown }

BuildMode buildModeForFlags({
  required bool debugBuild,
  required bool profileBuild,
  required bool releaseBuild,
}) {
  if (debugBuild) return BuildMode.debug;
  if (profileBuild) return BuildMode.profile;
  if (releaseBuild) return BuildMode.release;
  return BuildMode.unknown;
}

BuildChannel parseBuildChannel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'official':
      return BuildChannel.official;
    case 'preview':
      return BuildChannel.preview;
    default:
      return BuildChannel.unknown;
  }
}

BuildChannel defaultBuildChannelForPlatform(HostPlatform platform) {
  return platform == HostPlatform.android
      ? BuildChannel.official
      : BuildChannel.unknown;
}

/// Immutable build identity compiled into the application.
///
/// The values are safe to display in diagnostics and release notes. They must
/// never contain credentials, URLs, host names, or raw command output.
@immutable
class BuildInfo {
  const BuildInfo({
    required this.mode,
    required this.channel,
    this.gitSha = 'unknown',
    this.buildId = 'unknown',
    this.buildTimeUtc = 'unknown',
  });

  static const String _rawChannel = String.fromEnvironment(
    'MYCHU_BUILD_CHANNEL',
    defaultValue: '',
  );

  static String get _configuredChannel {
    if (_rawChannel.isNotEmpty) return _rawChannel;
    // Android's Gradle build defaults to Official when no channel define is
    // supplied. Apple direct builds remain fail-closed; the checked-in
    // unsigned Official script injects its channel explicitly.
    return defaultBuildChannelForPlatform(HostPlatform.current).name;
  }

  static final BuildInfo current = BuildInfo(
    mode: buildModeForFlags(
      debugBuild: kDebugMode,
      profileBuild: kProfileMode,
      releaseBuild: kReleaseMode,
    ),
    channel: parseBuildChannel(_configuredChannel),
    gitSha: const String.fromEnvironment(
      'MYCHU_GIT_SHA',
      defaultValue: 'unknown',
    ),
    buildId: const String.fromEnvironment(
      'MYCHU_BUILD_ID',
      defaultValue: 'unknown',
    ),
    buildTimeUtc: const String.fromEnvironment(
      'MYCHU_BUILD_TIME_UTC',
      defaultValue: 'unknown',
    ),
  );

  final BuildMode mode;
  final BuildChannel channel;
  final String gitSha;
  final String buildId;
  final String buildTimeUtc;

  bool get isOfficialRelease =>
      mode == BuildMode.release && channel == BuildChannel.official;

  bool get isPreviewRelease =>
      mode == BuildMode.release && channel == BuildChannel.preview;

  /// Debug builds are sent to Aptabase's separate Debug data stream.
  /// Release analytics remain limited to the official distribution channel.
  bool get allowAnalytics => mode == BuildMode.debug || isOfficialRelease;

  String get displayIdentity {
    final sha = _displayPart(gitSha, maxLength: 12);
    final id = _displayPart(buildId, maxLength: 32);
    return '${mode.name}/${channel.name} · $id · $sha';
  }

  @override
  bool operator ==(Object other) {
    return other is BuildInfo &&
        other.mode == mode &&
        other.channel == channel &&
        other.gitSha == gitSha &&
        other.buildId == buildId &&
        other.buildTimeUtc == buildTimeUtc;
  }

  @override
  int get hashCode => Object.hash(mode, channel, gitSha, buildId, buildTimeUtc);
}

String _displayPart(String value, {required int maxLength}) {
  final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._+:-]'), '_');
  if (normalized.isEmpty) return 'unknown';
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}
