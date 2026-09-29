import 'package:flutter/material.dart';

import '../widgets/apple_window_controls.dart';
import 'dev_tools_page.dart';
import 'log_page.dart';

/// Collects the existing developer-only pages behind one About entry.
class DeveloperToolsHubPage extends StatelessWidget {
  const DeveloperToolsHubPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('开发者工具')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.list_alt_outlined),
                  title: const Text('日志'),
                  subtitle: const Text('查看应用运行日志'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const LogPage()),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.build_outlined),
                  title: const Text('调试工具'),
                  subtitle: const Text('数据演示与开发调试工具'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const DevToolsPage()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
