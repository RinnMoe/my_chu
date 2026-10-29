import 'dart:convert';

import 'supabase_project_defaults.dart';

/// Supabase 公开端点配置。
///
/// 只承载公开客户端可持有的信息：项目 URL 与 publishable/anon key。Service
/// Role Key 只用于服务端（Edge Function / Dashboard），不得进入 Flutter 构建。
class SupabaseEndpointConfig {
  /// 编译进客户端的项目地址；`--dart-define=MYCHU_SUPABASE_URL` 可覆盖。
  static const String environmentUrl = String.fromEnvironment(
    'MYCHU_SUPABASE_URL',
    defaultValue: SupabaseProjectDefaults.url,
  );

  /// 编译进客户端的公开密钥；`--dart-define` 可覆盖，旧 ANON_KEY 优先级更低。
  static const String environmentKey = String.fromEnvironment(
    'MYCHU_SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'MYCHU_SUPABASE_ANON_KEY',
      defaultValue: SupabaseProjectDefaults.publishableKey,
    ),
  );

  static SupabaseEndpointConfig? fromEnvironment() =>
      tryParse(url: environmentUrl, anonKey: environmentKey);

  static const privacyBucket = 'privacy-policies';

  /// Public agreement retrieval needs no key or previous acceptance.
  static String privacyResourceRoot({String projectUrl = environmentUrl}) {
    final project = tryParse(
      url: projectUrl,
      anonKey: 'sb_publishable_url_validation',
    );
    return project?.baseUrl
            .replace(path: '/storage/v1/object/public/$privacyBucket/')
            .toString() ??
        '';
  }

  SupabaseEndpointConfig._({required this.baseUrl, required this.anonKey});

  /// 已规范化的项目根地址，例如 `https://abcdefgh.supabase.co`。
  final Uri baseUrl;

  /// 公开可发布的客户端密钥。
  final String anonKey;

  /// 解析并校验构建期配置；非法配置返回 `null`，由调用方安全降级。
  ///
  /// 校验失败只返回 `null` 而不抛出：错误配置不得阻止应用启动。
  static SupabaseEndpointConfig? tryParse({
    required String url,
    required String anonKey,
  }) {
    final normalizedUrl = url.trim();
    final normalizedKey = anonKey.trim();
    if (normalizedUrl.isEmpty || normalizedKey.isEmpty) return null;
    if (_containsWhitespace(normalizedKey)) return null;
    // 私密密钥（service_role / secret key）绝不允许随客户端分发。
    if (isPrivateKey(normalizedKey)) return null;

    final parsed = Uri.tryParse(normalizedUrl);
    if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
      return null;
    }
    if (parsed.hasQuery || parsed.hasFragment) return null;
    if (parsed.path.isNotEmpty && parsed.path != '/') return null;
    final isLoopback =
        parsed.host == '127.0.0.1' ||
        parsed.host == 'localhost' ||
        parsed.host == '::1';
    if (parsed.scheme != 'https' && !(parsed.scheme == 'http' && isLoopback)) {
      return null;
    }
    return SupabaseEndpointConfig._(
      baseUrl: parsed.replace(path: ''),
      anonKey: normalizedKey,
    );
  }

  /// 检测 Supabase 私密密钥前缀。客户端只能使用 publishable/anon key。
  static bool isPrivateKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized.startsWith('sb_secret_') ||
        normalized.startsWith('service_role') ||
        _isPrivilegedJwt(key);
  }

  static bool _isPrivilegedJwt(String key) {
    if (!key.contains('.')) return false;
    try {
      final parts = key.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is! Map || payload['role'] != 'anon';
    } on Object {
      return true;
    }
  }

  static bool _containsWhitespace(String value) =>
      RegExp(r'\s').hasMatch(value);

  /// PostgREST 表地址。
  Uri restUri(String table, {Map<String, String>? query}) {
    final origin = baseUrl.replace(path: '/rest/v1/$table');
    if (query == null || query.isEmpty) return origin;
    return origin.replace(queryParameters: query);
  }

  /// Edge Function 地址。
  Uri functionUri(String name) => baseUrl.replace(path: '/functions/v1/$name');

  /// 公开客户端请求头；不含任何用户身份声明。
  Map<String, String> get authHeaders => {
    'apikey': anonKey,
    if (!anonKey.startsWith('sb_publishable_'))
      'Authorization': 'Bearer $anonKey',
  };
}
