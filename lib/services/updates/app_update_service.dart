import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../capabilities/app_installer/app_installer.dart';
import '../../capabilities/app_update/app_update_coordinator.dart';
import '../../capabilities/app_update/app_update_manifest.dart';
import '../../capabilities/in_app_download/in_app_download.dart';
import '../app_remote_services_service.dart';
import '../fenfa/fenfa_service.dart';
import '../host_version.dart';
import '../platform_compatibility_service.dart';
import '../privacy_agreement_service.dart';
import 'update_offer.dart';
import 'upgradelink_client.dart';

enum UpdateCheckState {
  idle,
  checking,
  available,
  current,
  unavailable,
  disabled,
}

/// Shared, account-free state for startup, About and the Profile update section.
/// Fenfa announcements/feedback and its public update API remain independent.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    UpgradeLinkClient? upgradeLink,
    FenfaService? fenfa,
    AppUpdateCoordinator? coordinator,
    Future<int> Function()? localBuild,
    Future<String> Function()? localVersion,
    Future<String> Function()? packageName,
    Future<bool> Function()? isAllowed,
    bool Function()? isSupported,
    Future<bool> Function(InAppDownloadedFile)? install,
    bool observePolicy = true,
  }) : _upgradeLink = upgradeLink ?? UpgradeLinkClient(),
       _fenfa = fenfa ?? FenfaService.shared,
       _coordinator = coordinator ?? AppUpdateCoordinator(),
       _localBuild = localBuild ?? (() => AppHostVersion.buildNumber),
       _localVersion = localVersion ?? (() => AppHostVersion.current),
       _packageName =
           packageName ??
           (() async => (await PackageInfo.fromPlatform()).packageName),
       _allowed =
           isAllowed ??
           (() async =>
               await PrivacyAgreementService.isAccepted() &&
               await AppRemoteServicesService.isEnabled()),
       _supported =
           isSupported ?? (() => PlatformCompatibilityService.isAndroid),
       _install = install ?? AppInstallerCapability().install,
       _observePolicy = observePolicy {
    if (_observePolicy) {
      AppRemoteServicesService.revision.addListener(_policyChanged);
      PrivacyAgreementService.revision.addListener(_policyChanged);
    }
  }

  static final shared = AppUpdateService();
  final UpgradeLinkClient _upgradeLink;
  final FenfaService _fenfa;
  final AppUpdateCoordinator _coordinator;
  final Future<int> Function() _localBuild;
  final Future<String> Function() _localVersion;
  final Future<String> Function() _packageName;
  final Future<bool> Function() _allowed;
  final bool Function() _supported;
  final Future<bool> Function(InAppDownloadedFile) _install;
  final bool _observePolicy;
  bool _disposed = false;
  int _epoch = 0;
  Future<void>? _checking;
  Future<void>? _planning;
  DateTime? _checkedAt;

  UpdateCheckState state = UpdateCheckState.idle;
  UpdateOffer? offer;
  AppUpdatePatch? delta;
  String localVersion = '';
  int localVersionCode = 0;
  bool planning = false;
  bool downloading = false;
  bool installerOpened = false;
  InAppDownloadProgress? progress;
  String? error;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _policyChanged() {
    _epoch++;
    _checkedAt = null;
    _checking = null;
    offer = null;
    delta = null;
    planning = false;
    error = null;
    state = UpdateCheckState.disabled;
    _emit();
  }

  Future<void> refresh({bool force = false}) {
    if (_disposed || downloading) return Future<void>.value();
    final running = _checking;
    if (running != null) return running;
    final checked = _checkedAt;
    if (!force &&
        checked != null &&
        DateTime.now().difference(checked) < const Duration(minutes: 5)) {
      return Future<void>.value();
    }
    late final Future<void> task;
    task = _refresh(_epoch).whenComplete(() {
      if (identical(_checking, task)) _checking = null;
    });
    _checking = task;
    return task;
  }

  Future<bool> _current(int epoch) async {
    if (_disposed || epoch != _epoch) return false;
    final allowed = await _allowed();
    return allowed && !_disposed && epoch == _epoch;
  }

  Future<void> _refresh(int epoch) async {
    try {
      if (!_supported() || !await _current(epoch)) {
        // An older policy read must not clear a newer refresh's result.
        if (_disposed || epoch != _epoch) return;
        state = UpdateCheckState.disabled;
        offer = null;
        delta = null;
        _emit();
        return;
      }
      state = UpdateCheckState.checking;
      error = null;
      _emit();
      final code = await _localBuild();
      final version = await _localVersion();
      if (code <= 0) throw const FormatException('Local version unavailable');
      if (!await _current(epoch)) return;
      localVersionCode = code;
      localVersion = version;
      UpdateOffer? result;
      var useFenfa = !_upgradeLink.config.isConfigured;
      if (!useFenfa) {
        try {
          final name = await _packageName();
          if (!await _current(epoch)) return;
          result = await _upgradeLink.check(
            versionCode: code,
            packageName: name,
          );
        } catch (_) {
          // Only an unavailable/invalid source falls back. "No update" is
          // authoritative and must not resurrect a release from another source.
          useFenfa = true;
        }
      }
      if (!await _current(epoch)) return;
      if (useFenfa) {
        final legacy = await _fenfa.checkForUpdate(manual: true);
        if (!await _current(epoch)) return;
        if (legacy.outcome == FenfaCheckOutcome.unavailable) {
          throw const FormatException('Update sources unavailable');
        }
        if (legacy.release != null &&
            {
              FenfaCheckOutcome.normalUpdate,
              FenfaCheckOutcome.forceUpdate,
            }.contains(legacy.outcome)) {
          result = UpdateOffer.fromFenfa(legacy.release!);
        }
      }
      if (!await _current(epoch)) return;
      offer = result;
      delta = null;
      planning = false;
      installerOpened = false;
      progress = null;
      _checkedAt = DateTime.now();
      state =
          result == null
              ? UpdateCheckState.current
              : UpdateCheckState.available;
      if (result != null) {
        planning = true;
        _planning = (_planning ?? Future<void>.value()).then(
          (_) => _plan(result!, epoch),
        );
      }
      _emit();
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      offer = null;
      delta = null;
      state = UpdateCheckState.unavailable;
      _emit();
    }
  }

  Future<void> _plan(UpdateOffer candidate, int epoch) async {
    try {
      if (!await _current(epoch) || !identical(offer, candidate)) return;
      final match = await _coordinator.matchingPatch(candidate.package);
      if (!await _current(epoch) || !identical(offer, candidate)) return;
      delta = match;
    } catch (_) {
      // Metadata/preflight failure leaves the verified full route available.
    } finally {
      if (!_disposed && epoch == _epoch && identical(offer, candidate)) {
        planning = false;
        _emit();
      }
    }
  }

  Future<bool> download({
    required bool preferDelta,
    ValueChanged<InAppDownloadProgress>? onProgress,
  }) async {
    if (downloading || offer == null) return false;
    final selected = offer!;
    final epoch = _epoch;
    downloading = true;
    installerOpened = false;
    error = null;
    progress = null;
    _emit();
    try {
      await _planning;
      if (!await _current(epoch) || !identical(offer, selected)) {
        throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
      }
      void report(InAppDownloadProgress item) {
        if (_disposed || epoch != _epoch) {
          throw const InAppDownloadException(InAppDownloadErrorType.cancelled);
        }
        progress = item;
        _emit();
        onProgress?.call(item);
      }

      final bool opened;
      if (selected.provider == UpdateProvider.fenfa) {
        opened = await _fenfa.downloadAndInstall(
          selected.fenfaRelease!,
          preferDelta: preferDelta,
          onProgress: report,
        );
      } else {
        opened =
            await _coordinator.tryUpdatePackage(
              selected.package,
              install: _install,
              preferDelta: preferDelta,
              onProgress: report,
            ) ??
            false;
      }
      if (!_disposed && epoch == _epoch) {
        installerOpened = opened;
        if (!opened) error = '无法打开安装程序，请重试';
      }
      return opened;
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = '更新未完成，请检查网络或可用空间后重试';
      return false;
    } finally {
      downloading = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (_observePolicy) {
      AppRemoteServicesService.revision.removeListener(_policyChanged);
      PrivacyAgreementService.revision.removeListener(_policyChanged);
    }
    super.dispose();
  }
}
