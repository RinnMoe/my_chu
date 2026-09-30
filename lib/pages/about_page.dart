import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../capabilities/dev_visibility.dart';
import '../services/app_remote_services_service.dart';
import 'fenfa_dialogs.dart';
import 'fenfa_feedback_page.dart';
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

/// 关于页：版本信息、正式诊断入口，以及 Debug 构建下的开发工具。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionLabel = 'v${info.version}';
    });
  }

  void _openDeveloperTools() {
    _pushPage((_) => const DeveloperToolsHubPage());
  }

  void _openDiagnostics() {
    _pushPage((_) => const DiagnosticReportPage());
  }

  void _pushPage(WidgetBuilder builder) {
    Navigator.push<void>(context, MaterialPageRoute<void>(builder: builder));
  }

  Future<void> _openFeedback() async {
    if (!await AppRemoteServicesService.isEnabled()) {
      if (mounted) showAppRemoteServicesDisabledMessage(context);
      return;
    }
    if (mounted) _pushPage((_) => const FenfaFeedbackPage());
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
                leading: const Icon(Icons.info_outline),
                title: const Text('版本号'),
                subtitle: const Text('点击检查更新'),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 128),
                  child: Text(
                    _versionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                onTap: () => presentFenfaManualCheck(context),
              ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('诊断信息'),
                subtitle: const Text('预览、保存或分享脱敏诊断报告'),
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
                      subtitle: const Text('日志与调试工具'),
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
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('建言献策'),
                subtitle: const Text('提交问题或功能建议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openFeedback,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('用户协议与服务端设置'),
                subtitle: const Text('管理服务端功能'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pushPage((_) => const PrivacySettingsPage()),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.source_outlined),
                title: const Text('开源许可与致谢'),
                subtitle: const Text('本项目基于MPL协议开源'),
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
