import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  Future<bool> launch(ExternalAppTarget target) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('launch', {
            'uri': target.uri.toString(),
            'androidPackage': target.androidPackage,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
