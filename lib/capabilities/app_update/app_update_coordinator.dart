import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/app_remote_services_service.dart';
import '../../services/build_info.dart';
import '../../services/fenfa/fenfa_models.dart';
import '../../services/logger_service.dart';
import '../../services/platform_compatibility_service.dart';
import '../../services/privacy_agreement_service.dart';
import '../in_app_download/in_app_download.dart';
import 'app_update_manifest.dart';
import 'app_update_native.dart';
import 'app_update_package.dart';

typedef PrivateUpdateDownload =
    Future<InAppDownloadedFile> Function({
      required Uri url,
      required File destination,
      required int maxBytes,
      bool Function()? shouldContinue,
      required AppUpdatePhase phase,
      ValueChanged<InAppDownloadProgress>? onProgress,
    });

class AppUpdateCoordinator {
  AppUpdateCoordinator({
    AppUpdateNative native = const AppUpdateNative(),
    PrivateUpdateDownload? download,
    bool Function()? isEligible,
    Future<bool> Function()? isAllowed,
    int Function()? gateRevision,
  }) : _native = native,
       _download = download ?? const InAppDownloadCapability().downloadPrivate,
       _isEligible =
           isEligible ??
           (() =>
               PlatformCompatibilityService.isAndroid &&
               BuildInfo.current.isOfficialRelease),
       _isAllowed =
           isAllowed ??
           (() async =>
               await PrivacyAgreementService.isAccepted() &&
               await AppRemoteServicesService.isEnabled()),
       _gateRevision =
           gateRevision ??
           (() =>
               AppRemoteServicesService.revision.value +
               PrivacyAgreementService.revision.value);

  final AppUpdateNative _native;
  final PrivateUpdateDownload _download;
  final bool Function() _isEligible;
  final Future<bool> Function() _isAllowed;
  final int Function() _gateRevision;
  // Shared across Fenfa instances; a second update must not clean an active task.
  static bool _running = false;

  /// A card offers delta only after checking the actual installed APK. The
  /// transaction repeats these checks because the package may change meanwhile.
  Future<AppUpdatePatch?> matchingPatch(AppUpdatePackage release) async {
    final revision = _gateRevision();
    bool continuing() => revision == _gateRevision();
    if (!_isEligible() || _running || !await _isAllowed() || !continuing()) {
      return null;
    }
    AppUpdateSource? source;
    try {
      source = await _native.inspect();
      if (!source.supportsDelta) return null;
      final full = Uri.parse(release.downloadUrl);
      if (full.scheme != 'https' ||
          full.host.isEmpty ||
          full.userInfo.isNotEmpty) {
        return null;
      }
      final uri =
          release.deltaManifestUrl == null
              ? full.replace(path: '${full.path}.delta.json')
              : Uri.parse(release.deltaManifestUrl!);
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return null;
      if (!continuing() || !await _isAllowed() || !continuing()) return null;
      final file = File('${source.directory}/manifest.json');
      await _download(
        url: uri,
        destination: file,
        maxBytes: 64 * 1024,
        shouldContinue: continuing,
        phase: AppUpdatePhase.preparing,
      );
      final manifest = AppUpdateManifest.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        uri,
      );
      if (!await _isAllowed() ||
          !continuing() ||
          manifest.packageName != source.packageName ||
          manifest.target.version != release.version ||
          manifest.target.versionCode != release.versionCode) {
        return null;
      }
      final patch = manifest.select(
        versionCode: source.versionCode,
        sha256: source.sha256,
      );
      if (patch == null ||
          source.availableBytes <
              manifest.target.size + patch.size + 32 * 1024 * 1024) {
        return null;
      }
      return patch;
    } catch (_) {
      return null;
    } finally {
      if (source != null) {
        try {
          await _native.finish(source, retainApk: false);
        } catch (_) {
          AppLogger.warn('更新预检查缓存清理失败');
        }
      }
    }
  }

  /// Returns null only when the legacy full download should be used.
  /// Once a manifest is accepted, even full fallback is verified against it.
  Future<bool?> tryUpdate(
    FenfaRelease release, {
    required int targetVersionCode,
    required Future<bool> Function(InAppDownloadedFile) install,
    ValueChanged<InAppDownloadProgress>? onProgress,
    bool preferDelta = true,
  }) => tryUpdatePackage(
    AppUpdatePackage(
      version: release.version,
      versionCode: targetVersionCode,
      downloadUrl: release.downloadUrl,
      deltaManifestUrl: release.deltaManifestUrl,
    ),
    install: install,
    onProgress: onProgress,
    preferDelta: preferDelta,
  );

  Future<bool?> tryUpdatePackage(
    AppUpdatePackage release, {
    required Future<bool> Function(InAppDownloadedFile) install,
    ValueChanged<InAppDownloadProgress>? onProgress,
    bool preferDelta = true,
  }) async {
    if (!_isEligible()) return null;
    final targetVersionCode = release.versionCode;
    if (_running) {
      throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
    }
    _running = true;
    AppUpdateSource? source;
    var retainApk = false;
    final revision = _gateRevision();
    bool continuing() => revision == _gateRevision();
    Future<void> check() async {
      if (!continuing() || !await _isAllowed() || !continuing()) {
        throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
      }
    }

    void phase(AppUpdatePhase value) => onProgress?.call(
      InAppDownloadProgress(
        receivedBytes: 0,
        totalBytes: null,
        attempt: 1,
        phase: value,
      ),
    );
    try {
      await check();
      final fullUrl = Uri.parse(release.downloadUrl);
      if (fullUrl.scheme != 'https' || fullUrl.userInfo.isNotEmpty) {
        return null;
      }
      final manifestUri =
          release.deltaManifestUrl == null
              ? fullUrl.replace(path: '${fullUrl.path}.delta.json')
              : Uri.tryParse(release.deltaManifestUrl!);
      if (manifestUri == null ||
          manifestUri.scheme != 'https' ||
          manifestUri.host.isEmpty ||
          manifestUri.userInfo.isNotEmpty) {
        return null;
      }
      phase(AppUpdatePhase.preparing);
      try {
        source = await _native.inspect();
      } catch (_) {
        await check();
        return null;
      }
      await check();
      final task = source;
      final directory = Directory(task.directory);
      AppUpdateManifest manifest;
      try {
        final manifestFile = File('${directory.path}/manifest.json');
        await _download(
          url: manifestUri,
          destination: manifestFile,
          maxBytes: 64 * 1024,
          shouldContinue: continuing,
          phase: AppUpdatePhase.preparing,
        );
        await check();
        manifest = AppUpdateManifest.fromJson(
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>,
          manifestUri,
        );
        if (manifest.packageName != task.packageName ||
            manifest.target.version != release.version ||
            manifest.target.versionCode != targetVersionCode ||
            manifest.target.versionCode <= task.versionCode) {
          return null;
        }
      } catch (_) {
        await check();
        // Optional sidecar absent, malformed or unsupported: old Fenfa still works.
        return null;
      }
      final patch =
          preferDelta && task.supportsDelta
              ? manifest.select(
                versionCode: task.versionCode,
                sha256: task.sha256,
              )
              : null;
      InAppDownloadedFile? output;
      if (patch != null &&
          task.availableBytes >
              manifest.target.size + patch.size + 32 * 1024 * 1024) {
        try {
          await check();
          await _download(
            url: patch.url,
            destination: File('${directory.path}/update.hdiff'),
            maxBytes: patch.size,
            shouldContinue: continuing,
            phase: AppUpdatePhase.downloadingPatch,
            onProgress: onProgress,
          );
          await check();
          phase(AppUpdatePhase.merging);
          await check();
          output = await _native.merge(task, manifest, patch);
          await check();
        } catch (_) {
          await check();
          AppLogger.warn('差分更新失败，改用完整安装包');
        }
      }
      if (output == null) {
        await check();
        if (task.availableBytes < manifest.target.size + 32 * 1024 * 1024) {
          throw const InAppDownloadException(InAppDownloadErrorType.storage);
        }
        phase(AppUpdatePhase.downloadingFull);
        await _download(
          url: fullUrl,
          destination: File('${directory.path}/full.apk'),
          maxBytes: manifest.target.size,
          shouldContinue: continuing,
          phase: AppUpdatePhase.downloadingFull,
          onProgress: onProgress,
        );
        await check();
        phase(AppUpdatePhase.verifying);
        output = await _native.verifyFull(task, manifest);
      }
      await check();
      phase(AppUpdatePhase.installing);
      await check();
      // No fallback after installer cancellation/failure: it would download twice.
      retainApk = await install(output);
      return retainApk;
    } finally {
      if (source != null) {
        try {
          await _native.finish(source, retainApk: retainApk);
        } catch (_) {
          AppLogger.warn('更新缓存清理失败');
        }
      }
      _running = false;
    }
  }
}
