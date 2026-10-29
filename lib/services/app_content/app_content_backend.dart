import '../supabase/supabase_project_config.dart';

/// 应用公告与用户反馈的数据源。
enum AppContentBackend { fenfa, supabase }

/// 构建期数据源配置。
///
/// 与更新通道同构：项目连接可用就用 Supabase，不可用就整体退回 Fenfa，
/// 没有额外的后端选择开关。官方构建必须携带连接；省略连接的本地或开源构建
/// 行为与迁移前一致。
class AppContentBackendConfig {
  const AppContentBackendConfig({
    this.supabaseUrl = SupabaseEndpointConfig.environmentUrl,
    this.supabaseAnonKey = SupabaseEndpointConfig.environmentKey,
    this.announcementFallback = const String.fromEnvironment(
      'MYCHU_ANNOUNCEMENT_FALLBACK',
      defaultValue: 'true',
    ),
  });

  /// 进程默认配置。
  static const AppContentBackendConfig shared = AppContentBackendConfig();

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// 公告读取是否允许回退到 Fenfa。
  ///
  /// 只对只读操作生效；反馈提交永不跨后端回退。
  final String announcementFallback;

  /// 解析为可执行的选择结果；连接不可用时退回 Fenfa。
  AppContentBackendSelection resolve() {
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    if (url.isEmpty) {
      return const AppContentBackendSelection(
        backend: AppContentBackend.fenfa,
        announcementFallbackEnabled: false,
        degradedReason: 'missing_url',
      );
    }
    if (key.isEmpty) {
      return const AppContentBackendSelection(
        backend: AppContentBackend.fenfa,
        announcementFallbackEnabled: false,
        degradedReason: 'missing_anon_key',
      );
    }
    if (SupabaseEndpointConfig.isPrivateKey(key)) {
      return const AppContentBackendSelection(
        backend: AppContentBackend.fenfa,
        announcementFallbackEnabled: false,
        degradedReason: 'private_key_rejected',
      );
    }
    final endpoint = SupabaseEndpointConfig.tryParse(url: url, anonKey: key);
    if (endpoint == null) {
      return const AppContentBackendSelection(
        backend: AppContentBackend.fenfa,
        announcementFallbackEnabled: false,
        degradedReason: 'invalid_endpoint',
      );
    }
    return AppContentBackendSelection(
      backend: AppContentBackend.supabase,
      supabase: endpoint,
      announcementFallbackEnabled: _parseFlag(announcementFallback),
    );
  }

  static bool _parseFlag(String raw) {
    final normalized = raw.trim().toLowerCase();
    return normalized != 'false' && normalized != '0' && normalized != 'no';
  }
}

/// 已解析的数据源选择。
class AppContentBackendSelection {
  const AppContentBackendSelection({
    required this.backend,
    this.supabase,
    this.announcementFallbackEnabled = false,
    this.degradedReason,
  });

  final AppContentBackend backend;
  final SupabaseEndpointConfig? supabase;
  final bool announcementFallbackEnabled;

  /// 配置降级原因代码（不含 URL 或密钥），仅用于本地诊断日志。
  final String? degradedReason;

  bool get isSupabase => backend == AppContentBackend.supabase;
}
