import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueChanged, visibleForTesting;

import '../../capabilities/account_scoped_cache.dart';
import '../../services/time_reminder_service.dart';
import '../../capabilities/east8_time.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../../services/auth_service.dart';
import '../../services/campus_session.dart';
import '../../services/service_endpoints.dart';
import 'tronclass_models.dart';

const _mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 '
    'Mobile Safari/537.36 TronClass/Common';

/// 畅课数据服务：待办列表与课件下载，全部通过 `CampusSession` 共享会话调用。
class TronclassService {
  static const todosTargetAppId = 'feature.portal.personal';

  TronclassService({String? baseUrl})
    : baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/+$'), '');

  static const defaultBaseUrl = CampusServiceEndpoints.courseBase;
  static const _summaryTtl = Duration(seconds: 20);
  static const _requestTimeout = Duration(seconds: 12);
  static const _courseFields =
      'id,name,display_name,course_code,department(id,name),'
      'instructors(id,name),second_name,start_date,end_date';

  static final _client = CampusSession.client(CampusServices.courseOnline);
  static const _downloadCapability = InAppDownloadCapability();
  static final AccountScopedCache<List<TronclassTodo>> _todosCache =
      AccountScopedCache<List<TronclassTodo>>(ttl: _summaryTtl);

  static Future<void> scheduleTodoReminders(
    String accountKey,
    List<TronclassTodo> todos,
  ) => TimeReminderService.replaceEvents(
    accountKey,
    TimeReminderCategory.deadline,
    () => todoReminderEvents(todos),
  );

  static List<TimeReminderEvent> todoReminderEvents(
    List<TronclassTodo> todos,
  ) => [
    for (final todo in todos)
      if (todo.endTime != null && todo.submitRate < 100)
        TimeReminderEvent(
          id: 'todo:${todo.id}',
          at: east8WallClockToUtcInstant(todo.endTime!),
          title: '待办即将截止：${todo.title}',
          body: '${todo.courseName} · ${_formatDeadline(todo.endTime!)}',
        ),
  ];

  final String baseUrl;

  /// 待办列表：`GET /api/todos`，按账号做短时内存缓存（单飞）。
  Future<List<TronclassTodo>> fetchTodos({
    bool force = false,
    bool evaluateAlerts = true,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      throw const TronclassException('请先登录后再读取畅课待办');
    }
    final revision = AuthService.sessionRevision;
    final todos = await _todosCache.load(
      account.accountKey,
      _loadTodos,
      force: force,
    );
    if (evaluateAlerts && revision == AuthService.sessionRevision) {
      unawaited(scheduleTodoReminders(account.accountKey, todos));
    }
    return todos;
  }

  Future<List<TronclassTodo>> _loadTodos() async {
    final response = await _client.request(
      'GET',
      '$baseUrl/api/todos',
      extraHeaders: _headers(),
      requestTimeout: _requestTimeout,
      responseTimeout: _requestTimeout,
      throwOnHttpError: false,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw TronclassException('待办请求失败（HTTP ${response.statusCode}）');
    }
    final decoded = _decodeJson(response.body);
    final rawList =
        decoded is Map<String, dynamic>
            ? decoded['todo_list']
            : decoded is List
            ? decoded
            : null;
    if (rawList is! List) {
      throw const TronclassException('待办接口返回格式异常');
    }
    return rawList
        .whereType<Map>()
        .map((item) => TronclassTodo.fromJson(Map<String, dynamic>.from(item)))
        .where((todo) => todo.title.isNotEmpty)
        .toList(growable: false);
  }

  /// 课程列表分页：`POST /api/my-courses`，一次只取一页，供列表懒加载使用。
  ///
  /// 接口请求 `classify_type=recently_started`（按最近开课分类），并返回
  /// 每门课的 `start_date`；客户端按 [TronclassCourse.startDate] 倒序排列，
  /// 保证最新课程在最上面。
  Future<TronclassCoursePage> fetchCoursesPage({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _client.request(
      'POST',
      '$baseUrl/api/my-courses',
      body: {
        'fields': _courseFields,
        'page': page,
        'page_size': pageSize,
        'conditions': {
          'keyword': '',
          'classify_type': 'recently_started',
          'display_studio_list': false,
        },
        'showScorePassedStatus': false,
      },
      extraHeaders: _headers(),
      requestTimeout: _requestTimeout,
      responseTimeout: _requestTimeout,
      throwOnHttpError: false,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw TronclassException('课程列表请求失败（HTTP ${response.statusCode}）');
    }
    final decoded = _decodeJson(response.body);
    final data =
        decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    final rawCourses = data['courses'];
    final courses =
        rawCourses is List
            ? rawCourses
                .whereType<Map>()
                .map(
                  (item) =>
                      TronclassCourse.fromJson(Map<String, dynamic>.from(item)),
                )
                .where((course) => course.id.isNotEmpty)
                .toList(growable: false)
            : const <TronclassCourse>[];
    final rawPages = data['pages'];
    final pages = rawPages is num ? rawPages.toInt() : 1;
    return TronclassCoursePage(courses: courses, pages: pages);
  }

  /// 课件文件列表：一次读取课程活动及其 uploads。
  Future<List<TronclassCoursewareFile>> fetchCoursewareFiles(
    TronclassCourse course, {
    ValueChanged<TronclassCoursewareProgress>? onProgress,
    ValueChanged<List<TronclassCoursewareFile>>? onFilesUpdated,
  }) async {
    if (course.id.isEmpty) throw const TronclassException('课程缺少 ID');

    final data = await _requestJson(
      'GET',
      '$baseUrl/api/courses/${Uri.encodeComponent(course.id)}/activities?sub_course_id=0',
    );
    final activities = data['activities'];
    if (activities is! List) {
      throw const TronclassException('课件活动响应格式异常');
    }
    final files = parseCoursewareActivities(activities, course: course);
    onProgress?.call(
      TronclassCoursewareProgress(
        completed: activities.length,
        total: activities.length,
        found: files.length,
        failed: 0,
      ),
    );
    onFilesUpdated?.call(List<TronclassCoursewareFile>.unmodifiable(files));
    return files;
  }

  @visibleForTesting
  static List<TronclassCoursewareFile> parseCoursewareActivities(
    List<dynamic> activities, {
    required TronclassCourse course,
  }) {
    final files = <TronclassCoursewareFile>[];
    final seenKeys = <String>{};
    for (final rawActivity in activities) {
      if (rawActivity is! Map) {
        throw const TronclassException('课件活动响应格式异常');
      }
      final activity = Map<String, dynamic>.from(rawActivity);
      if (activity['type'] != 'material') continue;
      final activityId = activity['id']?.toString().trim() ?? '';
      if (activityId.isEmpty) {
        throw const TronclassException('课件活动响应格式异常');
      }
      final rawUploads = activity['uploads'];
      if (rawUploads == null) continue;
      if (rawUploads is! List) {
        throw const TronclassException('课件活动响应格式异常');
      }

      for (final rawUpload in rawUploads) {
        if (rawUpload is! Map) {
          throw const TronclassException('课件活动响应格式异常');
        }
        final upload = Map<String, dynamic>.from(rawUpload);
        // 与 TronClass++ 一致：使用 reference_id 获取 preview=true 的文件链接，
        // 不按网页下载按钮的 allow_download 标记过滤可读取的附件。
        final file = TronclassCoursewareFile.fromJson(
          upload,
          course: course,
          activityId: activityId,
          activityTitle: activity['title']?.toString().trim() ?? '',
        );
        if (file.fileId.isEmpty) {
          throw const TronclassException('课件活动响应格式异常');
        }
        final key = '${course.id}:$activityId:${file.fileId}';
        if (seenKeys.add(key)) files.add(file);
      }
    }

    files.sort(_compareCoursewareFiles);
    return files;
  }

  /// 下载课件：取下载链接后交给公共应用内下载能力保存。
  Future<InAppDownloadedFile> downloadCoursewareFile(
    TronclassCoursewareFile file, {
    ValueChanged<InAppDownloadProgress>? onProgress,
  }) async {
    if (file.fileId.isEmpty) throw const TronclassException('课件缺少文件 ID');

    final data = await _requestJson(
      'GET',
      '$baseUrl/api/uploads/reference/document/${file.fileId}/url?preview=true',
    );
    final url = data['url']?.toString().trim() ?? '';
    if (url.isEmpty || data['status'] == 'failed') {
      throw const TronclassException('无法获取下载链接');
    }
    final baseUri = Uri.parse(baseUrl);
    final downloadUri = baseUri.resolve(url);

    return _downloadCapability.download(
      url: downloadUri,
      fileName: file.name.isEmpty ? 'courseware' : file.name,
      extraHeaders: _headers(),
      requestTimeout: const Duration(seconds: 60),
      responseTimeout: const Duration(seconds: 60),
      onProgress: onProgress,
    );
  }

  Future<Map<String, dynamic>> _requestJson(String method, String url) async {
    final response = await _client.request(
      method,
      url,
      extraHeaders: _headers(),
      requestTimeout: _requestTimeout,
      responseTimeout: const Duration(seconds: 15),
      throwOnHttpError: false,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw TronclassException('请求失败（HTTP ${response.statusCode}）');
    }
    final decoded = _decodeJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TronclassException('接口返回格式异常');
    }
    return decoded;
  }

  Map<String, String> _headers() {
    return {
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'User-Agent': _mobileUserAgent,
      'sec-ch-ua-platform': '"Android"',
      'x-requested-with': 'XMLHttpRequest',
    };
  }
}

String _formatDeadline(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}月${time.day}日 ${two(time.hour)}:${two(time.minute)}';
}

Object? _decodeJson(String body) {
  final text = body.trim();
  if (text.isEmpty) return null;
  final cleaned = text.startsWith('\uFEFF') ? text.substring(1) : text;
  try {
    return jsonDecode(cleaned);
  } catch (_) {
    return null;
  }
}

int _compareCoursewareFiles(
  TronclassCoursewareFile a,
  TronclassCoursewareFile b,
) {
  final activityCompare = a.activityTitle.compareTo(b.activityTitle);
  if (activityCompare != 0) return activityCompare;
  return a.name.compareTo(b.name);
}
