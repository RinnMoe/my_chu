import 'package:shared_preferences/shared_preferences.dart';

/// 阅读偏好。与账号无关，跟随设备。
class MailPreferences {
  static const showRemoteImagesKey = 'mychu.mail.show_remote_images.v1';

  final Future<SharedPreferences> Function() _preferences;

  MailPreferences({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  Future<bool> showRemoteImages() async {
    final preferences = await _preferences();
    return preferences.getBool(showRemoteImagesKey) ?? false;
  }

  Future<void> setShowRemoteImages(bool value) async {
    final preferences = await _preferences();
    await preferences.setBool(showRemoteImagesKey, value);
  }
}
