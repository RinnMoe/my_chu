import 'package:flutter/foundation.dart';

/// Content hash algorithms the pinned Android native engine can verify.
///
/// Fenfa sidecar manifests publish SHA-256; the native UpgradeLink APK API only
/// publishes MD5. Both are real upstream-provided digests, so the host engine
/// takes the algorithm explicitly instead of silently reinterpreting one as the
/// other.
enum AppUpdateHashAlgorithm {
  sha256('sha256'),
  md5('md5');

  const AppUpdateHashAlgorithm(this.wireName);

  /// Value sent to the Android host.
  final String wireName;
}

/// Patch containers the pinned native merge engine can apply.
///
/// This is deliberately a closed set: an unknown container must never reach
/// `HPatch.merge`.
enum AppUpdatePatchFormat {
  hdiffpatchZlib('hdiffpatch-zlib');

  const AppUpdatePatchFormat(this.wireName);

  final String wireName;
}

/// One immutable target APK, independent of the protocol that announced it.
@immutable
class AppUpdateTargetSpec {
  const AppUpdateTargetSpec({
    required this.version,
    required this.versionCode,
    required this.size,
    required this.hash,
    required this.hashAlgorithm,
  });

  final String version;
  final int versionCode;
  final int size;
  final String hash;
  final AppUpdateHashAlgorithm hashAlgorithm;
}

/// Everything the host engine needs to rebuild and verify one target APK from
/// one patch. Protocol parsing stays outside this class.
@immutable
class AppUpdatePatchPlan {
  const AppUpdatePatchPlan({
    required this.patchSize,
    required this.patchHash,
    required this.patchHashAlgorithm,
    required this.patchFormat,
    required this.target,
    this.baseSha256,
  });

  final int patchSize;
  final String patchHash;
  final AppUpdateHashAlgorithm patchHashAlgorithm;
  final AppUpdatePatchFormat patchFormat;
  final AppUpdateTargetSpec target;

  /// Exact distributed base APK digest when the protocol publishes one.
  ///
  /// Fenfa requires an exact match. The native UpgradeLink API publishes no
  /// base digest at all, so it stays null there and the host falls back to
  /// proving the installed bytes did not change since inspection.
  final String? baseSha256;
}

/// Transport-neutral delta availability for the update UI.
///
/// Fenfa and native UpgradeLink both produce this; only the sizes are exposed
/// so no protocol model leaks into the page layer.
@immutable
class AppUpdateDelta {
  const AppUpdateDelta({required this.patchSize, required this.targetSize});

  final int patchSize;
  final int targetSize;

  /// A patch must beat this share of the full package to be offered.
  static const double maxSizeRatio = 0.7;

  bool get isWorthwhile =>
      patchSize > 0 && patchSize < targetSize * maxSizeRatio;
}
