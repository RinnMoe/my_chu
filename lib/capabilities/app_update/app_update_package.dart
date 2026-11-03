/// Transport-neutral APK target. Android versionCode is never normalized here.
class AppUpdatePackage {
  const AppUpdatePackage({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
  });

  final String version;
  final int versionCode;
  final String downloadUrl;
}
