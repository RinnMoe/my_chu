/// 公开项目连接默认值。
///
/// 默认指向自有域名 `mychu.rinn.moe`：该域名由 Cloudflare Worker 反代到 Supabase
/// 项目（见 `doc/integrations/supabase_mirror.md`），因为 `*.supabase.co` 在部分
/// 网络下不可解析或被阻断。根路径留给落地宣传页，Supabase API 占用
/// `/rest/v1`、`/functions/v1`、`/storage/v1`、`/auth/v1` 命名空间。
///
/// publishable key 按设计随客户端分发，不授予写权限；服务端仍由 RLS 与
/// Edge Function 校验。构建可用 `--dart-define=MYCHU_SUPABASE_URL=...` 与
/// `--dart-define=MYCHU_SUPABASE_PUBLISHABLE_KEY=...` 覆盖（例如临时回退到项目域名）。
class SupabaseProjectDefaults {
  const SupabaseProjectDefaults._();

  static const String url = 'https://mychu.rinn.moe';

  /// Supabase 项目引用。域名被自有域名替代后，项目引用无法再从 URL 推导，
  /// 因此显式记录；它是公开信息（任何客户端请求头里都能看到），不含凭证。
  static const String projectRef = 'qxkmgksgtzjquwwmewlr';

  static const String publishableKey =
      'sb_publishable_AXK19YsJWBsofp8pi9LVBg_Z5GIlGaz';
}
