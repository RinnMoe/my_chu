import 'package:flutter/material.dart';

import '../services/platform_environment.dart';
import 'home_layout_page.dart';
import 'navigation_layout_page.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 页面管理：首页管理 + 底栏管理两个子页，由“我的”页单一入口进入。
class PageManagementPage extends StatefulWidget {
  const PageManagementPage({super.key});

  @override
  State<PageManagementPage> createState() => _PageManagementPageState();
}

class _PageManagementPageState extends State<PageManagementPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final environment = PlatformEnvironment.fromContext(context);
    return _buildPage(context, environment);
  }

  Widget _buildPage(BuildContext context, PlatformEnvironment environment) {
    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded) {
      return _buildTablet(context);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(
            title: const Text('页面管理'),
            bottom: const TabBar(tabs: [Tab(text: '首页管理'), Tab(text: '底栏管理')]),
          ),
        ),
        body: const TabBarView(
          children: [HomeLayoutPanel(), NavigationLayoutPanel()],
        ),
      ),
    );
  }

  Widget _buildTablet(BuildContext context) {
    final menu = _buildMaterialTabletMenu(context);
    final content = KeyedSubtree(
      key: const ValueKey('page-management-content'),
      child: IndexedStack(
        index: _selectedIndex,
        children: [const HomeLayoutPanel(), const NavigationLayoutPanel()],
      ),
    );

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('页面管理')),
      ),
      body: Row(
        children: [
          SizedBox(
            key: const ValueKey('page-management-menu'),
            width: 240,
            child: menu,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildMaterialTabletMenu(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('页面管理', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                selected: _selectedIndex == 0,
                leading: const Icon(Icons.home_outlined),
                title: const Text('首页管理'),
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              ListTile(
                selected: _selectedIndex == 1,
                leading: const Icon(Icons.view_list_outlined),
                title: const Text('底栏管理'),
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
