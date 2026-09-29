import 'dart:convert';

import 'package:http/http.dart' as http;

import '../public_http_client.dart';
import 'fenfa_config.dart';
import 'fenfa_models.dart';

/// Fenfa 公开 API 客户端：只负责 HTTP 请求与响应解析。
///
/// 只调用公开路由（latest / announcements / feedback），不持有任何管理凭据。
class FenfaClient {
  FenfaClient({PublicHttpClient? httpClient, this.config = FenfaConfig.shared})
    : _http = httpClient ?? PublicHttpClient();

  final PublicHttpClient _http;
  final FenfaConfig config;

  /// 获取 latest 的产品、变体和发布上下文。
  Future<FenfaLatestSnapshot> fetchLatestSnapshot() async {
    final response = await _http.get(
      config.latestUri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw PublicHttpException(
        'Fenfa latest 不可用（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final json = PublicHttpClient.decodeJsonMap(_utf8Body(response));
    final data = json['data'];
    if (json['ok'] != true || data is! Map<String, dynamic>) {
      throw const FormatException('Fenfa latest 返回结构异常');
    }
    return FenfaLatestSnapshot.fromJson(data);
  }

  /// 获取最新发布；无已发布 release 时返回 null。
  Future<FenfaRelease?> fetchLatest() async {
    return (await fetchLatestSnapshot()).release;
  }

  /// 提交匿名反馈；只接受 Fenfa 公开 API 的成功响应。
  Future<void> submitFeedback({
    required String productId,
    String variantId = '',
    String releaseId = '',
    required FenfaFeedbackDraft draft,
  }) async {
    final response = await _http.postJson(
      config.feedbackUri,
      body: {
        'product_id': productId,
        'variant_id': variantId,
        'release_id': releaseId,
        'category': draft.category.apiValue,
        'content': draft.content,
        'contact': draft.contact,
        'website': '',
      },
    );
    if (response.statusCode != 201) {
      throw PublicHttpException(
        'Fenfa feedback 不可用（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final json = PublicHttpClient.decodeJsonMap(_utf8Body(response));
    if (json['ok'] != true) {
      throw const FormatException('Fenfa feedback 返回结构异常');
    }
  }

  /// 获取公告；单条畸形公告跳过，不阻塞整批。
  Future<List<FenfaAnnouncement>> fetchAnnouncements() async {
    final response = await _http.get(
      config.announcementsUri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw PublicHttpException(
        'Fenfa announcements 不可用（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final json = PublicHttpClient.decodeJsonMap(_utf8Body(response));
    final data = json['data'];
    if (json['ok'] != true || data is! Map<String, dynamic>) {
      throw const FormatException('Fenfa announcements 返回结构异常');
    }
    final items = data['items'];
    if (items is! List) return const [];
    final result = <FenfaAnnouncement>[];
    for (final entry in items) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        result.add(FenfaAnnouncement.fromJson(entry));
      } on FormatException {
        // 单条异常跳过，不影响其余公告。
      }
    }
    return result;
  }

  /// 按 UTF-8 显式解码响应体，避免服务端缺失 charset 时按 latin-1 误读中文。
  static String _utf8Body(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);
}
