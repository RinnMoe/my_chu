import 'dart:convert';

import '../../public_http_client.dart';
import '../announcement_repository.dart';
import '../app_announcement.dart';
import '../../supabase/supabase_project_config.dart';

/// Supabase `app_announcements` 只读数据源。
///
/// 只读取已发布且未过期的行：服务端 RLS 是主要约束，查询条件作为第二道防线。
/// 平台与版本定向在客户端按当前构建过滤，不影响 RLS 的发布态约束。
class SupabaseAnnouncementRepository implements AnnouncementRepository {
  SupabaseAnnouncementRepository({
    required this.config,
    PublicHttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? PublicHttpClient();

  final SupabaseEndpointConfig config;
  final PublicHttpClient _http;
  final Duration timeout;

  static const String table = 'app_announcements';
  static const int fetchLimit = 20;
  static const String _select =
      'id,title,body,priority,published_at,expires_at,platforms,'
      'min_app_version_code,max_app_version_code';

  @override
  Future<List<AppAnnouncement>> fetchAnnouncements() async {
    final response = await _http.get(
      config.restUri(
        table,
        query: {
          'select': _select,
          'status': 'eq.published',
          'order': 'priority.desc,published_at.desc',
          'limit': '$fetchLimit',
        },
      ),
      headers: config.authHeaders,
      timeout: timeout,
    );
    if (response.statusCode != 200) {
      throw PublicHttpException(
        'Supabase 公告不可用（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! List) {
      throw const FormatException('Supabase 公告返回结构异常');
    }
    final items = <AppAnnouncement>[];
    for (final entry in decoded) {
      final parsed = _parseRow(entry);
      // 单条畸形公告跳过，不阻塞整批。
      if (parsed != null) items.add(parsed);
    }
    items.sort(_compare);
    return items;
  }

  static AppAnnouncement? _parseRow(Object? row) {
    if (row is! Map<String, dynamic>) return null;
    final id = row['id'];
    final title = row['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      return null;
    }
    final body = row['body'];
    final priority = row['priority'];
    final platforms = row['platforms'];
    // 平台是定向字段，类型异常时无法判断目标端，整行跳过而不是当作不限平台。
    if (platforms != null && platforms is! List) return null;
    return AppAnnouncement(
      id: id,
      title: title,
      content: body is String ? body : '',
      priority: priority is num ? priority.toInt() : 0,
      publishedAt: _parseTimestamp(row['published_at']),
      platforms: {
        if (platforms is List)
          for (final platform in platforms)
            if (platform is String && platform.isNotEmpty) platform,
      },
      minAppVersionCode: _parseVersionCode(row['min_app_version_code']),
      maxAppVersionCode: _parseVersionCode(row['max_app_version_code']),
    );
  }

  static int? _parseVersionCode(Object? value) =>
      value is num ? value.toInt() : null;

  static DateTime? _parseTimestamp(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static int _compare(AppAnnouncement left, AppAnnouncement right) {
    final priorityCompare = right.priority.compareTo(left.priority);
    if (priorityCompare != 0) return priorityCompare;
    final leftTime = left.publishedAt;
    final rightTime = right.publishedAt;
    if (leftTime != null && rightTime != null) {
      final timeCompare = rightTime.compareTo(leftTime);
      if (timeCompare != 0) return timeCompare;
    } else if (leftTime == null && rightTime != null) {
      return 1;
    } else if (leftTime != null && rightTime == null) {
      return -1;
    }
    return left.id.compareTo(right.id);
  }
}
