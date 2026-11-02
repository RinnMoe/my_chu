import 'package:flutter/material.dart';

import '../../apps/app.dart';
import '../../apps/app_service.dart';
import '../../services/home_layout_service.dart';
import '../../services/remote_feature_policy/feature_access_guard.dart';
import '../../services/remote_feature_policy/remote_feature_policy_service.dart';
import '../../widgets/adaptive_settings.dart';
import '../quick_apps_editor_sheet.dart';

/// 焦点页管理：常用功能的启用、编辑与排序。
class FocusSection extends StatefulWidget {
  const FocusSection({super.key});

  @override
  State<FocusSection> createState() => _FocusSectionState();
}

class _FocusSectionState extends State<FocusSection> {
  static const _maxQuickApps = 8;

  List<AppDefinition> _quickAppCandidates = const [];
  QuickAppsConfig _quickAppsConfig = const QuickAppsConfig();
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    appCatalogNotifier.addListener(_load);
    HomeLayoutService.revision.addListener(_load);
    RemoteFeaturePolicyService.instance.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    appCatalogNotifier.removeListener(_load);
    HomeLayoutService.revision.removeListener(_load);
    RemoteFeaturePolicyService.instance.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (!mounted || generation != _loadGeneration) return;
    final projection = await AppService.loadQuickAppsProjection();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _quickAppCandidates = FeatureEntryVisibility.filter(
        projection.candidates,
      );
      _quickAppsConfig = projection.config;
      _loading = false;
    });
  }

  int get _selectedCount {
    final ids = _quickAppCandidates.map((plugin) => plugin.metadata.id).toSet();
    final count = _quickAppsConfig.selectedAppIds.where(ids.contains).length;
    return count > _maxQuickApps ? _maxQuickApps : count;
  }

  Future<void> _toggleEnabled(bool enabled) async {
    await HomeLayoutService.setQuickAppsEnabled(enabled);
  }

  Future<void> _openEditor() async {
    await showQuickAppsEditorSheet(context);
  }

  Future<void> _openSortMode() async {
    await showQuickAppsSortModeSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdaptiveSettingsSection(
        title: '焦点页管理',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }
    final enabled = _quickAppsConfig.enabled;
    final sortModeLabel = _quickAppsConfig.sortMode == QuickAppsSortMode.manual
        ? '手动'
        : '最近使用';
    return AdaptiveSettingsSection(
      title: '焦点页管理',
      children: [
        AdaptiveSettingsRow(
          key: const ValueKey('page-preferences-quick-apps'),
          icon: Icons.widgets_outlined,
          title: '常用功能',
          showChevron: false,
          trailing: Switch(
            value: enabled,
            onChanged: (value) => _toggleEnabled(value),
          ),
          onTap: () => _toggleEnabled(!enabled),
        ),
        AdaptiveSettingsRow(
          icon: Icons.edit_outlined,
          title: '编辑常用功能',
          trailingValue: '$_selectedCount / $_maxQuickApps',
          onTap: _openEditor,
        ),
        AdaptiveSettingsRow(
          icon: Icons.sort_outlined,
          title: '排序方式',
          trailingValue: sortModeLabel,
          onTap: _openSortMode,
        ),
      ],
    );
  }
}
