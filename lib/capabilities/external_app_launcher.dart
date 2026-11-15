import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/logging/logger.dart';

class ExternalAppTarget {
  final Uri uri;
  final String androidPackage;

  const ExternalAppTarget({required this.uri, required this.androidPackage});
}

class ExternalAppLauncher {
  static const _defaultChannel = MethodChannel('mychu/external_app_launcher');

  final MethodChannel _channel;

  ExternalAppLauncher({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  Future<bool> launchPackage(String androidPackage) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final opened =
          await _channel.invokeMethod<bool>('launchPackage', {
            'androidPackage': androidPackage,
          }) ??
          false;
      if (!opened) AppLogger.warn('外部应用未能打开\n$androidPackage');
      return opened;
    } on MissingPluginException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    } on PlatformException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }

  Future<bool> launch(ExternalAppTarget target) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final opened =
          await _channel.invokeMethod<bool>('launch', {
            'uri': target.uri.toString(),
            'androidPackage': target.androidPackage,
          }) ??
          false;
      if (!opened) {
        AppLogger.warn('外部应用未能打开\n${target.androidPackage}\n${target.uri}');
      }
      return opened;
    } on MissingPluginException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    } on PlatformException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }
}
