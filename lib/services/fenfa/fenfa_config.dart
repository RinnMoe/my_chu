/// Fenfa 公开分发服务配置。
///
/// 只包含公开 API 所需的最小信息；不存放 FENFA_ADMIN_TOKEN /
/// FENFA_UPLOAD_TOKEN / R2 Access Key / R2 Secret Key 等任何管理凭据。
class FenfaConfig {
  const FenfaConfig({
    this.baseUrl = 'https://release.rinn.moe',
    this.productSlug = 'mychu',
    this.variantId = '',
  });

  /// 生产配置（对应 `https://release.rinn.moe/products/mychu`）。
  static const FenfaConfig shared = FenfaConfig();

  /// Fenfa 服务根地址（公开 API 前缀）。
  final String baseUrl;

  /// 本应用在 Fenfa 中的 Product Slug。
  final String productSlug;

  /// Android Variant ID；空 = 单 Variant，多 Variant 发布后在此填写。
  final String variantId;

  /// latest 接口地址；[variantId] 非空时追加 `?variant=`。
  Uri get latestUri {
    final base = Uri.parse('$baseUrl/api/v1/products/$productSlug/latest');
    return variantId.isEmpty
        ? base
        : base.replace(queryParameters: {'variant': variantId});
  }

  /// 公告接口地址。
  Uri get announcementsUri =>
      Uri.parse('$baseUrl/api/v1/products/$productSlug/announcements');

  /// 匿名反馈接口地址。
  Uri get feedbackUri => Uri.parse('$baseUrl/api/v1/feedback');
}
