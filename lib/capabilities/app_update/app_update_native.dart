import 'package:flutter/services.dart';

import '../in_app_download/in_app_download.dart';
import 'app_update_patch_plan.dart';

class AppUpdateSource {
  const AppUpdateSource({
    required this.taskId,
    required this.directory,
    required this.packageName,
    required this.versionCode,
    required this.sha256,
    required this.availableBytes,
    required this.supportsDelta,
  });
  final String taskId;
  final String directory;
  final String packageName;
  final int versionCode;
  final String sha256;
  final int availableBytes;
  final bool supportsDelta;
}

/// Installed-package facts read without creating a workspace task.
///
/// Delta eligibility is decided from this before any patch is requested, so it
/// must stay free of side effects and of the single-task `UPDATE_BUSY` rule.
class AppUpdateHostCapabilities {
  const AppUpdateHostCapabilities({
    required this.packageName,
    required this.versionCode,
    required this.supportsDelta,
    required this.availableBytes,
    required this.readable,
  });

  final String packageName;
  final int versionCode;
  final bool supportsDelta;
  final int availableBytes;
  final bool readable;
}

/// Host-only bridge. No Activity, account or campus session crosses it.
class AppUpdateNative {
  const AppUpdateNative({
    MethodChannel channel = const MethodChannel('mychu/app_update'),
  }) : _channel = channel;
  final MethodChannel _channel;

  Future<AppUpdateHostCapabilities> capabilities() async {
    final data =
        (await _channel.invokeMapMethod<String, dynamic>('capabilities'))!;
    return AppUpdateHostCapabilities(
      packageName: data['packageName'] as String,
      versionCode: data['versionCode'] as int,
      supportsDelta: data['supportsDelta'] == true,
      availableBytes: data['availableBytes'] as int,
      readable: data['readable'] == true,
    );
  }

  Future<AppUpdateSource> inspect() async {
    final data = (await _channel.invokeMapMethod<String, dynamic>('inspect'))!;
    return AppUpdateSource(
      taskId: data['taskId'] as String,
      directory: data['directory'] as String,
      packageName: data['packageName'] as String,
      versionCode: data['versionCode'] as int,
      sha256: data['sha256'] as String,
      availableBytes: data['availableBytes'] as int,
      supportsDelta: data['supportsDelta'] == true,
    );
  }

  Future<InAppDownloadedFile> merge(
    AppUpdateSource source,
    AppUpdatePatchPlan plan,
  ) async {
    final data =
        (await _channel.invokeMapMethod<String, dynamic>('merge', {
          'taskId': source.taskId,
          ..._target(plan.target),
          'patchSize': plan.patchSize,
          'patchHash': plan.patchHash,
          'patchHashAlgorithm': plan.patchHashAlgorithm.wireName,
          'patchFormat': plan.patchFormat.wireName,
          if (plan.baseSha256 != null) 'baseSha256': plan.baseSha256!,
        }))!;
    return _file(data);
  }

  Future<InAppDownloadedFile> verifyFull(
    AppUpdateSource source,
    AppUpdateTargetSpec target,
  ) async {
    final data =
        (await _channel.invokeMapMethod<String, dynamic>('verifyFull', {
          'taskId': source.taskId,
          ..._target(target),
        }))!;
    return _file(data);
  }

  Future<void> finish(AppUpdateSource source, {required bool retainApk}) =>
      _channel.invokeMethod('finish', {
        'taskId': source.taskId,
        'retainApk': retainApk,
      });

  Map<String, Object> _target(AppUpdateTargetSpec target) => {
    'versionCode': target.versionCode,
    'version': target.version,
    'targetSize': target.size,
    'targetHash': target.hash,
    'targetHashAlgorithm': target.hashAlgorithm.wireName,
  };
  InAppDownloadedFile _file(Map<String, dynamic> data) => InAppDownloadedFile(
    path: data['path'] as String,
    fileName: 'MyCHU-update.apk',
    sizeBytes: data['size'] as int,
  );
}
