import 'package:flutter/material.dart';

import '../services/privacy_policy_document.g.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('用户协议')),
      ),
      body: SafeArea(child: _document(context)),
    );
  }

  Widget _document(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.headlineSmall;
    final sectionStyle = theme.textTheme.titleLarge;
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.55);
    final metadataStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Text(PrivacyPolicyDocument.current.title, style: titleStyle),
            const SizedBox(height: 8),
            Text(
              '更新日期：${_localizedDate(PrivacyPolicyDocument.current.updatedDate)}',
              style: metadataStyle,
            ),
            const SizedBox(height: 28),
            for (final section in PrivacyPolicyDocument.current.sections) ...[
              Text(
                section.title,
                key: ValueKey<String>('privacy-policy-section-${section.id}'),
                style: sectionStyle,
              ),
              const SizedBox(height: 10),
              for (
                var index = 0;
                index < section.paragraphs.length;
                index++
              ) ...[
                Text.rich(
                  _paragraphSpan(section.paragraphs[index], bodyStyle),
                  key: ValueKey<String>(
                    'privacy-policy-paragraph-${section.id}-$index',
                  ),
                ),
                if (index + 1 < section.paragraphs.length)
                  const SizedBox(height: 12),
              ],
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

String _localizedDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return '${date.year} 年 ${date.month} 月 ${date.day} 日';
}

TextSpan _paragraphSpan(String value, TextStyle? style) {
  final spans = <TextSpan>[];
  final emphasis = RegExp(r'\*\*(.+?)\*\*');
  var offset = 0;
  for (final match in emphasis.allMatches(value)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: value.substring(offset, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(1),
        style: style?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    offset = match.end;
  }
  if (offset < value.length) {
    spans.add(TextSpan(text: value.substring(offset)));
  }
  return TextSpan(style: style, children: spans);
}
