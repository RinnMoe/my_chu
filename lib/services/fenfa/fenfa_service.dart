import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../capabilities/app_installer/app_installer.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../app_remote_services_service.dart';
import '../host_version.dart';
import '../logger_service.dart';
import 'fenfa_client.dart';
import 'fenfa_models.dart';

const _flutterSplitAbiBuildPrefixes = <int>{1, 2, 3, 4};

typedef FenfaUpdateDownloader =
    Future<InAppDownloadedFile> Function(
      FenfaRelease release,
      ValueChanged<InAppDownloadProgress>? onProgress,
    );
typedef FenfaUpdateInstaller = Future<bool> Function(InAppDownloadedFile file);

const _fenfaDiagnosticHeader = '\n\n--- MyCHU 脱敏诊断日志 ---\n';

String composeFenfaFeedbackContent({
  required String content,
  required String diagnosticLog,
}) {
  final trimmedContent = content.trim();
  final trimmedDiagnostics = diagnosticLog.trim();
  if (trimmedDiagnostics.isEmpty) return trimmedContent;
  return '$trimmedContent$_fenfaDiagnosticHeader$trimmedDiagnostics';
}

/// Converts a Flutter split-per-ABI version code to the logical Fenfa build.
///
/// Flutter encodes ABI-specific Android version codes with a 1xxx/2xxx/3xxx/
/// 4xxx prefix, while Fenfa may publish the base build number (for example,
/// `5`). Builds outside that encoding remain unchanged.
int normalizeFenfaBuild(int build) {
  if (build < 1000 || build >= 5000) return build;
  final prefix = build ~/ 1000;
  return _flutterSplitAbiBuildPrefixes.contains(prefix) ? build % 1000 : build;
}

/// 版本检查结果。
enum FenfaCheckOutcome {
  /// 有新版本且为强制更新。
  forceUpdate,

  /// 有新版本，普通更新。
  normalUpdate,

  /// 无新版本（或本地 build 未知 / 自动检查被“稍后”抑制）。
  none,

  /// Fenfa 不可达或响应异常；本次检查失败，静默降级。
  unavailable,

  /// MyCHU 托管的远程服务已关闭。
  disabled,
}

class FenfaCheckResult {
  final FenfaCheckOutcome outcome;
  final FenfaRelease? release;

  const FenfaCheckResult(this.outcome, [this.release]);
}

/// Fenfa 更新/公告策略：版本比较、稍后策略、公告去重、单飞。
///
/// 只处理决策与本地状态，不持有 BuildContext；弹窗与编排见
/// `lib/pages/fenfa_dialogs.dart`。
class FenfaService {
  FenfaService({
    FenfaClient? client,
    Future<int> Function()? localBuild,
    FenfaUpdateDownloader? updateDownloader,
    FenfaUpdateInstaller? updateInstaller,
  }) : _client = client ?? FenfaClient(),
       _localBuild = localBuild ?? (() => AppHostVersion.buildNumber),
       _updateDownloader = updateDownloader,
       _updateInstaller = updateInstaller;

  /// 进程内共享实例：启动检查与手动检查共用，保证单飞与状态一致。
  static final FenfaService shared = FenfaService();

  static const _dismissedBuildKey = 'fenfa.v1.dismissed_build';
  static const _announcementsTtl = Duration(minutes: 5);

  final FenfaClient _client;
  final Future<int> Function() _localBuild;
  final FenfaUpdateDownloader? _updateDownloader;
  final FenfaUpdateInstaller? _updateInstaller;

  /// 单飞：同一时刻只发一次 latest 请求，更新检查和反馈上下文共享请求。
  Future<FenfaLatestSnapshot>? _inFlightLatest;
  Future<List<FenfaAnnouncement>>? _inFlightAnnouncements;
  int? _inFlightAnnouncementsRevision;
  List<FenfaAnnouncement>? _cachedAnnouncements;
  DateTime? _announcementsFetchedAt;
  int? _announcementsCacheRevision;

  /// 检查更新。[manual] 为 true 时绕过“稍后”抑制（手动检查）。
  Future<FenfaCheckResult> checkForUpdate({required bool manual}) async {
    if (!await AppRemoteServicesService.isEnabled()) {
      return const FenfaCheckResult(FenfaCheckOutcome.disabled);
    }
    final FenfaRelease? release;
    try {
      release = (await _latestSnapshot()).release;
    } on AppRemoteServicesDisabledException {
      return const FenfaCheckResult(FenfaCheckOutcome.disabled);
    } catch (error) {
      AppLogger.warn('Fenfa 版本检查失败（已降级，不影响启动）(${error.runtimeType})');
      return const FenfaCheckResult(FenfaCheckOutcome.unavailable);
    }
    if (release == null) {
      return const FenfaCheckResult(FenfaCheckOutcome.none);
    }
    final rawLocalBuild = await _localBuild();
    final localBuild = normalizeFenfaBuild(rawLocalBuild);
    if (localBuild <= 0) {
      AppLogger.warn(
        '本地 buildNumber 不可用（$rawLocalBuild，归一化后 $localBuild），跳过 Fenfa 更新提示',
      );
      return const FenfaCheckResult(FenfaCheckOutcome.none);
    }
    final remoteBuild = normalizeFenfaBuild(release.build);
    if (remoteBuild <= localBuild) {
      return const FenfaCheckResult(FenfaCheckOutcome.none);
    }
    if (!manual && await _isDismissed(remoteBuild)) {
      // “稍后”策略：自动检查在手动检查或更高版本出现前不再提醒。
      return const FenfaCheckResult(FenfaCheckOutcome.none);
    }
    return FenfaCheckResult(
      release.forceUpdate
          ? FenfaCheckOutcome.forceUpdate
          : FenfaCheckOutcome.normalUpdate,
      release,
    );
  }

  /// 记录普通更新的“稍后”：该 build 在手动检查或更高版本出现前不再自动提醒。
  Future<void> rememberLater(int build) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedBuildKey, normalizeFenfaBuild(build));
  }

  /// 首页 Focus 使用当前公告；短时缓存避免其他 Focus 来源刷新时重复请求。
  Future<List<FenfaAnnouncement>> loadFocusAnnouncements({
    bool force = false,
  }) async {
    final revision = AppRemoteServicesService.revision.value;
    if (!await AppRemoteServicesService.isEnabled()) {
      _cachedAnnouncements = null;
      _announcementsFetchedAt = null;
      return const [];
    }
    final fetchedAt = _announcementsFetchedAt;
    final cached = _cachedAnnouncements;
    if (!force &&
        _announcementsCacheRevision == revision &&
        cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _announcementsTtl) {
      return cached;
    }
    final running = _inFlightAnnouncements;
    if (running != null && _inFlightAnnouncementsRevision == revision) {
      return running;
    }
    final future = _fetchFocusAnnouncements(revision);
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

  Future<List<FenfaAnnouncement>> _fetchFocusAnnouncements(int revision) async {
    try {
      await _requireRemoteServicesEnabled();
      final items = await _client.fetchAnnouncements();
      if (!await AppRemoteServicesService.isEnabled() ||
          AppRemoteServicesService.revision.value != revision) {
        return const [];
      }
      _cachedAnnouncements = items;
      _announcementsFetchedAt = DateTime.now();
      _announcementsCacheRevision = revision;
      return items;
    } on AppRemoteServicesDisabledException {
      return const [];
    } catch (error) {
      AppLogger.warn('Fenfa 焦点公告加载失败（已降级）(${error.runtimeType})');
      return const [];
    }
  }

  /// 提交匿名反馈；产品/变体/版本上下文来自 Fenfa latest 接口。
  Future<void> submitFeedback(FenfaFeedbackDraft draft) async {
    await _requireRemoteServicesEnabled();
    final content = draft.content.trim();
    final contact = draft.contact.trim();
    final diagnosticLog = draft.diagnosticLog.trim();
    if (content.isEmpty ||
        (diagnosticLog.isEmpty &&
            content.runes.length > kFenfaFeedbackMaxContentLength) ||
        (diagnosticLog.isNotEmpty &&
            (content.runes.length >
                    kFenfaFeedbackWithDiagnosticsMaxContentLength ||
                diagnosticLog.runes.length >
                    kFenfaFeedbackMaxDiagnosticLength)) ||
        contact.runes.length > kFenfaFeedbackMaxContactLength) {
      throw const FormatException('反馈内容或联系方式长度不合法');
    }
    final submittedContent = composeFenfaFeedbackContent(
      content: content,
      diagnosticLog: diagnosticLog,
    );
    if (submittedContent.runes.length > kFenfaFeedbackMaxContentLength) {
      throw const FormatException('反馈内容或诊断日志长度不合法');
    }

    final snapshot = await _latestSnapshot();
    final productId = snapshot.productId;
    if (productId == null) {
      throw const FormatException('Fenfa 产品上下文不可用');
    }
    await _requireRemoteServicesEnabled();
    await _client.submitFeedback(
      productId: productId,
      variantId: snapshot.variantId ?? '',
      releaseId: snapshot.release?.id ?? '',
      draft: FenfaFeedbackDraft(
        category: draft.category,
        content: submittedContent,
        contact: contact,
      ),
    );
  }

  /// 在应用内下载更新安装包，随后交给 Android 系统安装程序。
  Future<bool> downloadAndInstall(
    FenfaRelease release, {
    ValueChanged<InAppDownloadProgress>? onProgress,
  }) async {
    await _requireRemoteServicesEnabled();
    final uri = Uri.tryParse(release.downloadUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      AppLogger.warn('Fenfa download_url 非法，已拒绝下载');
      throw const InAppDownloadException(InAppDownloadErrorType.invalidUrl);
    }

    final downloaded =
        _updateDownloader != null
            ? await _updateDownloader(release, onProgress)
            : await const InAppDownloadCapability().download(
              url: uri,
              fileName: 'MyCHU-${release.version}-${release.build}.apk',
              followRedirects: true,
              onProgress: onProgress,
            );
    return _updateInstaller != null
        ? _updateInstaller(downloaded)
        : AppInstallerCapability().install(downloaded);
  }

  Future<FenfaLatestSnapshot> _latestSnapshot() async {
    await _requireRemoteServicesEnabled();
    final inFlight = _inFlightLatest;
    if (inFlight != null) return inFlight;
    final future = _client.fetchLatestSnapshot();
    _inFlightLatest = future;
    future.whenComplete(() {
      if (identical(_inFlightLatest, future)) _inFlightLatest = null;
    }).ignore();
    return future;
  }

  Future<void> _requireRemoteServicesEnabled() async {
    if (!await AppRemoteServicesService.isEnabled()) {
      throw const AppRemoteServicesDisabledException();
    }
  }

  Future<bool> _isDismissed(int build) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getInt(_dismissedBuildKey);
    return dismissed != null && dismissed >= normalizeFenfaBuild(build);
  }
}
