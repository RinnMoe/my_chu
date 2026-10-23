import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../capabilities/app_update/app_update_package.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../public_http_client.dart';
import '../logger_service.dart';
import 'update_offer.dart';

/// Native UpgradeLink credentials are supplied by the private build configuration.
class UpgradeLinkConfig {
  const UpgradeLinkConfig({
    this.baseUrl = const String.fromEnvironment(
      'MYCHU_UPGRADELINK_BASE_URL',
      defaultValue: 'https://update.rinn.moe',
    ),
    this.apkKey = const String.fromEnvironment('MYCHU_UPGRADELINK_APK_KEY'),
    this.accessKey = const String.fromEnvironment(
      'MYCHU_UPGRADELINK_ACCESS_KEY',
    ),
    this.secretKey = const String.fromEnvironment(
      'MYCHU_UPGRADELINK_SECRET_KEY',
    ),
  });
  final String baseUrl;
  final String apkKey;
  final String accessKey;
  final String secretKey;
  bool get isConfigured =>
      baseUrl.isNotEmpty &&
      apkKey.isNotEmpty &&
      accessKey.isNotEmpty &&
      secretKey.isNotEmpty;
  Uri endpoint(String path) {
    final origin = Uri.parse(baseUrl);
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path != '' && origin.path != '/')) {
      throw const FormatException('Invalid UpgradeLink origin');
    }
    return origin.resolve(path);
  }
}

class UpgradeLinkClient {
  UpgradeLinkClient({
    this.config = const UpgradeLinkConfig(),
    PublicHttpClient? httpClient,
    DateTime Function()? now,
    String Function()? nonce,
    Future<Directory> Function()? temporaryDirectory,
  }) : _http = httpClient ?? PublicHttpClient(),
       _now = now ?? DateTime.now,
       _nonce = nonce ?? _randomNonce,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;
  final UpgradeLinkConfig config;
  final PublicHttpClient _http;
  final DateTime Function() _now;
  final String Function() _nonce;
  final Future<Directory> Function() _temporaryDirectory;
  static String _randomNonce() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (!config.isConfigured) {
      throw const FormatException('UpgradeLink credentials unavailable');
    }
    final endpoint = config.endpoint(path);
    final timestamp = _now().toUtc().toIso8601String();
    final nonce = _nonce();
    final fields = <String, String>{
      'body': jsonEncode(payload),
      'nonce': nonce,
      'secretKey': config.secretKey,
      'timestamp': timestamp,
      'url': endpoint.path,
    };
    final keys = fields.keys.toList()..sort();
    final signature =
        md5
            .convert(
              utf8.encode(keys.map((key) => '$key=${fields[key]}').join('&')),
            )
            .toString();
    final response = await _http.postJson(
      endpoint,
      body: payload,
      headers: {
        'X-AccessKey': config.accessKey,
        'X-Timestamp': timestamp,
        'X-Nonce': nonce,
        'X-Signature': signature,
      },
    );
    if (response.statusCode != 200 || response.bodyBytes.length > 64 * 1024) {
      throw const FormatException('UpgradeLink unavailable');
    }
    return PublicHttpClient.decodeJsonMap(utf8.decode(response.bodyBytes));
  }

  Future<UpdateOffer?> check({
    required int versionCode,
    required String packageName,
  }) async {
    final body = await _post('/v1/apk/upgrade', {
      'apkKey': config.apkKey,
      'versionCode': versionCode,
      'appointVersionCode': 0,
      'patchAlgo': 0,
    });
    if (body['code'] == 0) return null;
    final data = body['data'];
    if (body['code'] != 200 || data is! Map<String, dynamic>) {
      throw const FormatException('Invalid UpgradeLink response');
    }
    final code = data['versionCode'];
    final size = data['urlFileSize'];
    final version = data['versionName'];
    final type = data['upgradeType'];
    final checksum = data['urlFileMd5'];
    final url =
        data['urlPath'] is String ? Uri.tryParse(data['urlPath']) : null;
    if (data['apkKey'] != config.apkKey ||
        data['packageName'] != packageName ||
        code is! int ||
        code <= 0 ||
        size is! int ||
        size <= 0 ||
        size > 1024 * 1024 * 1024 ||
        version is! String ||
        version.isEmpty ||
        type is! int ||
        !{0, 1, 2, 3}.contains(type) ||
        checksum is! String ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(checksum) ||
        url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const FormatException('Invalid UpgradeLink target');
    }
    if (code <= versionCode) return null;
    return UpdateOffer(
      provider: UpdateProvider.upgradeLink,
      package: AppUpdatePackage(
        version: version,
        versionCode: code,
        downloadUrl: url.toString(),
      ),
      notes:
          data['promptUpgradeContent'] is String
              ? data['promptUpgradeContent']
              : '',
      force: type == 3,
      sizeBytes: size,
      nativeMd5: checksum.toLowerCase(),
    );
  }

  /// Native full-package route: no custom catalog or SHA sidecar is required.
  Future<bool> downloadAndInstall(
    UpdateOffer offer, {
    required int localVersionCode,
    required Future<bool> Function(InAppDownloadedFile) install,
    required Future<bool> Function() isAllowed,
    ValueChanged<InAppDownloadProgress>? onProgress,
    bool Function()? shouldContinue,
  }) async {
    assert(
      offer.provider == UpdateProvider.upgradeLink &&
          offer.sizeBytes != null &&
          offer.nativeMd5 != null,
    );
    // This existing FileProvider root is grantable to the Android installer.
    final root = await Directory(
      '${(await _temporaryDirectory()).path}/app_updates',
    ).create(recursive: true);
    // As with the Fenfa transaction, retain installer inputs for one day.
    // Only our expired task directories are eligible; never follow links.
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory &&
            RegExp(r'^ul-update-[a-f0-9]{32}$').hasMatch(
              entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
            ) &&
            _now().difference((await entity.stat()).modified) >
                const Duration(days: 1)) {
          await entity.delete(recursive: true);
        }
      }
    } on FileSystemException {
      AppLogger.warn('更新缓存清理失败');
    }
    final cacheKey = md5.convert(
      utf8.encode(
        jsonEncode([
          config.apkKey,
          offer.package.versionCode,
          offer.sizeBytes,
          offer.nativeMd5,
        ]),
      ),
    );
    if (!await isAllowed()) {
      throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
    }
    final directory =
        await Directory('${root.path}/ul-update-$cacheKey').create();
    var verified = false;
    try {
      final file = File('${directory.path}/update.apk');
      Future<bool> matches() async =>
          await file.exists() &&
          await file.length() == offer.sizeBytes &&
          (await md5.bind(file.openRead()).first).toString() == offer.nativeMd5;
      verified = await matches();
      onProgress?.call(
        const InAppDownloadProgress(
          receivedBytes: 0,
          totalBytes: null,
          attempt: 1,
          phase: AppUpdatePhase.verifying,
        ),
      );
      var downloaded = false;
      if (!verified) {
        await InAppDownloadCapability(publicHttpClient: _http).downloadPrivate(
          url: Uri.parse(offer.package.downloadUrl),
          destination: file,
          maxBytes: offer.sizeBytes!,
          shouldContinue: shouldContinue,
          onProgress: onProgress,
        );
        if (!await matches()) {
          throw const InAppDownloadException(InAppDownloadErrorType.network);
        }
        downloaded = true;
      }
      verified = true;
      if (!await isAllowed()) {
        throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
      }
      // Report only an actual successful download; no device identifier is sent.
      if (downloaded) {
        try {
          await _post('/v1/app/report', {
            'eventType': 'app_upgrade_download',
            'timestamp': _now().toUtc().toIso8601String(),
            'appKey': config.apkKey,
            'eventData': {
              'versionCode': localVersionCode,
              'downloadVersionCode': offer.package.versionCode,
              'code': 0,
            },
          });
        } on PublicHttpException {
          AppLogger.warn('更新下载统计上报失败');
        } on FormatException {
          AppLogger.warn('更新下载统计响应无效');
        }
      }
      if (!await isAllowed()) {
        throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
      }
      onProgress?.call(
        const InAppDownloadProgress(
          receivedBytes: 0,
          totalBytes: null,
          attempt: 1,
          phase: AppUpdatePhase.installing,
        ),
      );
      return await install(
        InAppDownloadedFile(
          path: file.path,
          fileName: 'update.apk',
          sizeBytes: offer.sizeBytes!,
        ),
      );
    } finally {
      // Keep verified bytes even if installation is cancelled or unavailable.
      if (!verified) {
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
        } on FileSystemException {
          AppLogger.warn('更新缓存清理失败');
        }
      }
    }
  }
}
