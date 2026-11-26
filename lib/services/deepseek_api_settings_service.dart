import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 应用级 DeepSeek API Key。
///
/// Key 属于 MyCHU 本身，不属于校园账号；这里刻意不接受 Account、accountKey
/// 或任何其他身份参数，避免登录态变化误删或覆盖用户的 Key。
class DeepSeekApiSettingsService {
  DeepSeekApiSettingsService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final DeepSeekApiSettingsService instance =
      DeepSeekApiSettingsService();

  /// 全局唯一 Key；不要追加账号、游客或其他作用域后缀。
  static const String storageKey = 'mychu.ai.assistant.deepseek.api_key.v1';

  final FlutterSecureStorage _storage;

  /// 原生设置页保存/删除 Key 后递增，供选项页和 AI 页面重新读取。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<String?> read() async {
    final value = await _storage.read(key: storageKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> write(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'API Key 不能为空');
    }
    await _storage.write(key: storageKey, value: trimmed);
    revision.value++;
  }

  Future<void> clear() async {
    await _storage.delete(key: storageKey);
    revision.value++;
  }
}
