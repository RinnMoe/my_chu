import 'dart:convert';

import '../../capabilities/app_update/app_update_package.dart';
import '../public_http_client.dart';
import 'update_offer.dart';

/// Public, read-only gateway. Signing secrets belong to the server, not Dart
/// defines. Fenfa is only a fallback; an explicit empty override disables UL.
class UpgradeLinkConfig {
  const UpgradeLinkConfig({
    this.baseUrl = const String.fromEnvironment(
      'MYCHU_UPGRADELINK_BASE_URL',
      defaultValue: 'https://update.rinn.moe',
    ),
  });
  final String baseUrl;
  bool get isConfigured => baseUrl.trim().isNotEmpty;
  Uri get endpoint {
    final origin = Uri.parse(baseUrl);
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw const FormatException('UpgradeLink requires an HTTPS gateway');
    }
    return Uri.parse(
      '${baseUrl.replaceFirst(RegExp(r"/+$"), "")}/mychu/v1/update',
    );
  }
}

class UpgradeLinkClient {
  UpgradeLinkClient({
    this.config = const UpgradeLinkConfig(),
    PublicHttpClient? httpClient,
  }) : _http = httpClient ?? PublicHttpClient();
  final UpgradeLinkConfig config;
  final PublicHttpClient _http;

  Future<UpdateOffer?> check({
    required int versionCode,
    required String packageName,
  }) async {
    final endpoint = config.endpoint;
    final response = await _http.postJson(
      endpoint,
      body: {'versionCode': versionCode},
    );
    if (response.statusCode != 200 || response.bodyBytes.length > 64 * 1024) {
      throw const FormatException('UpgradeLink response unavailable');
    }
    final body = PublicHttpClient.decodeJsonMap(
      utf8.decode(response.bodyBytes),
    );
    if (body['code'] == 0) return null;
    final data = body['data'];
    if (body['code'] != 200 || data is! Map<String, dynamic>) {
      throw const FormatException('Invalid UpgradeLink response');
    }
    final remoteCode = data['versionCode'];
    final size = data['urlFileSize'];
    final version = data['versionName'];
    final type = data['upgradeType'];
    if (data['packageName'] != packageName ||
        remoteCode is! int ||
        remoteCode <= 0 ||
        size is! int ||
        size <= 0 ||
        size > 1024 * 1024 * 1024 ||
        version is! String ||
        version.isEmpty ||
        version.length > 256 ||
        type is! int ||
        !{1, 2, 3}.contains(type)) {
      throw const FormatException('Invalid UpgradeLink target');
    }
    if (remoteCode <= versionCode) return null;
    Uri url(String key) {
      final value = data[key];
      if (value is! String || value.isEmpty || value.length > 2048) {
        throw const FormatException('Missing verified update URL');
      }
      final uri = endpoint.resolve(value);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Insecure update URL');
      }
      return uri;
    }

    return UpdateOffer(
      provider: UpdateProvider.upgradeLink,
      package: AppUpdatePackage(
        version: version,
        versionCode: remoteCode,
        downloadUrl: url('urlPath').toString(),
        deltaManifestUrl: url('deltaManifestUrl').toString(),
        requireManifest: true,
      ),
      notes:
          data['promptUpgradeContent'] is String
              ? data['promptUpgradeContent'] as String
              : '',
      force: type == 3,
      sizeBytes: size,
    );
  }
}
