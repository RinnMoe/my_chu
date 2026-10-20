import 'package:flutter/foundation.dart';

import '../../capabilities/app_installer/app_installer.dart';
import '../../capabilities/app_update/app_update_coordinator.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../app_remote_services_service.dart';
import '../host_version.dart';
import '../logger_service.dart';
import '../privacy_agreement_service.dart';
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
    AppUpdateCoordinator? updateCoordinator,
  }) : _client = client ?? FenfaClient(),
       _localBuild = localBuild ?? (() => AppHostVersion.buildNumber),
       _updateDownloader = updateDownloader,
       _updateInstaller = updateInstaller,
       _updateCoordinator = updateCoordinator ?? AppUpdateCoordinator();

  /// 进程内共享实例：启动检查与手动检查共用，保证单飞与状态一致。
  static final FenfaService shared = FenfaService();
  static bool _updateRunning = false;

  static const _announcementsTtl = Duration(minutes: 5);

  final FenfaClient _client;
  final Future<int> Function() _localBuild;
  final FenfaUpdateDownloader? _updateDownloader;
  final FenfaUpdateInstaller? _updateInstaller;
  final AppUpdateCoordinator _updateCoordinator;

  /// 单飞：同一时刻只发一次 latest 请求，更新检查和反馈上下文共享请求。
  Future<FenfaLatestSnapshot>? _inFlightLatest;
  Future<List<FenfaAnnouncement>>? _inFlightAnnouncements;
  int? _inFlightAnnouncementsRevision;
  List<FenfaAnnouncement>? _cachedAnnouncements;
  DateTime? _announcementsFetchedAt;
  int? _announcementsCacheRevision;

  /// 检查更新；启动/手动入口均已收敛到同一版本比较逻辑。
  Future<FenfaCheckResult> checkForUpdate() async {
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
    return FenfaCheckResult(
      release.forceUpdate
          ? FenfaCheckOutcome.forceUpdate
          : FenfaCheckOutcome.normalUpdate,
      release,
    );
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
    bool preferDelta = true,
  }) async {
    if (_updateRunning) {
      throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
    }
    _updateRunning = true;
    try {
      return await _downloadAndInstall(
        release,
        onProgress: onProgress,
        preferDelta: preferDelta,
      );
    } finally {
      _updateRunning = false;
    }
  }

  Future<bool> _downloadAndInstall(
    FenfaRelease release, {
    ValueChanged<InAppDownloadProgress>? onProgress,
    required bool preferDelta,
  }) async {
    await _requireUpdateAllowed();
    final remoteRevision = AppRemoteServicesService.revision.value;
    final privacyRevision = PrivacyAgreementService.revision.value;
    void report(InAppDownloadProgress progress) {
      if (remoteRevision != AppRemoteServicesService.revision.value ||
          privacyRevision != PrivacyAgreementService.revision.value) {
        throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
      }
      onProgress?.call(progress);
    }

    final uri = Uri.tryParse(release.downloadUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      AppLogger.warn('Fenfa download_url 非法，已拒绝下载');
      throw const InAppDownloadException(InAppDownloadErrorType.invalidUrl);
    }

    if (_updateDownloader == null) {
      final result = await _updateCoordinator.tryUpdate(
        release,
        targetVersionCode: 2000 + normalizeFenfaBuild(release.build),
        install: _updateInstaller ?? AppInstallerCapability().install,
        onProgress: report,
        preferDelta: preferDelta,
      );
      if (result != null) return result;
    }
    await _requireUpdateAllowed();
    final downloaded =
        _updateDownloader != null
            ? await _updateDownloader(release, report)
            : await const InAppDownloadCapability().download(
              url: uri,
              fileName: 'MyCHU-${release.version}-${release.build}.apk',
              followRedirects: true,
              onProgress: report,
            );
    await _requireUpdateAllowed();
    report(
      const InAppDownloadProgress(
        receivedBytes: 0,
        totalBytes: null,
        attempt: 1,
        phase: AppUpdatePhase.installing,
      ),
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

  Future<void> _requireUpdateAllowed() async {
    await _requireRemoteServicesEnabled();
    if (!await PrivacyAgreementService.isAccepted()) {
      throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
    }
  }
}
