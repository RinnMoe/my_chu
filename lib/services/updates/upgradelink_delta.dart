/// Patch algorithms the native UpgradeLink APK API can announce.
///
/// The wire value is `patchAlgo` on both the request and the response: `0` is
/// a full-package upgrade, `1` is an HDiffPatch upgrade. Any other value is
/// treated as a protocol change and rejected by the client.
enum UpgradeLinkPatchAlgorithm {
  none(0),
  hdiffpatch(1);

  const UpgradeLinkPatchAlgorithm(this.wireValue);

  final int wireValue;

  static UpgradeLinkPatchAlgorithm? fromWire(Object? value) {
    if (value is! int) return null;
    for (final algorithm in values) {
      if (algorithm.wireValue == value) return algorithm;
    }
    return null;
  }
}

/// Native HDiffPatch patch metadata from one `POST /v1/apk/upgrade` response.
///
/// This is deliberately its own model: the native UpgradeLink API is not the
/// Fenfa `.delta.json` sidecar and must never be interpreted as one. The target
/// APK's size and digest are not repeated here — they are the response's own
/// `urlFileSize`/`urlFileMd5` full-package fields, kept as the single source of
/// truth on [UpdateOffer].
///
/// The native API publishes MD5 only. There is no upstream SHA-256 for the
/// target APK, so none is invented here.
class UpgradeLinkNativeDelta {
  const UpgradeLinkNativeDelta({
    required this.algorithm,
    required this.patchUrl,
    required this.patchSize,
    required this.patchMd5,
  });

  final UpgradeLinkPatchAlgorithm algorithm;
  final Uri patchUrl;
  final int patchSize;

  /// Lowercase 32-character hexadecimal MD5 of the patch file.
  final String patchMd5;
}
