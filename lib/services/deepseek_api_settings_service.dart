import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'logging/logger.dart';

enum DeepSeekApiKeyCheckResult { valid, invalidKey, networkError }

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
  static const String _verifyEndpoint = 'https://api.deepseek.com/models';
  static const Duration _verifyTimeout = Duration(seconds: 10);

  final FlutterSecureStorage _storage;

  /// 原生设置页保存/删除 Key 后递增，供选项页和 AI 页面重新读取。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 脱敏展示已配置的 Key，避免在设置页暴露明文。
  static String mask(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length < 10) return '••••';
    return '${trimmed.substring(0, 6)}••••${trimmed.substring(trimmed.length - 4)}';
  }

  Future<String?> read() async {
    final value = await _storage.read(key: storageKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 调用 DeepSeek `/models` 接口校验 Key 是否可用（不产生计费）。
  Future<DeepSeekApiKeyCheckResult> verify(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return DeepSeekApiKeyCheckResult.invalidKey;
    }
    try {
      final response = await http
          .get(
            Uri.parse(_verifyEndpoint),
            headers: {
              'Authorization': 'Bearer $trimmed',
              'Accept': 'application/json',
            },
          )
          .timeout(_verifyTimeout);
      if (response.statusCode == 200) {
        return DeepSeekApiKeyCheckResult.valid;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return DeepSeekApiKeyCheckResult.invalidKey;
      }
      return DeepSeekApiKeyCheckResult.networkError;
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return DeepSeekApiKeyCheckResult.networkError;
    }
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
