import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/apple_window_controls.dart';

class OpenSourcePage extends StatelessWidget {
  const OpenSourcePage({super.key});

  static const _dependencies = <_DependencyEntry>[
    _DependencyEntry('Mapbox Maps Flutter', '校园地图展示'),
    _DependencyEntry('Dio', '网络请求'),
    _DependencyEntry('http', 'HTTP 请求工具'),
    _DependencyEntry('flutter_inappwebview', '网页内容展示'),
    _DependencyEntry('flutter_secure_storage', '安全存储'),
    _DependencyEntry('shared_preferences', '本地设置存储'),
    _DependencyEntry('mobile_scanner', '二维码与条码扫描'),
    _DependencyEntry('flutter_blue_plus', 'BLE 设备连接'),
    _DependencyEntry('geolocator', '定位'),
    _DependencyEntry('flutter_local_notifications', '本地通知'),
    _DependencyEntry('aptabase_flutter', '匿名使用统计'),
    _DependencyEntry('zxing2', '条码编解码'),
    _DependencyEntry('archive', '压缩包处理'),
    _DependencyEntry('file_selector', '文件选择'),
    _DependencyEntry('dynamic_color', '动态配色'),
  ];

  Future<void> _openExternal(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // An unavailable browser should not prevent reading the local license list.
    }
  }

  void _showDependencyLicenses(BuildContext context) {
    showLicensePage(context: context, applicationName: 'MyCHU');
  }

  Widget _acknowledgement(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('本项目开发中受到了 '),
        _ProjectLink(
          title: 'HFUT-Schedule',
          url: 'https://github.com/Chiu-xaH/HFUT-Schedule',
          onTap: _openExternal,
        ),
        const Text('、'),
        _ProjectLink(
          title: 'DanXi',
          url: 'https://github.com/DanXi-Dev/DanXi',
          onTap: _openExternal,
        ),
        const Text(' 等项目的灵感启发，以及许多同学的建言献策。在此向他们表示感谢。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('开源许可与致谢')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _MaterialSectionHeading('开源许可', style: theme.textTheme.titleSmall),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('本应用依照 Mozilla Public License 2.0协议开源。'),
          ),
          ListTile(
            title: const Text('查看开源仓库'),
            trailing: const Icon(Icons.open_in_new),
            onTap:
                () => _openExternal('https://github.com/RinnMoe/my_chu'),
          ),
          const Divider(),
          _MaterialSectionHeading('特别鸣谢', style: theme.textTheme.titleSmall),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _acknowledgement(context),
          ),
          const Divider(),
          _MaterialSectionHeading('主要依赖', style: theme.textTheme.titleSmall),
          for (final dependency in _dependencies)
            ListTile(
              title: Text(dependency.name),
              subtitle: Text(dependency.purpose),
              dense: true,
            ),
          const Divider(),
          ListTile(
            title: const Text('查看第三方依赖许可证'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDependencyLicenses(context),
          ),
        ],
      ),
    );
  }
}

class _DependencyEntry {
  const _DependencyEntry(this.name, this.purpose);

  final String name;
  final String purpose;
}

class _MaterialSectionHeading extends StatelessWidget {
  const _MaterialSectionHeading(this.title, {required this.style});

  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: style),
    );
  }
}

class _ProjectLink extends StatelessWidget {
  const _ProjectLink({
    required this.title,
    required this.url,
    required this.onTap,
  });

  final String title;
  final String url;
  final Future<void> Function(String url) onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(url),
        child: Text(
          title,
          style: TextStyle(color: color, decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}
