import 'package:flutter/services.dart';

import '../../services/logger_service.dart';
import '../../services/platform_compatibility_service.dart';
import '../in_app_download/in_app_download.dart';

/// Host-only capability for handing a downloaded APK to Android's installer.
class AppInstallerCapability {
  static const _defaultChannel = MethodChannel('mychu/app_installer');

  final MethodChannel _channel;

  AppInstallerCapability({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  Future<bool> install(InAppDownloadedFile file) async {
    if (!PlatformCompatibilityService.isAndroid) return false;
    if (file.path.trim().isEmpty ||
        file.sizeBytes <= 0 ||
        !file.fileName.toLowerCase().endsWith('.apk')) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('installPackage', {
            'path': file.path,
            'fileName': file.fileName,
          }) ??
          false;
    } on MissingPluginException {
      AppLogger.warn('系统安装能力不可用');
      return false;
    } on PlatformException catch (error) {
      AppLogger.warn('系统安装程序唤起失败 (${error.code})');
      return false;
    }
  }
}
