import 'package:flutter/material.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../services/user_error_message.dart';
import 'wozaichangda_models.dart';
import 'wozaichangda_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class WozaichangdaPage extends StatefulWidget {
  const WozaichangdaPage({super.key});

  @override
  State<WozaichangdaPage> createState() => _WozaichangdaPageState();
}

class _WozaichangdaPageState extends State<WozaichangdaPage> {
  List<WozaichangdaCategory> _categories = [];
  bool _loading = true;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _fetchApps();
  }

  Future<void> _fetchApps() async {
    final generation = ++_requestGeneration;
    try {
      final categories = await WozaichangdaService.fetchApps();

      if (mounted && generation == _requestGeneration) {
        setState(() {
          _categories = categories;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      logUserFacingError(UserErrorContext.network, error, operation: 'apps');
      setState(() {
        _error = userFacingError(UserErrorContext.network, error);
        _loading = false;
      });
    }
  }

  Future<void> _openApp(WozaichangdaApp app) async {
    final uri = WozaichangdaService.resolveAppUri(app);
    if (uri == null) return;

    await AuthenticatedWebViewCapability.openForService(
      context,
      title: app.name,
      url: uri.toString(),
      serviceId: WozaichangdaService.serviceId,
    );
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    _fetchApps();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('我在长大'), centerTitle: true),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('加载失败', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return const Center(child: Text('暂无应用'));
    }

    return RefreshIndicator(
      onRefresh: _fetchApps,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final cat in _categories) ...[
            _buildCategory(theme, cat),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildCategory(ThemeData theme, WozaichangdaCategory cat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            cat.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...cat.apps.map(
          (app) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildAppTile(theme, app),
          ),
        ),
      ],
    );
  }

  Widget _buildAppTile(ThemeData theme, WozaichangdaApp app) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openApp(app),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    app.icon.isNotEmpty
                        ? Image.network(
                          app.icon,
                          width: 40,
                          height: 40,
                          errorBuilder: (_, __, ___) => _iconPlaceholder(theme),
                        )
                        : _iconPlaceholder(theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  app.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconPlaceholder(ThemeData theme) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.app_shortcut,
        color: theme.colorScheme.primary,
        size: 24,
      ),
    );
  }
}
