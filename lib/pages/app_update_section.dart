import 'dart:async';

import 'package:flutter/material.dart';

import '../services/updates/app_update_service.dart';
import 'app_update_prompts.dart';

String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Appears above Profile's account group only while a newer release is known.
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
      final delta = service.delta;
      final downloading = service.downloading;
      final fraction = service.progress?.fraction;
      final foreground = colors.onPrimaryContainer;
      // Sizes live on the actions, not in the body: the primary reports the bytes
      // this update actually transfers, the folded action reports the full package.
      final downloadSize = delta?.patchSize ?? update.sizeBytes;
      final fullSize = delta?.targetSize ?? update.sizeBytes;
      // After a failed patch the same operation continues with the full package;
      // say so instead of hiding the extra download behind the patch size.
      final onFullFallback =
          downloading && delta != null && service.downloadingFullPackage;
      final actionLabel =
          downloading
              ? (fraction == null
                  ? '下载中…'
                  : onFullFallback
                  ? '下载完整更新 ${(fraction * 100).floor()}%'
                  : '下载中 ${(fraction * 100).floor()}%')
              : (downloadSize == null
                  ? '下载更新'
                  : '下载更新（${_size(downloadSize)}）');
      final fullLabel =
          fullSize == null ? '下载完整更新' : '下载完整更新（${_size(fullSize)}）';
      // One entry point: the delta is preferred internally and falls back to the
      // full package by itself, so the user never chooses a download strategy.
      final sizeLine = '$currentVersion → $targetVersion';
      final hasDetails = update.notes.trim().isNotEmpty || delta != null;
      return Padding(
        key: const ValueKey('profile-update-section'),
        padding: const EdgeInsets.only(top: 24),
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
            Card(
              margin: const EdgeInsets.only(top: 8),
              color: colors.primaryContainer,
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
                          child: Icon(Icons.arrow_upward, color: foreground),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                update.force ? '发现新版本 · 需要更新' : '发现新版本',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: foreground,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                sizeLine,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasDetails)
                          IconButton(
                            tooltip: _expanded ? '收起' : '更多选项',
                            isSelected: _expanded,
                            onPressed:
                                () => setState(() => _expanded = !_expanded),
                            icon: const Icon(Icons.notes_outlined),
                            color: foreground,
                          ),
                      ],
                    ),
                  ),
                  if (_expanded && hasDetails)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (update.notes.trim().isNotEmpty)
                            SelectableText(
                              update.notes,
                              style: TextStyle(color: foreground),
                            ),
                          if (delta != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const ValueKey('update-download-full'),
                                onPressed:
                                    busy
                                        ? null
                                        : () => unawaited(
                                          service.download(preferDelta: false),
                                        ),
                                style: TextButton.styleFrom(
                                  foregroundColor: foreground,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(fullLabel),
                              ),
                            ),
                        ],
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('update-download'),
                    onPressed:
                        busy
                            ? null
                            : () =>
                                unawaited(service.download(preferDelta: true)),
                    style: TextButton.styleFrom(
                      foregroundColor: foreground,
                      backgroundColor: foreground.withValues(alpha: 0.07),
                      shape: const RoundedRectangleBorder(),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Semantics(
                      liveRegion: downloading,
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ),
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
