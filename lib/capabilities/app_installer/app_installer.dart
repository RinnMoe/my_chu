import 'package:flutter/services.dart';

import '../../services/logging/logger.dart';
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
      final opened =
          await _channel.invokeMethod<bool>('installPackage', {
            'path': file.path,
            'fileName': file.fileName,
          }) ??
          false;
      if (!opened) AppLogger.warn('系统安装程序未能打开\n${file.fileName}\n${file.path}');
      return opened;
    } on MissingPluginException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(
        diagnosticError,
        stackTrace: diagnosticStack,
        context: '系统安装能力不可用',
      );
      return false;
    } on PlatformException catch (error, diagnosticStack) {
      AppLogger.error(
        error,
        stackTrace: diagnosticStack,
        context: '系统安装程序唤起失败 (${error.code})',
      );
      return false;
    }
  }
}
