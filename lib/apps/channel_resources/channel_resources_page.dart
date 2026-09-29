import 'package:flutter/material.dart';

import '../../pages/channel_account_page.dart';
import 'channel_resources_profile_page.dart';
import 'channel_resources_resources_page.dart';
import 'channel_resources_service.dart';
import 'channel_resources_widgets.dart';

/// Native Android presentation for the normal-user channel-resources site.
/// The two tabs are local to this app and do not change the host bottom bar.
class ChannelResourcesPage extends StatefulWidget {
  final ChannelResourcesService? service;

  const ChannelResourcesPage({super.key, this.service});

  @override
  State<ChannelResourcesPage> createState() => _ChannelResourcesPageState();
}

class _ChannelResourcesPageState extends State<ChannelResourcesPage> {
  ChannelResourcesService? _service;
  final _resourceSearchVisibility = ValueNotifier<bool>(false);
  final _pointsInvalidation = ValueNotifier<int>(0);
  List<Widget?> _tabs = List<Widget?>.filled(2, null);
  int _selectedIndex = 0;
  ChannelAccountStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _service?.authStateListenable.removeListener(_handleAuthChanged);
    _resourceSearchVisibility.dispose();
    _pointsInvalidation.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final service = widget.service ?? ChannelResourcesService.current;
    if (!mounted) return;
    _attachService(service);
    try {
      await service.restore();
    } on Object {
      // The session publishes the corresponding auth state.
    }
  }

  void _attachService(ChannelResourcesService service) {
    if (identical(_service, service)) return;
    _service?.authStateListenable.removeListener(_handleAuthChanged);
    _service = service;
    _lastStatus = service.authState.status;
    service.authStateListenable.addListener(_handleAuthChanged);
  }

  void _handleAuthChanged() {
    if (!mounted) return;
    final service = _service;
    if (service == null) return;
    final status = service.authState.status;
    final authTransition = _lastStatus != status;
    _lastStatus = status;
    setState(() {
      if (authTransition) {
        // Child pages load only when first selected. Resetting them on an auth
        // transition prevents data from the previous channel user lingering.
        _tabs = List<Widget?>.filled(2, null);
        _selectedIndex = 0;
        _resourceSearchVisibility.value = false;
      }
    });
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      if (index != 0) _resourceSearchVisibility.value = false;
      _tabs[index] ??= _createTab(index);
    });
  }

  Widget _createTab(int index) {
    final service = _service!;
    switch (index) {
      case 0:
        return ChannelResourcesResourcesPage(
          service: service,
          onPointsChanged: _invalidatePoints,
          searchVisibility: _resourceSearchVisibility,
        );
      default:
        return ChannelResourcesProfilePage(
          service: service,
          pointsInvalidation: _pointsInvalidation,
        );
    }
  }

  void _invalidatePoints() {
    _pointsInvalidation.value++;
  }

  Future<void> _retryChannelSession() async {
    final service = _service;
    if (service != null) await service.restore();
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final showSearch =
        _service?.authState.status == ChannelAccountStatus.authenticated &&
        _selectedIndex == 0;
    return AppBar(
      title: const Text('频道资料站'),
      actions: [
        if (showSearch)
          ValueListenableBuilder<bool>(
            valueListenable: _resourceSearchVisibility,
            builder:
                (context, visible, _) => IconButton(
                  tooltip: visible ? '关闭搜索' : '搜索资料',
                  onPressed: () => _resourceSearchVisibility.value = !visible,
                  icon: Icon(visible ? Icons.close : Icons.search),
                ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    _tabs[_selectedIndex] ??= _createTab(_selectedIndex);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < _tabs.length; index++)
          if (_tabs[index] != null)
            Offstage(
              offstage: index != _selectedIndex,
              child: TickerMode(
                enabled: index == _selectedIndex,
                child: _tabs[index]!,
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return Scaffold(
        appBar: _buildAppBar(context),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return ValueListenableBuilder<ChannelAccountState>(
      valueListenable: service.authStateListenable,
      builder: (context, state, _) {
        switch (state.status) {
          case ChannelAccountStatus.restoring:
            return Scaffold(
              appBar: _buildAppBar(context),
              body: const Center(child: CircularProgressIndicator()),
            );
          case ChannelAccountStatus.unavailable:
            return Scaffold(
              appBar: _buildAppBar(context),
              body: ChannelResourcesErrorView(
                message:
                    ChannelAccountException(
                      state.errorType ?? ChannelAccountErrorType.network,
                    ).userMessage,
                onRetry: _retryChannelSession,
              ),
            );
          case ChannelAccountStatus.signedOut:
            return Scaffold(
              appBar: _buildAppBar(context),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.forum_outlined, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        '请先登录校园频道账号',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '本功能由校园频道运营，需要通过独立的校园频道账号登录。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed:
                            () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChannelAccountPage(),
                              ),
                            ),
                        icon: const Icon(Icons.login),
                        label: const Text('前往登录'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          case ChannelAccountStatus.authenticated:
            return Scaffold(
              appBar: _buildAppBar(context),
              body: _buildBody(),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: '账户',
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}
