import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../capabilities/channel_resources_link_capability.dart';

class ChannelResourcesErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const ChannelResourcesErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: colors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChannelResourcesEmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function()? onRetry;

  const ChannelResourcesEmptyView({
    super.key,
    required this.icon,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 50, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChannelResourcesSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ChannelResourcesSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class ChannelResourcesActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  const ChannelResourcesActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        leading: Icon(icon, color: destructive ? colors.error : null),
        title: Text(
          title,
          style:
              destructive
                  ? TextStyle(color: colors.error)
                  : theme.textTheme.titleMedium,
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? const Icon(Icons.chevron_right),
      ),
    );
  }
}

String channelResourcesSubPageTitle(String section) => '频道资料站 | $section';

/// A deliberately dependency-free Markdown subset for channel Q&A and
/// announcement copy. It keeps text native and gives links one controlled
/// opening path; it does not load remote images or execute HTML.
class ChannelMarkdownText extends StatefulWidget {
  final String markdown;
  final ChannelResourcesLinkCapability linkCapability;
  final TextStyle? style;

  const ChannelMarkdownText({
    super.key,
    required this.markdown,
    this.linkCapability = const ChannelResourcesLinkCapability(),
    this.style,
  });

  @override
  State<ChannelMarkdownText> createState() => _ChannelMarkdownTextState();
}

class _ChannelMarkdownTextState extends State<ChannelMarkdownText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(ChannelMarkdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? theme.textTheme.bodyMedium!;
    final lines = widget.markdown.replaceAll('\r\n', '\n').split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) _buildLine(context, line, baseStyle),
      ],
    );
  }

  Widget _buildLine(BuildContext context, String raw, TextStyle baseStyle) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) return const SizedBox(height: 8);
    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          _stripInlineMarkers(heading.group(2)!),
          style: baseStyle.copyWith(
            fontSize:
                level == 1
                    ? 21
                    : level == 2
                    ? 18
                    : 16,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      );
    }
    final list = RegExp(r'^\s*([-*]|\d+\.)\s+(.+)$').firstMatch(line);
    final content = list == null ? line : '• ${list.group(2)!}';
    final quote = content.startsWith('> ');
    final rendered = quote ? content.substring(2) : content;
    return Padding(
      padding: EdgeInsets.only(left: quote ? 12 : 0, bottom: 4),
      child: Text.rich(
        TextSpan(children: _inlineSpans(context, rendered, baseStyle)),
        style: baseStyle.copyWith(height: 1.55),
      ),
    );
  }

  List<InlineSpan> _inlineSpans(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final linkPattern = RegExp(r'\[([^\]]+)\]\((https?://[^)\s]+)\)');
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in linkPattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: _stripInlineMarkers(text.substring(offset))));
      }
      final label = match.group(1) ?? match.group(2) ?? '打开链接';
      final uri = Uri.tryParse(match.group(2) ?? '');
      if (uri == null || uri.host.isEmpty) {
        spans.add(TextSpan(text: label));
      } else {
        final recognizer =
            TapGestureRecognizer()
              ..onTap = () {
                unawaited(widget.linkCapability.open(uri));
              };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: label,
            style: baseStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      }
      offset = match.end;
    }
    if (offset < text.length) {
      spans.add(TextSpan(text: _stripInlineMarkers(text.substring(offset))));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: _stripInlineMarkers(text)));
    }
    return spans;
  }

  String _stripInlineMarkers(String value) =>
      value.replaceAll('**', '').replaceAll('`', '');

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}

void showChannelResourcesSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
