import '../supabase/supabase_project_config.dart';

/// 构建期数据源配置。
///
/// 应用内容只有 Supabase 一个数据源；连接不可用时整体停用远程内容，不再退回
/// 其他后端。官方构建必须携带连接；省略连接的本地或开源构建会停用公告与反馈。
class AppContentBackendConfig {
  const AppContentBackendConfig({
    this.supabaseUrl = SupabaseEndpointConfig.environmentUrl,
    this.supabaseAnonKey = SupabaseEndpointConfig.environmentKey,
  });

  /// 进程默认配置。
  static const AppContentBackendConfig shared = AppContentBackendConfig();

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// 解析为可执行的选择结果；连接不可用时远程内容整体停用。
  AppContentBackendSelection resolve() {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    if (url.isEmpty) {
      return const AppContentBackendSelection.unavailable('missing_url');
    }
    if (key.isEmpty) {
      return const AppContentBackendSelection.unavailable('missing_anon_key');
    }
    if (SupabaseEndpointConfig.isPrivateKey(key)) {
      return const AppContentBackendSelection.unavailable(
        'private_key_rejected',
      );
    }
    final endpoint = SupabaseEndpointConfig.tryParse(url: url, anonKey: key);
    if (endpoint == null) {
      return const AppContentBackendSelection.unavailable('invalid_endpoint');
    }
    return AppContentBackendSelection.available(endpoint);
  }
}

/// 已解析的数据源选择。
class AppContentBackendSelection {
  const AppContentBackendSelection.available(
    SupabaseEndpointConfig this.endpoint,
  ) : degradedReason = null;

  const AppContentBackendSelection.unavailable(String this.degradedReason)
    : endpoint = null;

  final SupabaseEndpointConfig? endpoint;

  /// 配置降级原因代码（不含 URL 或密钥），仅用于本地诊断日志。
  final String? degradedReason;

  bool get isAvailable => endpoint != null;
}
