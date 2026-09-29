import 'package:flutter/material.dart';

import '../apps/app.dart';
import '../apps/app_service.dart';
import '../services/auth_service.dart';
import '../services/home_layout_service.dart';
import 'quick_apps_editor_sheet.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 首页管理页（独立打开时使用，带标题栏）。
class HomeLayoutPage extends StatelessWidget {
  final String? accountKey;

  const HomeLayoutPage({super.key, this.accountKey});

  @override
  Widget build(BuildContext context) {
    final body = HomeLayoutPanel(accountKey: accountKey);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('管理首页')),
      ),
      body: body,
    );
  }
}

/// 首页管理内容面板：供独立页与“页面管理”Tab 复用。
class HomeLayoutPanel extends StatefulWidget {
  final String? accountKey;

  const HomeLayoutPanel({super.key, this.accountKey});

  @override
  State<HomeLayoutPanel> createState() => _HomeLayoutPanelState();
}

class _HomeLayoutPanelState extends State<HomeLayoutPanel>
    with AutomaticKeepAliveClientMixin {
  static const _maxQuickApps = 8;

  String _accountKey = 'anonymous';
  List<AppDefinition> _quickAppCandidates = const [];
  QuickAppsConfig _quickAppsConfig = const QuickAppsConfig();
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    appCatalogNotifier.addListener(_load);
    HomeLayoutService.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    appCatalogNotifier.removeListener(_load);
    HomeLayoutService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final accountKey =
        widget.accountKey ??
        (await AuthService.getCurrentAccount())?.accountKey ??
        'anonymous';
    if (!mounted || generation != _loadGeneration) return;
    final projection = await AppService.loadQuickAppsProjection(accountKey);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _accountKey = accountKey;
      _quickAppCandidates = projection.candidates;
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
    await HomeLayoutService.setQuickAppsEnabled(_accountKey, enabled);
  }

  Future<void> _openEditor() async {
    await showQuickAppsEditorSheet(context, accountKey: _accountKey);
  }

  Future<void> _openSortMode() async {
    await showQuickAppsSortModeSheet(context, accountKey: _accountKey);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final sortModeLabel =
        _quickAppsConfig.sortMode == QuickAppsSortMode.manual ? '手动' : '最近使用';

    return _buildMaterial(context, sortModeLabel);
  }

  Widget _buildMaterial(BuildContext context, String sortModeLabel) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionTitle('首页内容'),
        const SizedBox(height: 6),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            title: const Text('常用功能'),
            subtitle: const Text('首页底部常用功能入口'),
            value: _quickAppsConfig.enabled,
            onChanged: _toggleEnabled,
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('常用功能'),
        const SizedBox(height: 6),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.tune_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: const Text('编辑常用功能'),
                subtitle: Text('$_selectedCount / $_maxQuickApps'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openEditor,
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              ListTile(
                leading: Icon(
                  Icons.sort_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: const Text('排序方式'),
                subtitle: Text(sortModeLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openSortMode,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
