import 'package:shared_preferences/shared_preferences.dart';

/// Persistence boundary for the last validated policy snapshot.
abstract class RemoteFeaturePolicyStore {
  Future<String?> read();

  Future<void> write(String raw);

  Future<void> clear();
}

/// Device-local snapshot storage.
///
/// The payload only contains published policy rows: no account, campus or
/// credential data is written here.
class SharedPreferencesFeaturePolicyStore implements RemoteFeaturePolicyStore {
  const SharedPreferencesFeaturePolicyStore();

  static const String storageKey = 'remote_feature_policy.v1.snapshot';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(storageKey);
  }

  @override
  Future<void> write(String raw) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(storageKey, raw);
    if (!saved) throw StateError('远程功能策略缓存写入失败');
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }
}
