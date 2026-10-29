/// 公开项目连接默认值。
///
/// publishable key 按设计随客户端分发，不授予写权限；服务端仍由 RLS 与
/// Edge Function 校验。构建可用 `--dart-define=MYCHU_SUPABASE_URL=...` 与
/// `--dart-define=MYCHU_SUPABASE_PUBLISHABLE_KEY=...` 覆盖，用于指向测试项目或轮换密钥。
class SupabaseProjectDefaults {
  const SupabaseProjectDefaults._();

  static const String url = 'https://qxkmgksgtzjquwwmewlr.supabase.co';

  static const String publishableKey =
      'sb_publishable_AXK19YsJWBsofp8pi9LVBg_Z5GIlGaz';
}
