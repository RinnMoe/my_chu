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
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child:
              releases.isEmpty
                  ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无历史更新记录，可在 GitHub 查看。'),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: releases.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder:
                        (context, index) =>
                            _ReleaseHistoryTile(release: releases[index]),
                  ),
        ),
      ),
    ),
  );
}

class _ReleaseHistoryTile extends StatelessWidget {
  const _ReleaseHistoryTile({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(release.version),
        // The card owns the outline in both states.
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minTileHeight: 56,
        textColor: colors.onSurface,
        iconColor: colors.primary,
        title: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                'v${release.version}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(release.date, style: muted),
            ],
          ),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 12),
          if (release.sections.isEmpty)
            Text('本版本暂无更新记录', style: muted)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                for (final section in release.sections)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      if (section.title != null)
                        AppSectionHeading(section.title!),
                      for (final entry in section.entries)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          spacing: 8,
                          children: [
                            ExcludeSemantics(child: Text('•', style: muted)),
                            Expanded(
                              child: Text(
                                entry,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
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
