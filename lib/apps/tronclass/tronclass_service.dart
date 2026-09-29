import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueChanged;

import '../../capabilities/account_scoped_cache.dart';
import '../../capabilities/alert_center.dart';
import '../../capabilities/alert_models.dart';
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
  static const _newTodosProviderId = 'tronclass.todos.new';
  static const _todoDeadlineProviderId = 'tronclass.todo.deadline';

  /// Todo alerts open the embedded todo view in the personal-data app.
  static const todosTargetAppId = 'feature.portal.personal';

  /// Older persisted todo notifications use this unregistered target.
  /// They can remain active across cold starts, so Focus still recognizes
  /// this ID for deduplicating historical todo alerts; AppRegistry resolves
  /// their navigation target to the current personal-data app.
  static const legacyTodosTargetAppId = 'feature.tronclass';

  /// Whether an app ID targets a current or historical todo notification.
  static bool isTodoAlertTarget(String? appId) =>
      appId == todosTargetAppId || appId == legacyTodosTargetAppId;

  /// 新待办事件提醒（订阅制）：首次评估只记录基线，待办集合变化才提醒。
  static final AlertProvider newTodosAlertProvider = AlertProvider(
    id: _newTodosProviderId,
    source: '畅课',
    title: '课程有新的待办',
    kind: AlertKind.event,
    severity: AlertSeverity.info,
    baselineOnFirstEvaluation: true,
    evaluate: (params, data) {
      final todos =
          data is List
              ? data.whereType<TronclassTodo>().toList()
              : const <TronclassTodo>[];
      if (todos.isEmpty) return const [];
      final key = [for (final todo in todos) todo.id]..sort();
      return [
        AlertDraft(
          fingerprintKey: key.join('|'),
          title: '课程有新的待办',
          body: '当前共 ${todos.length} 项待办，点击查看',
          deeplinkAppId: todosTargetAppId,
        ),
      ];
    },
  );

  /// 待办截止提醒提供者（订阅制）：进入提醒窗口的待办才提醒。
  static final AlertProvider todoDeadlineAlertProvider = AlertProvider(
    id: _todoDeadlineProviderId,
    source: '畅课',
    title: '待办即将截止',
    kind: AlertKind.deadline,
    severity: AlertSeverity.warning,
    params: const [
      AlertParamSpec(
        key: 'leadTimeHours',
        label: '提前提醒',
        type: AlertParamType.hours,
        defaultValue: 24,
        min: 1,
        max: 168,
        unit: '小时',
      ),
    ],
    evaluate: (params, data) {
      final todos =
          data is List
              ? data.whereType<TronclassTodo>().toList()
              : const <TronclassTodo>[];
      if (todos.isEmpty) return const [];
      final hours = (params['leadTimeHours'] as num?)?.toDouble() ?? 24;
      final lead = Duration(hours: hours.round());
      final now = east8Now();
      final drafts = <AlertDraft>[];
      for (final todo in todos) {
        final endTime = todo.endTime;
        if (endTime == null || !endTime.isAfter(now)) continue;
        final remaining = endTime.difference(now);
        if (remaining > lead) continue;
        drafts.add(
          AlertDraft(
            fingerprintKey: 'todo:${todo.id}',
            title: '待办即将截止',
            body:
                '${todo.title} · ${todo.courseName} · '
                '${_formatDeadline(endTime)}',
            deeplinkAppId: todosTargetAppId,
          ),
        );
      }
      return drafts;
    },
  );

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

  static Future<void> evaluateTodoAlerts(
    String accountKey,
    List<TronclassTodo> todos,
  ) async {
    await Future.wait<void>([
      AlertCenterService.evaluate(accountKey, _newTodosProviderId, todos),
      AlertCenterService.evaluate(accountKey, _todoDeadlineProviderId, todos),
      AlertCenterService.rebuildScheduled(accountKey, _todoDeadlineProviderId, (
        params,
      ) {
        final hours = (params['leadTimeHours'] as num?)?.round() ?? 24;
        final lead = Duration(hours: hours.clamp(1, 168));
        return [
          for (final todo in todos)
            if (todo.endTime != null)
              ScheduledAlertDraft(
                eventId: 'todo:${todo.id}',
                triggerAt: east8WallClockToUtcInstant(
                  todo.endTime!.subtract(lead),
                ),
                title: '待办即将截止：${todo.title}',
                body: '${todo.courseName} · ${_formatDeadline(todo.endTime!)}',
                deeplinkAppId: todosTargetAppId,
                validUntil: east8WallClockToUtcInstant(todo.endTime!),
              ),
        ];
      }),
    ]);
  }

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
    final todos = await _todosCache.load(
      account.accountKey,
      _loadTodos,
      force: force,
    );
    if (evaluateAlerts) {
      unawaited(evaluateTodoAlerts(account.accountKey, todos));
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
        if (upload['allow_download'] != true) continue;
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
