import '../services/service_endpoints.dart';

/// 校园 WebView 证书策略：对 `*.chd.edu.cn` 主机放行不受信证书。
///
/// 校园内网服务（如评教 `jxzlpj.chd.edu.cn:8080`）使用私有 CA 或未预置
/// 中间证书，WebView 默认会因证书校验失败白屏。该策略仅对 `*.chd.edu.cn`
/// 主机接受服务器证书（等价于对校园站点关闭证书校验），其余主机保持系统
/// 默认严格校验。
bool shouldAcceptCampusCertificate(String host) =>
    CampusServiceEndpoints.isChdHost(host);

/// Returns whether a WebView certificate challenge should use the platform's
/// normal certificate validation instead of the campus compatibility override.
///
/// Returning `null` from `onReceivedServerTrustAuthRequest` is intentional:
/// `flutter_inappwebview` then delegates the challenge to native default
/// handling. This keeps external resources such as Taobao/DCloud strict while
/// retaining the existing compatibility path for campus hosts.
bool shouldUseSystemCertificateValidation(String host) =>
    !shouldAcceptCampusCertificate(host);
