import 'package:flutter/material.dart';

import '../services/privacy_policy_document.dart';
import '../services/privacy_policy_repository.dart';
import '../services/privacy_agreement_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key, this.document});
  final PrivacyPolicyDocument? document;

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  PrivacyPolicyDocument? _selected;
  List<PrivacyPolicyDocument> _documents = [];
  bool _loading = true;
  bool _failed = false;
  int _acceptedVersion = 0;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    if (document != null) {
      _selected = document;
      _documents = [document];
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final repository = PrivacyPolicyRepository.instance;
    try {
      _acceptedVersion = await PrivacyAgreementService.acceptedVersion();
      var documents = await repository.cached();
      if (refresh || documents.isEmpty) {
        try {
          await repository.refresh(
            acceptedVersion: _acceptedVersion,
            acceptedHash: await PrivacyAgreementService.acceptedHash(),
          );
          documents = await repository.cached();
        } catch (_) {
          if (mounted) setState(() => _failed = true);
        }
      }
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _selected = null;
        for (final document in documents) {
          if (document.version == _acceptedVersion) _selected = document;
        }
        // A migrated acceptance has no cached body. Do not label a newer
        // document as the agreement the user previously accepted.
        if (_selected == null && _acceptedVersion < 3 && documents.isNotEmpty) {
          _selected = documents.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('用户协议'),
          actions: [
            if (widget.document == null)
              IconButton(
                tooltip: '刷新协议',
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_failed)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _documents.isEmpty ? '暂时无法获取协议，请检查网络后重试。' : '刷新失败，仍可阅读已缓存版本。',
                ),
              ),
            if (widget.document == null && _documents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DropdownButton<int>(
                  isExpanded: true,
                  hint: const Text('选择已缓存的协议版本'),
                  value: _selected?.version,
                  items:
                      _documents
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.version,
                              child: Text(
                                '第 ${d.version} 版 · ${d.version == _acceptedVersion ? "已同意" : "未同意"}',
                              ),
                            ),
                          )
                          .toList(),
                  onChanged:
                      (version) => setState(
                        () =>
                            _selected = _documents.firstWhere(
                              (d) => d.version == version,
                            ),
                      ),
                ),
              ),
            Expanded(
              child:
                  _selected != null
                      ? _document(context)
                      : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _acceptedVersion >= 3
                                    ? '已同意版本的正文尚未缓存。可重试获取，或选择已缓存的其他版本查看。'
                                    : '需要联网获取用户协议。',
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed:
                                    _loading
                                        ? null
                                        : () => _load(refresh: true),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ),
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
            Text(_selected!.title, style: titleStyle),
            const SizedBox(height: 8),
            Text(
              '第 ${_selected!.version} 版 · ${_selected!.revision}\n更新日期：${_localizedDate(_selected!.updatedDate)}',
              style: metadataStyle,
            ),
            const SizedBox(height: 28),
            for (final section in _selected!.sections) ...[
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
