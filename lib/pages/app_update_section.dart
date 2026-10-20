import 'dart:async';

import 'package:flutter/material.dart';

import '../services/updates/app_update_service.dart';
import 'app_update_prompts.dart';
import 'app_update_progress.dart';

String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Appears after Profile's About group only while a newer release is known.
class AppUpdateSection extends StatefulWidget {
  const AppUpdateSection({super.key, this.service, this.refreshOnMount = true});
  final AppUpdateService? service;
  final bool refreshOnMount;
  @override
  State<AppUpdateSection> createState() => _AppUpdateSectionState();
}

class _AppUpdateSectionState extends State<AppUpdateSection> {
  bool _expanded = false;
  AppUpdateService get service => widget.service ?? AppUpdateService.shared;
  @override
  void initState() {
    super.initState();
    if (widget.refreshOnMount) {
      unawaited(presentAppUpdateCheck(context, service: service));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final update = service.offer;
      if (update == null) return const SizedBox.shrink();
      final sameVersion = service.localVersion == update.package.version;
      final currentVersion =
          '${service.localVersion}${sameVersion ? '+${service.localVersionCode}' : ''}';
      final targetVersion =
          '${update.package.version}${sameVersion ? '+${update.package.versionCode}' : ''}';
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final busy =
          service.downloading ||
          service.planning ||
          service.state == UpdateCheckState.checking;
      Widget card({required bool incremental}) {
        final patch = service.delta;
        final background =
            incremental ? colors.tertiaryContainer : colors.primaryContainer;
        final foreground =
            incremental
                ? colors.onTertiaryContainer
                : colors.onPrimaryContainer;
        return Card(
          margin: const EdgeInsets.only(top: 8),
          color: background,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 12),
                      child: Icon(
                        incremental
                            ? Icons.inventory_2_outlined
                            : Icons.arrow_upward,
                        color: foreground,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            incremental
                                ? '增量更新'
                                : (update.force ? '发现新版本 · 必须更新' : '发现新版本'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: foreground,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            incremental
                                ? '下载 ${_size(patch!.size)} 补丁，合成后安装完整新版本。失败时将改用完整包。'
                                : '$currentVersion → $targetVersion${update.sizeBytes == null ? '' : ' · ${_size(update.sizeBytes!)}'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!incremental && update.notes.trim().isNotEmpty)
                      IconButton(
                        tooltip: _expanded ? '收起更新说明' : '查看更新说明',
                        isSelected: _expanded,
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: const Icon(Icons.notes_outlined),
                        color: foreground,
                      ),
                  ],
                ),
              ),
              if (!incremental && _expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SelectableText(
                    update.notes,
                    style: TextStyle(color: foreground),
                  ),
                ),
              TextButton(
                key: ValueKey(
                  incremental
                      ? 'update-delta-download'
                      : 'update-full-download',
                ),
                onPressed:
                    busy
                        ? null
                        : () => unawaited(
                          service.download(preferDelta: incremental),
                        ),
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  backgroundColor: foreground.withValues(alpha: 0.07),
                  shape: const RoundedRectangleBorder(),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(incremental ? '增量更新' : '下载更新'),
              ),
            ],
          ),
        );
      }

      return Padding(
        key: const ValueKey('profile-update-section'),
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '更新版本',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            card(incremental: false),
            if (service.delta != null) card(incremental: true),
            if (service.planning)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('正在检查是否有适用的增量包…'),
              ),
            if (service.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: service.progress?.fraction),
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(updateProgressLabel(service.progress)),
              ),
            ],
            if (service.installerOpened)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('安装程序已打开，请在系统界面完成更新'),
              ),
            if (service.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    service.error!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
