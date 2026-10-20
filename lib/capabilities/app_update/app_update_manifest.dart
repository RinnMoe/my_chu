/// Versioned, public sidecar for one immutable signed APK.
class AppUpdateTarget {
  const AppUpdateTarget({
    required this.version,
    required this.versionCode,
    required this.sha256,
    required this.size,
  });
  final String version;
  final int versionCode;
  final String sha256;
  final int size;

  factory AppUpdateTarget.fromJson(Map<String, dynamic> json) =>
      AppUpdateTarget(
        version: _text(json, 'version'),
        versionCode: _positive(json, 'version_code'),
        sha256: _hash(json, 'sha256'),
        size: _positive(json, 'size'),
      );
}

class AppUpdatePatch {
  const AppUpdatePatch({
    required this.fromVersionCode,
    required this.fromSha256,
    required this.sha256,
    required this.size,
    required this.url,
  });
  final int fromVersionCode;
  final String fromSha256;
  final String sha256;
  final int size;
  final Uri url;

  factory AppUpdatePatch.fromJson(Map<String, dynamic> json, Uri manifestUri) {
    if (json['algorithm'] != 'hdiffpatch' || json['compression'] != 'zlib') {
      throw const FormatException('Unsupported patch format');
    }
    final url = manifestUri.resolve(_text(json, 'url'));
    if (!_https(url)) throw const FormatException('Invalid patch URL');
    return AppUpdatePatch(
      fromVersionCode: _positive(json, 'from_version_code'),
      fromSha256: _hash(json, 'from_sha256'),
      sha256: _hash(json, 'sha256'),
      size: _positive(json, 'size'),
      url: url,
    );
  }
}

class AppUpdateManifest {
  const AppUpdateManifest({
    required this.packageName,
    required this.target,
    required this.patches,
  });
  final String packageName;
  final AppUpdateTarget target;
  final List<AppUpdatePatch> patches;

  factory AppUpdateManifest.fromJson(
    Map<String, dynamic> json,
    Uri manifestUri,
  ) {
    if (json['schema_version'] != 1 ||
        json['channel'] != 'official' ||
        json['abi'] != 'arm64-v8a' ||
        !_https(manifestUri)) {
      throw const FormatException('Unsupported update manifest');
    }
    final target = json['target'];
    final entries = json['patches'];
    if (target is! Map<String, dynamic> ||
        entries is! List ||
        entries.length > 8) {
      throw const FormatException('Invalid update manifest');
    }
    final patches = <AppUpdatePatch>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        patches.add(AppUpdatePatch.fromJson(entry, manifestUri));
      } on FormatException {
        // One malformed/unsupported patch does not invalidate the full target.
      }
    }
    return AppUpdateManifest(
      packageName: _text(json, 'package_name'),
      target: AppUpdateTarget.fromJson(target),
      patches: List.unmodifiable(patches),
    );
  }

  AppUpdatePatch? select({required int versionCode, required String sha256}) {
    final matching =
        patches
            .where(
              (p) =>
                  p.fromVersionCode == versionCode &&
                  p.fromSha256 == sha256 &&
                  p.fromVersionCode < target.versionCode &&
                  p.size < target.size * 0.7,
            )
            .toList()
          ..sort((a, b) => a.size.compareTo(b.size));
    return matching.isEmpty ? null : matching.first;
  }
}

bool _https(Uri uri) =>
    uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 256) {
    throw const FormatException('Invalid manifest field');
  }
  return value;
}

int _positive(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value <= 0 || value > 1024 * 1024 * 1024) {
    throw const FormatException('Invalid manifest number');
  }
  return value;
}

String _hash(Map<String, dynamic> json, String key) {
  final value = _text(json, key).toLowerCase();
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid manifest hash');
  }
  return value;
}
