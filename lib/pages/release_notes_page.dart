import 'dart:async';

import 'package:flutter/material.dart';

import '../data/release_notes.dart';
import '../models/release_notes.dart';
import '../services/app_remote_services_service.dart';
import '../services/host_version.dart';
import '../services/logging/logger.dart';
import '../services/platform_compatibility_service.dart';
import '../services/updates/app_update_service.dart';
import '../widgets/adaptive_settings.dart';
import 'app_update_dialog.dart' show showAppRemoteServicesDisabledMessage;
import 'app_update_prompts.dart';
import 'app_update_section.dart';
import 'release_history_page.dart';

/// 版本中心：版本信息、更新检查与历史更新日志。
///
/// 新特性内容随包发布，不依赖网络与「在线功能」开关；只有检查更新需要远程服务。
class ReleaseNotesPage extends StatefulWidget {
  const ReleaseNotesPage({super.key, this.updates});

  final AppUpdateService? updates;

  @override
  State<ReleaseNotesPage> createState() => _ReleaseNotesPageState();
}

class _ReleaseNotesPageState extends State<ReleaseNotesPage> {
  final GlobalKey _updateCardKey = GlobalKey();

  AppUpdateService get _updates => widget.updates ?? AppUpdateService.shared;

  String _installedVersion = '';
  int _buildNumber = 0;
  List<AppRelease>? _releases;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var installed = '';
    var buildNumber = 0;
    try {
      installed = await AppHostVersion.current;
      buildNumber = await AppHostVersion.buildNumber;
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
    }

    var releases = const <AppRelease>[];
    try {
      releases = await ReleaseNotes.load();
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
    }

    if (!mounted) return;
    setState(() {
      _installedVersion = installed;
      _buildNumber = buildNumber;
      _releases = releases;
    });
  }

  Future<void> _checkForUpdates() async {
    if (!PlatformCompatibilityService.isAndroid) return;
    if (!await AppRemoteServicesService.isEnabled()) {
      if (!mounted) return;
      showAppRemoteServicesDisabledMessage(context);
      return;
    }
    if (!mounted) return;
    // The shared update result can outlive this page. Keep mandatory prompts
    // on the root navigator even if the user leaves while checking.
    await presentAppUpdateCheck(
      Navigator.of(context, rootNavigator: true).context,
      service: _updates,
      forceRefresh: true,
      onUpdateAvailable: () async {
        // 更新卡片插入后需要先完成布局，滚动目标才有可用的渲染对象。
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final cardContext = _updateCardKey.currentContext;
        if (cardContext != null && cardContext.mounted) {
          await Scrollable.ensureVisible(
            cardContext,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      },
    );
  }

  String? _checkStateLabel() {
    switch (_updates.state) {
      case UpdateCheckState.idle:
      case UpdateCheckState.available:
        return null;
      case UpdateCheckState.checking:
        return '正在检查更新…';
      case UpdateCheckState.current:
        return '已是最新版本';
      case UpdateCheckState.unavailable:
        return '检查失败，可重试';
      case UpdateCheckState.disabled:
        return '暂时无法检查更新';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final releases = _releases;
    final release =
        releases
            ?.where((item) => item.version == _installedVersion)
            .firstOrNull;
    final version = release?.version ?? _installedVersion;
    final meta = <String>[
      if (release != null) release.date,
      if (_buildNumber > 0) '构建 $_buildNumber',
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
        actions: const [GitHubReleasesButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (releases == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _buildVersionHeader(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        version.isEmpty ? '版本未知' : 'v$version',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            meta.join(' · '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (release == null || release.sections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '本版本更新内容暂未收录',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ReleaseNoteEntries(sections: release.sections),
                ...[
                  const SizedBox(height: 12),
                  AdaptiveSettingsSection(
                    children: [
                      AdaptiveSettingsRow(
                        icon: Icons.history,
                        title: '历史更新日志',
                        onTap:
                            () => _push(ReleaseHistoryPage(releases: releases)),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionHeader(Widget versionInfo) {
    if (!PlatformCompatibilityService.isAndroid) return versionInfo;
    return ListenableBuilder(
      listenable: _updates,
      builder: (context, _) {
        if (_updates.offer != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              versionInfo,
              AppUpdateSection(
                key: _updateCardKey,
                service: _updates,
                refreshOnMount: false,
              ),
            ],
          );
        }
        final checking = _updates.state == UpdateCheckState.checking;
        final status = _checkStateLabel();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  versionInfo,
                  FilledButton.tonalIcon(
                    onPressed: checking ? null : _checkForUpdates,
                    icon:
                        checking
                            ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.refresh, size: 18),
                    label: const Text('检查更新'),
                  ),
                ],
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _push(Widget page) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}
