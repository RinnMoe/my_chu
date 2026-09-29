import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../apps/app.dart';
import '../apps/app_service.dart';
import '../capabilities/skeleton_block.dart';
import '../services/platform_environment.dart';
import '../widgets/feature_icon_tile.dart';
import 'app_sheet.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  List<AppDefinition> _apps = const [];
  final Map<AppCategory, bool> _expandedCategories = {};
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    appCatalogNotifier.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    appCatalogNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final snapshot = await AppService.loadCatalog();
    final apps = snapshot.plugins
        .where(
          (plugin) =>
              !plugin.metadata.core &&
              AppService.isVisibleInCurrentMode(plugin) &&
              (snapshot.states[plugin.metadata.id]?.installed ?? false),
        )
        .toList(growable: false);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  Future<void> _open(AppDefinition plugin) {
    return openAppDefinition(context, plugin);
  }

  void _showDetails(AppDefinition plugin) {
    showAppDetailSheet(context, plugin);
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      appBar: WindowControlsAwareAppBar(child: AppBar(title: const Text('功能'))),
      body: SafeArea(bottom: false, child: _buildCatalogBody()),
    );
    return page;
  }

  Widget _buildCatalogBody() {
    if (_loading) {
      return const SingleChildScrollView(
        key: PageStorageKey<String>('feature-catalog-loading'),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: _AppsSkeleton(),
      );
    }
    if (_apps.isEmpty) {
      return const SingleChildScrollView(
        key: PageStorageKey<String>('feature-catalog-empty'),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: _HintRow(icon: Icons.apps_outlined, text: '暂无已添加功能'),
      );
    }
    return SingleChildScrollView(
      key: const PageStorageKey<String>('feature-catalog-category'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildCategoryChildren(),
      ),
    );
  }

  List<Widget> _buildCategoryChildren() {
    final grouped = <AppCategory, List<AppDefinition>>{
      for (final category in AppCategory.values) category: <AppDefinition>[],
    };
    for (final plugin in _apps) {
      final category = plugin.metadata.catalogCategory;
      grouped[category]!.add(plugin);
    }

    final children = <Widget>[];
    for (final category in AppCategory.values) {
      final plugins = grouped[category]!;
      if (plugins.isEmpty) continue;
      children.add(
        _FeatureSection(
          title: category.label,
          plugins: plugins,
          expanded: _expandedCategories[category] ?? true,
          onToggle: () {
            setState(() {
              _expandedCategories[category] =
                  !(_expandedCategories[category] ?? true);
            });
          },
          onOpen: _open,
          onLongPress: _showDetails,
        ),
      );
    }
    return children;
  }
}

class _FeatureSection extends StatelessWidget {
  final String title;
  final List<AppDefinition> plugins;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<AppDefinition> onOpen;
  final ValueChanged<AppDefinition> onLongPress;

  const _FeatureSection({
    required this.title,
    required this.plugins,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    final header = SizedBox(
      width: double.infinity,
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: heading)),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.expand_more,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    final headerControl = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: header,
      ),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(expanded: expanded, child: headerControl),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child:
                      expanded
                          ? _FeatureGrid(
                            plugins: plugins,
                            onOpen: onOpen,
                            onLongPress: onLongPress,
                          )
                          : const SizedBox(width: double.infinity, height: 0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _featureGridSpacing = 8.0;
const _featureGridMaxTileWidth = 220.0;

int _featureGridColumnCount(double width) {
  if (width < PlatformEnvironment.mediumWidthBreakpoint) return 2;
  return ((width + _featureGridSpacing) /
          (_featureGridMaxTileWidth + _featureGridSpacing))
      .ceil()
      .clamp(3, 6)
      .toInt();
}

class _FeatureGrid extends StatelessWidget {
  final List<AppDefinition> plugins;
  final ValueChanged<AppDefinition> onOpen;
  final ValueChanged<AppDefinition> onLongPress;

  const _FeatureGrid({
    required this.plugins,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _featureGridColumnCount(constraints.maxWidth);
        final baseFontSize =
            (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0);
        final textScaler = MediaQuery.textScalerOf(context);
        final lineHeight = textScaler.scale(baseFontSize) * 1.25;
        const maxLines = 2;
        final tileExtent =
            math
                .max(
                  featureCatalogTileMinHeight,
                  16.0 +
                      math.max(featureCatalogIconSize, lineHeight * maxLines),
                )
                .toDouble();
        final tileWidth =
            (constraints.maxWidth - _featureGridSpacing * (columns - 1)) /
            columns;
        return Wrap(
          spacing: _featureGridSpacing,
          runSpacing: _featureGridSpacing,
          children: [
            for (var index = 0; index < plugins.length; index++)
              _buildPluginTile(plugins[index], tileWidth, tileExtent, maxLines),
          ],
        );
      },
    );
  }

  Widget _buildPluginTile(
    AppDefinition plugin,
    double tileWidth,
    double tileExtent,
    int maxLines,
  ) {
    final tile = SizedBox(
      width: tileWidth,
      height: tileExtent,
      child: FeatureCatalogCard(
        metadata: plugin.metadata,

        onTap: () => onOpen(plugin),
        onLongPress: () => onLongPress(plugin),
        maxLines: maxLines,
      ),
    );
    return tile;
  }
}

class _HintRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HintRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppsSkeleton extends StatelessWidget {
  const _AppsSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _featureGridColumnCount(constraints.maxWidth);
        final tileWidth =
            (constraints.maxWidth - _featureGridSpacing * (columns - 1)) /
            columns;
        return Wrap(
          spacing: _featureGridSpacing,
          runSpacing: _featureGridSpacing,
          children: [
            for (var index = 0; index < 10; index++)
              SizedBox(
                width: tileWidth,
                height: featureCatalogTileMinHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: SkeletonBlock(
                      width: featureCatalogIconSize,
                      height: featureCatalogIconSize,
                      radius: featureIconTileRadius,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
