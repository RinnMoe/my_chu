import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app_remote_services_service.dart';
import '../host_platform.dart';
import '../host_version.dart';
import '../logger_service.dart';
import '../public_http_client.dart';
import '../privacy_agreement_service.dart';
import '../supabase/supabase_privacy_gate.dart';
import 'announcement_repository.dart';
import 'app_announcement.dart';
import 'app_content_backend.dart';
import 'app_feedback.dart';
import 'feedback_repository.dart';
import 'supabase/supabase_announcement_repository.dart';
import 'supabase/supabase_feedback_repository.dart';

/// 应用公告与用户反馈的统一入口。
///
/// 职责：
/// - 遵守“应用远程服务”开关；
/// - 公告的短时缓存、单飞与失败降级；
/// - 反馈的长度校验、单次提交与幂等键生命周期；
/// - 公告的平台/版本定向过滤。
///
/// 数据源由 [AppContentBackendConfig] 在构建期决定。公告读取失败可以回退到
/// Fenfa；反馈提交固定单一目标，结果不确定时不自动改投其他后端。
class AppContentService {
  AppContentService({
    required AnnouncementRepository announcementRepository,
    required FeedbackRepository feedbackRepository,
    AnnouncementRepository? fallbackAnnouncementRepository,
    this.backend = AppContentBackend.fenfa,
    Future<bool> Function()? consentCheck,
    Future<bool> Function()? isRemoteServicesEnabled,
    ValueListenable<int>? remoteServicesRevision,
    Future<int> Function()? appVersionCode,
    String Function()? platformName,
    DateTime Function()? clock,
    String Function()? requestIdGenerator,
    this.announcementTtl = const Duration(minutes: 5),
  }) : _announcementRepository = announcementRepository,
       _feedbackRepository = feedbackRepository,
       _fallbackAnnouncementRepository = fallbackAnnouncementRepository,
       _consentCheck =
           consentCheck ??
           (backend == AppContentBackend.supabase
               ? SupabasePrivacyGate.isAccepted
               : PrivacyAgreementService.isAccepted),
       _isEnabled =
           isRemoteServicesEnabled ?? AppRemoteServicesService.isEnabled,
       _revision = remoteServicesRevision ?? AppRemoteServicesService.revision,
       _appVersionCode = appVersionCode ?? (() => AppHostVersion.buildNumber),
       _platformName = platformName ?? (() => HostPlatform.current.name),
       _clock = clock ?? DateTime.now,
       _requestIdGenerator = requestIdGenerator ?? _generateRequestId;

  /// 按构建期配置装配的数据源。
  factory AppContentService.fromConfig(
    AppContentBackendConfig config, {
    Future<bool> Function()? consentCheck,
    Future<bool> Function()? isRemoteServicesEnabled,
    ValueListenable<int>? remoteServicesRevision,
    Future<int> Function()? appVersionCode,
    String Function()? platformName,
    DateTime Function()? clock,
    String Function()? requestIdGenerator,
  }) {
    final selection = config.resolve();
    final endpoint = selection.supabase;
    if (!selection.isSupabase || endpoint == null) {
      final degradedReason = selection.degradedReason;
      // 默认后端就是 Supabase，因此“没有配置项目”是正常构建形态而非异常；
      // 只有配置存在却不可用时才值得告警。
      if (degradedReason != null && degradedReason != 'missing_url') {
        AppLogger.warn('应用内容数据源配置已降级为 Fenfa（$degradedReason）');
      }
      return AppContentService(
        announcementRepository: FenfaAnnouncementRepository(),
        feedbackRepository: FenfaFeedbackRepository(),
        consentCheck: consentCheck,
        isRemoteServicesEnabled: isRemoteServicesEnabled,
        remoteServicesRevision: remoteServicesRevision,
        appVersionCode: appVersionCode,
        platformName: platformName,
        clock: clock,
        requestIdGenerator: requestIdGenerator,
      );
    }
    final fallbackLabel = selection.announcementFallbackEnabled ? '开启' : '关闭';
    AppLogger.info('应用内容数据源：Supabase（公告回退$fallbackLabel）');
    return AppContentService(
      backend: AppContentBackend.supabase,
      announcementRepository: SupabaseAnnouncementRepository(config: endpoint),
      feedbackRepository: SupabaseFeedbackRepository(config: endpoint),
      // 只读操作允许回退；反馈永不跨后端回退。
      fallbackAnnouncementRepository:
          selection.announcementFallbackEnabled
              ? FenfaAnnouncementRepository()
              : null,
      consentCheck: consentCheck,
      isRemoteServicesEnabled: isRemoteServicesEnabled,
      remoteServicesRevision: remoteServicesRevision,
      appVersionCode: appVersionCode,
      platformName: platformName,
      clock: clock,
      requestIdGenerator: requestIdGenerator,
    );
  }

  /// 进程内共享实例；首页 Focus 与反馈页共用同一份缓存与幂等状态。
  static final AppContentService shared = AppContentService.fromConfig(
    AppContentBackendConfig.shared,
  );

  final AppContentBackend backend;
  final Duration announcementTtl;

  final AnnouncementRepository _announcementRepository;
  final FeedbackRepository _feedbackRepository;
  final AnnouncementRepository? _fallbackAnnouncementRepository;
  final Future<bool> Function() _isEnabled;
  final Future<bool> Function() _consentCheck;

  Future<bool> _canRequest() async =>
      await _consentCheck() && await _isEnabled();
  final ValueListenable<int> _revision;
  final Future<int> Function() _appVersionCode;
  final String Function() _platformName;
  final DateTime Function() _clock;
  final String Function() _requestIdGenerator;

  List<AppAnnouncement>? _cachedAnnouncements;
  DateTime? _announcementsFetchedAt;
  int? _announcementsCacheRevision;
  Future<List<AppAnnouncement>>? _inFlightAnnouncements;
  int? _inFlightAnnouncementsRevision;

  bool _feedbackInFlight = false;
  _PendingFeedbackRequest? _pendingFeedbackRequest;

  /// 首页 Focus 使用当前公告；短时缓存避免其他 Focus 来源刷新时重复请求。
  Future<List<AppAnnouncement>> loadAnnouncements({bool force = false}) async {
    final revision = _revision.value;
    if (!await _canRequest()) {
      _resetAnnouncementCache();
      return const [];
    }
    final fetchedAt = _announcementsFetchedAt;
    final cached = _cachedAnnouncements;
    if (!force &&
        _announcementsCacheRevision == revision &&
        cached != null &&
        fetchedAt != null &&
        _clock().difference(fetchedAt) < announcementTtl) {
      return cached;
    }
    final running = _inFlightAnnouncements;
    if (running != null && _inFlightAnnouncementsRevision == revision) {
      return running;
    }
    final future = _fetchAnnouncements(revision);
    _inFlightAnnouncements = future;
    _inFlightAnnouncementsRevision = revision;
    try {
      return await future;
    } finally {
      if (identical(_inFlightAnnouncements, future)) {
        _inFlightAnnouncements = null;
        _inFlightAnnouncementsRevision = null;
      }
    }
  }

  Future<List<AppAnnouncement>> _fetchAnnouncements(int revision) async {
    try {
      final items = await _announcementRepository.fetchAnnouncements();
      return _commitAnnouncements(items, revision);
    } catch (error) {
      AppLogger.warn('应用公告读取失败（已降级：${_describe(error)}）');
      final fallback = _fallbackAnnouncementRepository;
      if (fallback == null ||
          !await _canRequest() ||
          _revision.value != revision) {
        return const [];
      }
      try {
        final items = await fallback.fetchAnnouncements();
        return _commitAnnouncements(items, revision);
      } catch (fallbackError) {
        AppLogger.warn('应用公告回退读取失败（已降级：${_describe(fallbackError)}）');
        return const [];
      }
    }
  }

  /// 只记录异常类型与 HTTP 状态码，不记录 URL、请求参数或响应正文。
  static String _describe(Object error) {
    if (error is PublicHttpException) {
      final status = error.statusCode;
      return status == null
          ? '${error.runtimeType}/${error.failureReason.name}'
          : '${error.runtimeType}/HTTP $status';
    }
    return '${error.runtimeType}';
  }

  Future<List<AppAnnouncement>> _commitAnnouncements(
    List<AppAnnouncement> items,
    int revision,
  ) async {
    // 请求期间开关被关闭或状态被修改时丢弃结果，避免过期公告进入首页。
    if (!await _canRequest() || _revision.value != revision) return const [];
    final filtered = await _applyTargeting(items);
    _cachedAnnouncements = filtered;
    _announcementsFetchedAt = _clock();
    _announcementsCacheRevision = revision;
    return filtered;
  }

  Future<List<AppAnnouncement>> _applyTargeting(
    List<AppAnnouncement> items,
  ) async {
    if (items.isEmpty) return const [];
    final platform = _platformName();
    final versionCode = await _versionCodeOrUnknown();
    return [
      for (final item in items)
        if (item.targets(platform: platform, versionCode: versionCode)) item,
    ];
  }

  Future<int> _versionCodeOrUnknown() async {
    try {
      return await _appVersionCode();
    } catch (error) {
      AppLogger.warn('宿主构建号不可用，公告跳过版本定向（${error.runtimeType}）');
      return 0;
    }
  }

  void _resetAnnouncementCache() {
    _cachedAnnouncements = null;
    _announcementsFetchedAt = null;
    _announcementsCacheRevision = null;
  }

  /// 提交匿名反馈。
  ///
  /// 单次提交固定一个后端：网络中断或 5xx 时抛出
  /// [FeedbackSubmissionUnknownException]，不自动重试、不改投 Fenfa。
  /// 用户主动重试同一份草稿时复用同一幂等请求 ID，由服务端去重。
  Future<void> submitFeedback(AppFeedbackDraft draft) async {
    if (!await _canRequest()) {
      throw const AppRemoteServicesDisabledException();
    }
    final normalized = _normalizeDraft(draft);
    if (_feedbackInFlight) {
      throw const FormatException('反馈正在提交，请稍候');
    }
    _feedbackInFlight = true;
    final fingerprint = _fingerprint(normalized);
    final pending = _pendingFeedbackRequest;
    final requestId =
        pending != null && pending.fingerprint == fingerprint
            ? pending.requestId
            : _requestIdGenerator();
    _pendingFeedbackRequest = _PendingFeedbackRequest(fingerprint, requestId);
    try {
      await _feedbackRepository.submitFeedback(
        normalized,
        requestId: requestId,
      );
      _pendingFeedbackRequest = null;
    } on FeedbackSubmissionUnknownException {
      // 结果未知：保留幂等键，用户主动重试时复用。
      rethrow;
    } on PublicHttpException catch (error) {
      // 429 在服务端限流处就被拒绝，没有走到按 request_id 去重的写入，因此
      // 它不能证明上一次尝试没有入库。若此时丢弃幂等键，用户稍后重试会生成
      // 新键，把同一份反馈写第二次。
      if (error.statusCode == 429) rethrow;
      // 其余 4xx 在写入前被拒绝，可安全丢弃幂等键。
      _pendingFeedbackRequest = null;
      rethrow;
    } catch (_) {
      // 明确失败：服务端未写入，丢弃幂等键。
      _pendingFeedbackRequest = null;
      rethrow;
    } finally {
      _feedbackInFlight = false;
    }
  }

  static AppFeedbackDraft _normalizeDraft(AppFeedbackDraft draft) {
    final content = draft.content.trim();
    final contact = draft.contact.trim();
    final diagnosticLog = draft.diagnosticLog.trim();
    final normalized = AppFeedbackDraft(
      category: draft.category,
      content: content,
      contact: contact,
      diagnosticLog: diagnosticLog,
    );
    if (content.isEmpty) {
      throw const FormatException('反馈内容不能为空');
    }
    if (content.runes.length > normalized.contentLengthLimit) {
      throw const FormatException('反馈内容长度不合法');
    }
    if (diagnosticLog.runes.length > kFeedbackMaxDiagnosticLength) {
      throw const FormatException('诊断信息长度不合法');
    }
    if (contact.runes.length > kFeedbackMaxContactLength) {
      throw const FormatException('联系方式长度不合法');
    }
    return normalized;
  }

  static String _fingerprint(AppFeedbackDraft draft) => [
    draft.category.apiValue,
    draft.content,
    draft.contact,
    draft.diagnosticLog,
  ].join('\u0000');

  static String _generateRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }
}

class _PendingFeedbackRequest {
  const _PendingFeedbackRequest(this.fingerprint, this.requestId);

  final String fingerprint;
  final String requestId;
}
