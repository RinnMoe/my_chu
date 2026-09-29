import 'package:flutter/material.dart';

import '../capabilities/dev_visibility.dart';
import 'data_demo_page.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// DEV 专用的开发调试工具入口。
class DevToolsPage extends StatelessWidget {
  const DevToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('调试工具')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: const Text('数据 Demo'),
                  subtitle: const Text('按模块预览与填充演示数据'),
                  trailing: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DevBadge(),
                      SizedBox(width: 8),
                      Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const DataDemoPage(),
                        ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
