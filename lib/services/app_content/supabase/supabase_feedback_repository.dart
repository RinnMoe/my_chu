import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../host_platform.dart';
import '../../host_version.dart';
import '../../public_http_client.dart';
import '../app_feedback.dart';
import '../feedback_repository.dart';
import '../../supabase/supabase_project_config.dart';

/// Supabase 匿名反馈数据源。
///
/// 统一走 Edge Function（`submit-feedback`），不直接写表：客户端只持有
/// publishable key，写入校验、限流与幂等由服务端负责。
class SupabaseFeedbackRepository implements FeedbackRepository {
  SupabaseFeedbackRepository({
    required this.config,
    PublicHttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
    Future<String> Function()? appVersion,
    Future<int> Function()? appBuild,
    String Function()? platform,
  }) : _http = httpClient ?? PublicHttpClient(),
       _appVersion = appVersion ?? (() => AppHostVersion.current),
       _appBuild = appBuild ?? (() => AppHostVersion.buildNumber),
       _platform = platform ?? (() => HostPlatform.current.name);

  final SupabaseEndpointConfig config;
  final PublicHttpClient _http;
  final Duration timeout;
  final Future<String> Function() _appVersion;
  final Future<int> Function() _appBuild;
  final String Function() _platform;

  static const String functionName = 'submit-feedback';

  @override
  Future<void> submitFeedback(
    AppFeedbackDraft draft, {
    required String requestId,
  }) async {
    final body = <String, Object?>{
      'request_id': requestId,
      'category': draft.category.apiValue,
      'content': draft.content,
      'contact': _blankToNull(draft.contact),
      'diagnostics': _blankToNull(draft.diagnosticLog),
      'app_version': _truncate(await _appVersion(), 32),
      'app_build': _truncate('${await _appBuild()}', 32),
      'platform': _truncate(_platform(), 16),
    };

    final http.Response response;
    try {
      response = await _http.postJson(
        config.functionUri(functionName),
        body: body,
        headers: config.authHeaders,
        timeout: timeout,
      );
    } on PublicHttpException catch (error) {
      // 超时、连接中断或响应读取失败：请求可能已经写入，结果未知。
      throw FeedbackSubmissionUnknownException(error);
    }

    final status = response.statusCode;
    if (status == 429) {
      throw const PublicHttpException('提交过于频繁，请稍后再试。', statusCode: 429);
    }
    if (status >= 400 && status < 500) {
      // 4xx 在写入前被拒绝，可安全地视为明确失败。
      throw PublicHttpException(
        'Supabase 反馈被拒绝（HTTP $status）',
        statusCode: status,
      );
    }
    if (status < 200 || status >= 300) {
      // 5xx：函数可能在写库后才失败，不能断言未写入。
      throw const FeedbackSubmissionUnknownException();
    }

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map || decoded['ok'] != true) {
        throw const FeedbackSubmissionUnknownException();
      }
    } on FormatException catch (error) {
      throw FeedbackSubmissionUnknownException(error);
    }
  }

  static String _truncate(String value, int maxLength) {
    final trimmed = value.trim();
    return trimmed.length <= maxLength
        ? trimmed
        : trimmed.substring(0, maxLength);
  }

  /// 空白内容按缺省处理，避免把只有空格的字段写入数据库。
  static String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
