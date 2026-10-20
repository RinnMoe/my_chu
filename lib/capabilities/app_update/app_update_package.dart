/// Transport-neutral APK target. Android versionCode is never normalized here.
class AppUpdatePackage {
  const AppUpdatePackage({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    this.deltaManifestUrl,
    this.requireManifest = false,
  });

  final String version;
  final int versionCode;
  final String downloadUrl;
  final String? deltaManifestUrl;
  final bool requireManifest;
}
