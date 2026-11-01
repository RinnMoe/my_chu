import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../capabilities/app_update/app_update_coordinator.dart';
import '../../capabilities/app_update/app_update_gate.dart';
import '../../capabilities/app_update/app_update_native.dart';
import '../../capabilities/app_update/app_update_patch_plan.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../logger_service.dart';
import 'update_offer.dart';

/// Free space kept beyond the rebuilt target APK and the patch itself.
const int upgradelinkDeltaStorageMargin = 32 * 1024 * 1024;

const InAppDownloadException _cancelled = InAppDownloadException(
  InAppDownloadErrorType.cancelled,
);

/// Decides whether the native HDiffPatch route may be offered at all.
///
/// Official Android releases of the production package are the only builds that
/// may merge a patch against the installed base APK. A Debug build has a
/// different package name and a different installed binary even though it reads
/// the official release stream, so it can never satisfy this check by accident.
class UpgradeLinkDeltaPlanner {
  UpgradeLinkDeltaPlanner({
    AppUpdateNative native = const AppUpdateNative(),
    bool Function()? isEligible,
    Future<bool> Function()? isAllowed,
    int Function()? gateRevision,
  }) : _native = native,
       _isEligible = isEligible ?? AppUpdateGate.deltaEligible,
       _isAllowed = isAllowed ?? AppUpdateGate.allowed,
       _gateRevision = gateRevision ?? AppUpdateGate.revision;

  final AppUpdateNative _native;
  final bool Function() _isEligible;
  final Future<bool> Function() _isAllowed;
  final int Function() _gateRevision;

  /// Returns a UI-ready delta, or null when the full package is the only safe
  /// route.
  Future<AppUpdateDelta?> readiness(
    UpdateOffer offer, {
    required int installedVersionCode,
  }) async {
    final delta = offer.nativeDelta;
    final targetSize = offer.sizeBytes;
    final packageName = offer.packageName;
    if (delta == null || targetSize == null || packageName == null) return null;
    if (!_isEligible()) return null;
    final revision = _gateRevision();
    try {
      if (!await _isAllowed()) return null;
      final host = await _native.capabilities();
      if (revision != _gateRevision() || !await _isAllowed()) return null;
      // The patch was produced for the package and exact version code that the
      // strategy query reported; anything else would merge an unrelated base.
      if (!host.readable ||
          !host.supportsDelta ||
          host.packageName != packageName ||
          host.versionCode != installedVersionCode ||
          offer.package.versionCode <= host.versionCode) {
        return null;
      }
      if (host.availableBytes <
          targetSize + delta.patchSize + upgradelinkDeltaStorageMargin) {
        return null;
      }
      final readiness = AppUpdateDelta(
        patchSize: delta.patchSize,
        targetSize: targetSize,
      );
      return readiness.isWorthwhile ? readiness : null;
    } catch (_) {
      return null;
    }
  }
}

/// One native HDiffPatch rebuild: download the patch, verify it, rebuild the
/// target APK in the host workspace and verify its size, MD5, identity and
/// signature before anything can be installed.
///
/// Returns null only when the caller must fall back to the full package of the
/// same response. Cancellation, withdrawn authorization and stale state throw
/// [InAppDownloadException] so the caller stops instead of downloading again.
class UpgradeLinkDeltaRunner {
  UpgradeLinkDeltaRunner({
    AppUpdateNative native = const AppUpdateNative(),
    PrivateUpdateDownload? download,
  }) : _native = native,
       _download = download ?? const InAppDownloadCapability().downloadPrivate;

  final AppUpdateNative _native;
  final PrivateUpdateDownload _download;

  Future<InAppDownloadedFile?> attempt(
    UpdateOffer offer, {
    required int installedVersionCode,
    required bool Function() shouldContinue,
    required Future<bool> Function() isAllowed,
    ValueChanged<InAppDownloadProgress>? onProgress,
  }) async {
    final delta = offer.nativeDelta;
    final targetSize = offer.sizeBytes;
    final targetMd5 = offer.nativeMd5;
    final packageName = offer.packageName;
    if (delta == null ||
        targetSize == null ||
        targetMd5 == null ||
        packageName == null) {
      return null;
    }

    Future<void> check() async {
      if (!shouldContinue() || !await isAllowed() || !shouldContinue()) {
        throw _cancelled;
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

    AppUpdateSource? source;
    var retain = false;
    try {
      await check();
      phase(AppUpdatePhase.preparing);
      try {
        source = await _native.inspect();
      } on Object {
        await check();
        return null;
      }
      await check();
      final task = source;
      if (task.packageName != packageName ||
          task.versionCode != installedVersionCode ||
          task.versionCode >= offer.package.versionCode ||
          !task.supportsDelta) {
        return null;
      }
      if (task.availableBytes <
          targetSize + delta.patchSize + upgradelinkDeltaStorageMargin) {
        return null;
      }
      final directory = Directory(task.directory);
      final patchFile = File('${directory.path}/update.hdiff');
      phase(AppUpdatePhase.downloadingPatch);
      await check();
      await _download(
        url: delta.patchUrl,
        destination: patchFile,
        maxBytes: delta.patchSize,
        shouldContinue: shouldContinue,
        phase: AppUpdatePhase.downloadingPatch,
        onProgress: onProgress,
      );
      await check();
      // The patch digest is a real upstream value; the host repeats the same
      // check before merging.
      if (await patchFile.length() != delta.patchSize ||
          (await md5.bind(patchFile.openRead()).first).toString() !=
              delta.patchMd5) {
        AppLogger.warn('差分补丁校验失败，改用完整安装包');
        return null;
      }
      phase(AppUpdatePhase.merging);
      await check();
      final merged = await _native.merge(
        task,
        AppUpdatePatchPlan(
          patchSize: delta.patchSize,
          patchHash: delta.patchMd5,
          patchHashAlgorithm: AppUpdateHashAlgorithm.md5,
          patchFormat: AppUpdatePatchFormat.hdiffpatchZlib,
          target: AppUpdateTargetSpec(
            version: offer.package.version,
            versionCode: offer.package.versionCode,
            size: targetSize,
            hash: targetMd5,
            hashAlgorithm: AppUpdateHashAlgorithm.md5,
          ),
        ),
      );
      await check();
      phase(AppUpdatePhase.verifying);
      retain = true;
      return merged;
    } on InAppDownloadException catch (error) {
      if (error.type == InAppDownloadErrorType.cancelled) rethrow;
      await check();
      AppLogger.warn('差分补丁下载失败，改用完整安装包');
      return null;
    } catch (_) {
      await check();
      // Merge, verification and identity failures all land here; the verified
      // full package of the same response remains available.
      AppLogger.warn('原生差分更新失败，改用完整安装包');
      return null;
    } finally {
      if (source != null) {
        try {
          await _native.finish(source, retainApk: retain);
        } catch (_) {
          AppLogger.warn('更新缓存清理失败');
        }
      }
    }
  }
}
