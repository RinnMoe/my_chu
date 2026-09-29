import 'package:flutter/material.dart';

import '../apps/app.dart';
import '../apps/app_service.dart';
import '../capabilities/dev_visibility.dart';
import '../services/home_layout_service.dart';

/// 打开常用应用编辑器。首页与页面管理共用同一实现。
Future<void> showQuickAppsEditorSheet(
  BuildContext context, {
  required String accountKey,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => QuickAppsEditorSheet(accountKey: accountKey),
  );
}

class QuickAppsEditorSheet extends StatefulWidget {
  final String accountKey;

  const QuickAppsEditorSheet({super.key, required this.accountKey});

  @override
  State<QuickAppsEditorSheet> createState() => _QuickAppsEditorSheetState();
}

class _QuickAppsEditorSheetState extends State<QuickAppsEditorSheet> {
  static const _maxQuickApps = 8;

  QuickAppsConfig _config = const QuickAppsConfig();
  List<AppDefinition> _available = const [];
  List<String> _recentIds = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final projection = await AppService.loadQuickAppsProjection(
      widget.accountKey,
    );
    if (!mounted) return;
    setState(() {
      _config = projection.config;
      _available = projection.candidates;
      _recentIds = projection.recentIds;
      _loading = false;
    });
  }

  List<AppDefinition> get _selected {
    return AppService.orderQuickApps(
      _available,
      _recentIds,
      _config,
      limit: _maxQuickApps,
    );
  }

  List<AppDefinition> get _addable {
    final selectedIds = _config.selectedAppIds.toSet();
    return [
      for (final plugin in _available)
        if (!selectedIds.contains(plugin.metadata.id)) plugin,
    ];
  }

  bool get _atLimit => _selected.length >= _maxQuickApps;

  Future<void> _add(AppDefinition plugin) async {
    await HomeLayoutService.addQuickApp(widget.accountKey, plugin.metadata.id);
    await _refresh();
  }

  Future<void> _remove(AppDefinition plugin) async {
    await HomeLayoutService.removeQuickApp(
      widget.accountKey,
      plugin.metadata.id,
    );
    await _refresh();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final ids = [for (final plugin in _selected) plugin.metadata.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    await HomeLayoutService.setQuickAppsOrder(widget.accountKey, ids);
    await _refresh();
  }

  void _reorderLegacy(int oldIndex, int newIndex) {
    // Flutter OH 3.41 exposes the original callback semantics. The callback
    // reports the insertion slot before the dragged item is removed, whereas
    // the newer onReorderItem API reports the final list index.
    final adjustedIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    _reorder(oldIndex, adjustedIndex);
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final addable = _addable;
    final manual = _config.sortMode == QuickAppsSortMode.manual;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      minChildSize: 0.50,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '编辑常用功能',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                child: Text(
                  manual ? '最多显示 8 个，可拖动排序' : '最多显示 8 个，按最近使用排序',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Row(
                  children: [
                    Text(
                      '当前常用功能',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${selected.length} / $_maxQuickApps',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (selected.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text('暂无常用功能'),
                ),
              )
            else if (manual)
              SliverReorderableList(
                itemCount: selected.length,
                // Flutter OH 3.41 does not expose onReorderItem yet.
                // ignore: deprecated_member_use
                onReorder: _reorderLegacy,
                itemBuilder: (context, index) {
                  final plugin = selected[index];
                  return ReorderableDragStartListener(
                    key: ValueKey('quick-${plugin.metadata.id}'),
                    index: index,
                    child: _CurrentAppRow(
                      plugin: plugin,
                      onRemove: () => _remove(plugin),
                    ),
                  );
                },
              )
            else
              SliverList.list(
                children: [
                  for (final plugin in selected)
                    _CurrentAppRow(
                      plugin: plugin,
                      onRemove: () => _remove(plugin),
                    ),
                ],
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  '可添加功能',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_atLimit)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  child: Text(
                    '已达到首页显示上限',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            SliverList.list(
              children: [
                for (final plugin in addable)
                  _AddableAppRow(
                    plugin: plugin,
                    enabled: !_atLimit,
                    onAdd: () => _add(plugin),
                  ),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

class _CurrentAppRow extends StatelessWidget {
  final AppDefinition plugin;
  final VoidCallback onRemove;

  const _CurrentAppRow({required this.plugin, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final metadata = plugin.metadata;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
      child: Row(
        children: [
          Icon(Icons.drag_handle, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              metadata.icon,
              size: 20,
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    metadata.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (metadata.requiresDev) ...[
                  const SizedBox(width: 8),
                  const DevBadge(),
                ],
              ],
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('移除')),
        ],
      ),
    );
  }
}

class _AddableAppRow extends StatelessWidget {
  final AppDefinition plugin;
  final bool enabled;
  final VoidCallback onAdd;

  const _AddableAppRow({
    required this.plugin,
    required this.enabled,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final metadata = plugin.metadata;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 12, 2),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              metadata.icon,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        metadata.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (metadata.requiresDev) ...[
                      const SizedBox(width: 8),
                      const DevBadge(),
                    ],
                  ],
                ),
                if (metadata.description.isNotEmpty)
                  Text(
                    metadata.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

/// 排序方式选择：手动排序或最近使用，点击后即时保存。
Future<void> showQuickAppsSortModeSheet(
  BuildContext context, {
  required String accountKey,
}) async {
  final config = await AppService.getQuickAppsConfig(accountKey);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '排序方式',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _SortModeTile(
              title: '手动排序',
              subtitle: '按你设置的顺序显示',
              selected: config.sortMode == QuickAppsSortMode.manual,
              onTap: () async {
                await HomeLayoutService.setQuickAppsSortMode(
                  accountKey,
                  QuickAppsSortMode.manual,
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            _SortModeTile(
              title: '最近使用',
              subtitle: '最近使用的功能优先显示',
              selected: config.sortMode == QuickAppsSortMode.recent,
              onTap: () async {
                await HomeLayoutService.setQuickAppsSortMode(
                  accountKey,
                  QuickAppsSortMode.recent,
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

class _SortModeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SortModeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
