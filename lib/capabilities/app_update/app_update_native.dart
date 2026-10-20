import 'package:flutter/services.dart';

import '../in_app_download/in_app_download.dart';
import 'app_update_manifest.dart';

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

/// Host-only bridge. No Activity, account or campus session crosses it.
class AppUpdateNative {
  const AppUpdateNative({
    MethodChannel channel = const MethodChannel('mychu/app_update'),
  }) : _channel = channel;
  final MethodChannel _channel;

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
    AppUpdateManifest manifest,
    AppUpdatePatch patch,
  ) async {
    final data =
        (await _channel.invokeMapMethod<String, dynamic>('merge', {
          ..._target(source, manifest),
          'fromSha256': patch.fromSha256,
          'patchSha256': patch.sha256,
          'patchSize': patch.size,
        }))!;
    return _file(data);
  }

  Future<InAppDownloadedFile> verifyFull(
    AppUpdateSource source,
    AppUpdateManifest manifest,
  ) async {
    final data =
        (await _channel.invokeMapMethod<String, dynamic>(
          'verifyFull',
          _target(source, manifest),
        ))!;
    return _file(data);
  }

  Future<void> finish(AppUpdateSource source, {required bool retainApk}) =>
      _channel.invokeMethod('finish', {
        'taskId': source.taskId,
        'retainApk': retainApk,
      });

  Map<String, Object> _target(
    AppUpdateSource source,
    AppUpdateManifest manifest,
  ) => {
    'taskId': source.taskId,
    'targetSha256': manifest.target.sha256,
    'targetSize': manifest.target.size,
    'versionCode': manifest.target.versionCode,
    'version': manifest.target.version,
  };
  InAppDownloadedFile _file(Map<String, dynamic> data) => InAppDownloadedFile(
    path: data['path'] as String,
    fileName: 'MyCHU-update.apk',
    sizeBytes: data['size'] as int,
  );
}
