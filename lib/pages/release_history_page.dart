import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/release_notes.dart';
import '../widgets/adaptive_settings.dart';

class GitHubReleasesButton extends StatelessWidget {
  const GitHubReleasesButton({super.key});

  static final _uri = Uri.parse('https://github.com/RinnMoe/my_chu/releases');

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(_uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The system may have no handler for external URLs.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开 GitHub Releases')));
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'GitHub Releases',
    onPressed: () => _open(context),
    icon: Image.asset(
      'assets/images/github_mark.png',
      width: 24,
      height: 24,
      color: IconTheme.of(context).color,
    ),
  );
}

class ReleaseHistoryPage extends StatelessWidget {
  const ReleaseHistoryPage({super.key, required this.releases});

  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('历史更新日志'),
      actions: const [GitHubReleasesButton()],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (releases.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无历史更新记录'),
              )
            else
              for (final release in releases)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: PageStorageKey(release.version),
                    title: Text('v${release.version}'),
                    subtitle: Text(release.date),
                    childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [ReleaseNoteEntries(sections: release.sections)],
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class ReleaseNoteEntries extends StatelessWidget {
  const ReleaseNoteEntries({super.key, required this.sections});

  final List<ReleaseNoteSection> sections;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final section in sections)
        if (section.entries.isEmpty && section.title != null)
          AppSectionHeading(section.title!)
        else if (section.entries.isNotEmpty)
          AdaptiveSettingsSection(
            title: section.title,
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              for (final entry in section.entries) ListTile(title: Text(entry)),
            ],
          ),
    ],
  );
}
