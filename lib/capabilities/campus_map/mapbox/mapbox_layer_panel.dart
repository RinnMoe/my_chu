import "package:flutter/material.dart";

import "../layers/layers.dart";

/// 通用的地图图层面板。
///
/// 内容完全由 [MapLayerManager] 根据 [MapLayerRegistry] 生成：不包含任何
/// 具体业务图层的硬编码菜单。图层未注册或对当前校区不适用时不会出现。
class MapLayerSheet extends StatelessWidget {
  const MapLayerSheet({
    super.key,
    required this.manager,
    required this.onToggle,
    required this.onRetry,
    this.onRefresh,
  });

  final MapLayerManager manager;
  final Future<void> Function(String layerId, bool visible) onToggle;
  final Future<void> Function(String layerId) onRetry;
  final Future<void> Function(String layerId)? onRefresh;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final entries = manager.entries;
        final theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "地图图层",
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: "关闭",
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Text(
                      "当前校区暂无可用图层",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final entry in entries)
                          _MapLayerTile(
                            entry: entry,
                            onToggle:
                                (visible) => onToggle(entry.layerId, visible),
                            onRetry: () => onRetry(entry.layerId),
                            onRefresh:
                                onRefresh == null
                                    ? null
                                    : () => onRefresh!(entry.layerId),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapLayerTile extends StatelessWidget {
  const _MapLayerTile({
    required this.entry,
    required this.onToggle,
    required this.onRetry,
    this.onRefresh,
  });

  final MapLayerEntry entry;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRetry;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definition = entry.definition;
    final error = entry.errorMessage;
    final subtitle =
        entry.hasError
            ? error ?? "加载失败，点按重试"
            : entry.isLoading
            ? "正在加载"
            : definition.description;
    return ListTile(
      leading: Icon(definition.icon),
      title: Text(definition.name),
      subtitle:
          subtitle == null
              ? null
              : Text(
                subtitle,
                style:
                    entry.hasError
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
              ),
      onTap: entry.hasError ? onRetry : () => onToggle(!entry.visible),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRefresh != null && entry.visible && !entry.isLoading)
            IconButton(
              tooltip: "刷新图层",
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          Switch(value: entry.visible, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// 通用要素详情卡。
///
/// 业务可以提供 [MapLayerInteraction.detailBuilder] 展示自己的详情；未提供时
/// 使用本卡片（标题、副标题与“打开应用”入口）。卡片与 Mapbox 完全解耦。
class MapLayerFeatureCard extends StatelessWidget {
  const MapLayerFeatureCard({
    super.key,
    required this.selection,
    required this.onClose,
    this.onOpenOwnerApp,
    this.busy = false,
  });

  final MapLayerFeatureSelection selection;
  final VoidCallback onClose;
  final Future<void> Function()? onOpenOwnerApp;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interaction = selection.definition.interaction;
    final custom = interaction.detailBuilder?.call(context, selection);
    if (custom != null) {
      return Stack(
        children: [
          custom,
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: "关闭",
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      );
    }
    final feature = selection.feature;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(selection.definition.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    feature.label ?? selection.definition.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (feature.subtitle?.isNotEmpty == true)
                    Text(
                      feature.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onOpenOwnerApp != null)
              IconButton(
                tooltip: "在${selection.definition.name}中打开",
                onPressed: busy ? null : () => onOpenOwnerApp!(),
                icon:
                    busy
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.open_in_new),
              ),
            IconButton(
              tooltip: "关闭要素信息",
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
