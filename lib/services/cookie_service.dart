import '../capabilities/web_view_cookie_coordinator.dart';

class CookieService {
  /// 通过 coordinator 获取指定 URL 的完整 cookies（含 HttpOnly）。
  /// Android 优先使用原生适配器，其他平台或 channel 不可用时回退到
  /// flutter_inappwebview。读取失败会抛出显式错误，不伪装成空 Cookie。
  static Future<String?> getCookies(String url) =>
      WebViewCookieCoordinator.getCookieHeader(Uri.parse(url));
}
