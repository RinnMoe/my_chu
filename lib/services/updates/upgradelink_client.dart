import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../capabilities/app_update/app_update_package.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../logger_service.dart';
import '../public_http_client.dart';
import 'upgradelink_delta.dart';
import 'update_offer.dart';

/// Native UpgradeLink credentials are supplied by the private build configuration.
class UpgradeLinkConfig {
  const UpgradeLinkConfig({
    this.baseUrl = const String.fromEnvironment(
      'MYCHU_UPGRADELINK_BASE_URL',
      defaultValue: 'https://mychu.rinn.moe/update',
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

  /// Resolves one UpgradeLink path under the configured base URL.
  ///
  /// A path prefix is allowed so the same client works against both the legacy
  /// root host (`https://update.rinn.moe`) and the unified domain
  /// (`https://mychu.rinn.moe/update`). The signature always covers the logical
  /// path (`/v1/apk/upgrade`), never the prefixed public path, so both entry
  /// points share one preimage.
  Uri endpoint(String path) {
    final origin = Uri.parse(baseUrl);
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && !origin.path.startsWith('/')) ||
        origin.path.contains('..') ||
        origin.path.contains('//')) {
      throw const FormatException('Invalid UpgradeLink origin');
    }
    final prefix =
        origin.path == '/' ? '' : origin.path.replaceFirst(RegExp(r'/+$'), '');
    return origin.replace(path: '$prefix$path', query: null, fragment: null);
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
      // Logical path only: the server verifies this preimage regardless of the
      // public hostname or path prefix the request travelled through.
      'url': path,
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

  Map<String, dynamic> _strategyPayload(int versionCode, int patchAlgo) => {
    'apkKey': config.apkKey,
    'versionCode': versionCode,
    'appointVersionCode': 0,
    'patchAlgo': patchAlgo,
  };

  /// Validates only the transport envelope, so a rejected patch query can be
  /// retried without mistaking a bad target for a bad algorithm.
  static Map<String, dynamic> _envelope(Map<String, dynamic> body) {
    if (body['code'] == 0) return body;
    if (body['code'] != 200 || body['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid UpgradeLink response');
    }
    return body;
  }

  /// Queries the native APK strategy.
  ///
  /// [patchCapable] asks the server for an HDiffPatch (`patchAlgo=1`) strategy.
  /// UpgradeLink 3.1.0 answers that query with an empty HTTP 500 when the
  /// release publishes no patch, so a rejected patch query is retried once as a
  /// full-package query instead of being reported as a service outage. A
  /// transport failure keeps the existing fallback behaviour.
  Future<Map<String, dynamic>> _strategy({
    required int versionCode,
    required bool patchCapable,
  }) async {
    if (!patchCapable) {
      return _envelope(
        await _post('/v1/apk/upgrade', _strategyPayload(versionCode, 0)),
      );
    }
    try {
      return _envelope(
        await _post(
          '/v1/apk/upgrade',
          _strategyPayload(
            versionCode,
            UpgradeLinkPatchAlgorithm.hdiffpatch.wireValue,
          ),
        ),
      );
    } on FormatException {
      AppLogger.warn('原生差分查询不可用，改为完整更新查询');
    }
    return _envelope(
      await _post('/v1/apk/upgrade', _strategyPayload(versionCode, 0)),
    );
  }

  Future<UpdateOffer?> check({
    required int versionCode,
    required String packageName,
    bool patchCapable = false,
  }) async {
    final body = await _strategy(
      versionCode: versionCode,
      patchCapable: patchCapable,
    );
    if (body['code'] == 0) return null;
    final data = body['data'] as Map<String, dynamic>;
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
    final patchAlgo = data['patchAlgo'];
    final algorithm = UpgradeLinkPatchAlgorithm.fromWire(patchAlgo);
    if (patchAlgo != null && algorithm == null) {
      // Never guess what an unknown algorithm would mean, and never let it
      // invalidate the fully verifiable full package of the same response.
      AppLogger.warn('未知的原生差分算法，仅提供完整更新');
    }
    final targetMd5 = checksum.toLowerCase();
    return UpdateOffer(
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
      nativeMd5: targetMd5,
      packageName: packageName,
      nativeDelta:
          algorithm == UpgradeLinkPatchAlgorithm.hdiffpatch
              ? _nativeDelta(data, url, size, targetMd5)
              : null,
    );
  }

  /// Native patch metadata, or null when it cannot be used safely.
  ///
  /// An incomplete patch description never fails the whole response: the
  /// response's full package stays a valid upgrade.
  UpgradeLinkNativeDelta? _nativeDelta(
    Map<String, dynamic> data,
    Uri fullUrl,
    int fullSize,
    String fullMd5,
  ) {
    final rawUrl = data['patchUrlPath'];
    final patchSize = data['patchUrlFileSize'];
    final patchMd5 = data['patchUrlFileMd5'];
    final url =
        rawUrl is String && rawUrl.isNotEmpty ? Uri.tryParse(rawUrl) : null;
    final md5Text =
        patchMd5 is String && patchMd5.isNotEmpty
            ? patchMd5.trim().toLowerCase()
            : null;
    final usable =
        url != null &&
        url.scheme == 'https' &&
        url.host.isNotEmpty &&
        url.userInfo.isEmpty &&
        url.toString() != fullUrl.toString() &&
        patchSize is int &&
        patchSize > 0 &&
        patchSize <= 1024 * 1024 * 1024 &&
        md5Text != null &&
        RegExp(r'^[a-f0-9]{32}$').hasMatch(md5Text) &&
        md5Text != fullMd5;
    if (!usable) {
      AppLogger.warn('原生差分元数据不完整，仅提供完整更新');
      return null;
    }
    if (patchSize >= fullSize) {
      AppLogger.warn('原生差分补丁不小于完整包，仅提供完整更新');
      return null;
    }
    return UpgradeLinkNativeDelta(
      algorithm: UpgradeLinkPatchAlgorithm.hdiffpatch,
      patchUrl: url,
      patchSize: patchSize,
      patchMd5: md5Text,
    );
  }

  /// Reports one completed and verified upgrade download.
  ///
  /// The native contract has no patch-specific event, so a delta rebuild and a
  /// full download both report `app_upgrade_download` exactly once. Failures
  /// are logged and never block a verified APK.
  Future<void> _reportDownload({
    required int localVersionCode,
    required int downloadVersionCode,
  }) async {
    try {
      await _post('/v1/app/report', {
        'eventType': 'app_upgrade_download',
        'timestamp': _now().toUtc().toIso8601String(),
        'appKey': config.apkKey,
        'eventData': {
          'versionCode': localVersionCode,
          'downloadVersionCode': downloadVersionCode,
          'code': 0,
        },
      });
    } on PublicHttpException {
      AppLogger.warn('更新下载统计上报失败');
    } on FormatException {
      AppLogger.warn('更新下载统计响应无效');
    }
  }

  /// Native full-package route: no custom catalog or SHA sidecar is required.
  ///
  /// [tryDelta] is attempted first when supplied. It returns the rebuilt and
  /// host-verified target APK, or null when the delta must fall through to this
  /// method's full package. It must throw [InAppDownloadException] with
  /// [InAppDownloadErrorType.cancelled] when the operation has to stop instead.
  Future<bool> downloadAndInstall(
    UpdateOffer offer, {
    required int localVersionCode,
    required Future<bool> Function(InAppDownloadedFile) install,
    required Future<bool> Function() isAllowed,
    ValueChanged<InAppDownloadProgress>? onProgress,
    bool Function()? shouldContinue,
    Future<InAppDownloadedFile?> Function()? tryDelta,
  }) async {
    assert(offer.sizeBytes != null && offer.nativeMd5 != null);
    // This existing FileProvider root is grantable to the Android installer.
    final root = await Directory(
      '${(await _temporaryDirectory()).path}/app_updates',
    ).create(recursive: true);
    // Retain installer inputs for one day so a retried install reuses the APK.
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
    if (!await isAllowed()) {
      throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
    }
    // A verified delta product is already a complete, identity-checked APK, so
    // it needs no separate download cache and is handed straight to the
    // installer.
    if (tryDelta != null) {
      final merged = await tryDelta();
      if (merged != null) {
        if (!await isAllowed()) {
          throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
        }
        // The native API has no patch-specific report event; a verified rebuild
        // is an upgrade download and reports the same event once.
        await _reportDownload(
          localVersionCode: localVersionCode,
          downloadVersionCode: offer.package.versionCode,
        );
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
        return await install(merged);
      }
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
      // Report only an actual successful full-package download; no device
      // identifier is sent, and a patch rebuild is counted separately above.
      if (downloaded) {
        await _reportDownload(
          localVersionCode: localVersionCode,
          downloadVersionCode: offer.package.versionCode,
        );
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
