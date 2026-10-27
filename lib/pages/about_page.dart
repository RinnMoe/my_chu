import 'package:flutter/material.dart';

import '../capabilities/dev_visibility.dart';
import 'diagnostic_report_page.dart';
import 'developer_tools_hub_page.dart';
import 'open_source_page.dart';
import 'privacy_settings_page.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

Widget _aboutArtwork({required double width, required double height}) {
  return ClipRect(
    child: SizedBox(
      key: const ValueKey('about-building-artwork-frame'),
      width: width,
      height: height,
      child: Image.asset(
        'assets/splash/campus_building_splash.png',
        key: const ValueKey('about-building-artwork-image'),
        fit: BoxFit.cover,
        alignment: Alignment.center,
      ),
    ),
  );
}

/// 关于页：正式诊断、协议与开源信息，以及 Debug 构建下的开发工具。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  void _openDeveloperTools() {
    _pushPage((_) => const DeveloperToolsHubPage());
  }

  void _openDiagnostics() {
    _pushPage((_) => const DiagnosticReportPage());
  }

  void _pushPage(WidgetBuilder builder) {
    Navigator.push<void>(context, MaterialPageRoute<void>(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              _aboutArtwork(width: 260, height: 104),
              const SizedBox(height: 12),
              Text(
                'MyCHU',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'By Rinn',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('诊断信息'),
                subtitle: const Text('预览、保存或分享已隐去个人信息的诊断报告'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openDiagnostics,
              ),
              DevOnly(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.build_outlined),
                      title: const Text('开发者工具'),
                      trailing: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DevBadge(),
                          SizedBox(width: 8),
                          Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: _openDeveloperTools,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('用户协议与在线功能'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pushPage((_) => const PrivacySettingsPage()),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.source_outlined),
                title: const Text('开源许可与致谢'),
                subtitle: const Text('本项目基于 Mozilla Public License 2.0 开源'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pushPage((_) => const OpenSourcePage()),
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: WindowControlsAwareAppBar(child: AppBar(title: const Text('关于'))),
      body: body,
    );
  }
}
