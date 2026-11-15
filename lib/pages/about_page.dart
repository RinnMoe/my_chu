import 'package:flutter/material.dart';

import '../capabilities/dev_visibility.dart';
import '../capabilities/qq_group_join_capability.dart';
import '../services/app_remote_services_service.dart';
import 'app_update_dialog.dart' show showAppRemoteServicesDisabledMessage;
import 'appreciation_page.dart';
import '../widgets/diagnostics_entries.dart';
import 'developer_tools_hub_page.dart';
import 'feedback_community_page.dart';
import 'open_source_page.dart';
import 'privacy_settings_page.dart';

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

/// 关于页：项目交流、赞赏、诊断、协议与开源信息。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.qqGroup = const QqGroupJoinCapability()});

  final QqGroupJoinCapability qqGroup;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  Future<void> _openFeedback() async {
    if (!await AppRemoteServicesService.isEnabled()) {
      if (mounted) showAppRemoteServicesDisabledMessage(context);
      return;
    }
    if (mounted) _pushPage((_) => const FeedbackCommunityPage());
  }

  Future<void> _joinQqGroup() async {
    final opened = await widget.qqGroup.joinGroup();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '未能唤起 QQ，可在 QQ 中搜索群号 ${QqGroupJoinCapability.groupNumber}',
        ),
      ),
    );
  }

  void _openDeveloperTools() {
    _pushPage((_) => const DeveloperToolsHubPage());
  }

  void _pushPage(WidgetBuilder builder) {
    Navigator.push<void>(context, MaterialPageRoute<void>(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
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
        _section(context, '关于', [
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('建言献策'),
            subtitle: const Text('分享你遇到的问题或建议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openFeedback,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('QQ交流群'),
            subtitle: const Text(QqGroupJoinCapability.groupNumber),
            trailing: const Icon(Icons.chevron_right),
            onTap: _joinQqGroup,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: const Text('赞赏'),
            subtitle: const Text('支持本项目'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pushPage((_) => const AppreciationPage()),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('用户协议'),
            subtitle: const Text('管理用户协议与在线功能'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pushPage((_) => const PrivacySettingsPage()),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: const Text('开源信息'),
            subtitle: const Text('本项目基于MPL v2开源'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pushPage((_) => const OpenSourcePage()),
          ),
        ]),
        _section(context, '修复', [
          const DiagnosticsEntries(),
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
        ]),
      ],
    );
    return Scaffold(appBar: AppBar(title: const Text('关于')), body: body);
  }
}
