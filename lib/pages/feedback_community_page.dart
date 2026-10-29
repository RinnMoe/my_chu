import 'package:flutter/material.dart';

import '../services/app_remote_services_service.dart';
import '../services/feedback_community_service.dart';
import '../services/privacy_agreement_service.dart';
import '../theme/app_palette.dart';
import '../widgets/apple_window_controls.dart';
import 'feedback_composer_page.dart';

const _stateLabels = {
  'considering': '评估中',
  'planned': '计划中',
  'developing': '开发中',
  'released': '已发布',
  'declined': '暂不采纳',
};

/// 标题约定为「类别#编号 正文」；只用于分类筛选与标签，正文照原样展示。
final _titlePrefix = RegExp(
  r'^([A-Za-z\u4e00-\u9fa5]{1,8})\s*#\s*(\d{1,4})(?:\s+([\s\S]+))?$',
);

const _categoryTones = {'BUG': 'red', '新功能': 'green', '功能优化': 'blue'};

String? _categoryOf(Object? title) {
  if (title is! String) return null;
  return _titlePrefix.firstMatch(title.trim())?.group(1);
}

/// 建言献策：公开建议列表，右下角入口进入提交表单。
class FeedbackCommunityPage extends StatefulWidget {
  const FeedbackCommunityPage({super.key, this.service});

  final FeedbackCommunityService? service;

  @override
  State<FeedbackCommunityPage> createState() => _FeedbackCommunityPageState();
}

class _FeedbackCommunityPageState extends State<FeedbackCommunityPage> {
  late final _service = widget.service ?? FeedbackCommunityService();
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true, _more = false, _mineOnly = false;
  int _offset = 0, _generation = 0;
  String? _category;

  @override
  void initState() {
    super.initState();
    PrivacyAgreementService.revision.addListener(_gateChanged);
    AppRemoteServicesService.revision.addListener(_gateChanged);
    _load();
  }

  void _gateChanged() {
    _items = [];
    _load();
  }

  @override
  void dispose() {
    PrivacyAgreementService.revision.removeListener(_gateChanged);
    AppRemoteServicesService.revision.removeListener(_gateChanged);
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        _offset = 0;
        _items = [];
      }
    });
    try {
      final result = await _service.feed(offset: _offset, mine: _mineOnly);
      if (!mounted || generation != _generation) return;
      final rows = (result['proposals'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _items = [if (append) ..._items, ...rows];
        _more = rows.length == 50;
        _offset += rows.length;
        if (_category != null &&
            !_items.any((item) => _categoryOf(item['title']) == _category)) {
          _category = null;
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error =
                  error is CommunityException ? error.message : '加载失败，请稍后重试。',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _propose() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FeedbackComposerPage(communityService: _service),
      ),
    );
    if (mounted && created == true) await _load();
  }

  Future<void> _open(Map<String, dynamic> item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProposalPage(service: _service, proposal: item),
      ),
    );
    if (mounted) await _load();
  }

  Widget _tile(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final pending = p['moderation'] != 'published';
    final votes = p['votes'] as int? ?? 0;
    final comments = p['comments'] as int? ?? 0;
    final extra = [
      if (votes > 0) '$votes 人支持',
      if (comments > 0) '$comments 条讨论',
    ].join(' · ');
    final title = p['title'] as String;
    final prefix = _titlePrefix.firstMatch(title.trim());
    final category = prefix?.group(1);
    final rest = prefix == null ? title : prefix.group(3) ?? '';
    final status = pending ? '审核中' : _stateLabels[p['state']] ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (category != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: _tag(
                                context,
                                '$category#${prefix!.group(2)}',
                                _categoryTones[category.toUpperCase()] ??
                                    'gray',
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              rest,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      if (status.isNotEmpty || extra.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (status.isNotEmpty)
                              _tag(
                                context,
                                status,
                                _statusTone(p['state'], pending),
                              ),
                            if (status.isNotEmpty && extra.isNotEmpty)
                              const SizedBox(width: 8),
                            if (extra.isNotEmpty)
                              Expanded(
                                child: Text(
                                  extra,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (p['voted'] == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Icon(
                      Icons.thumb_up,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusTone(Object? state, bool pending) {
    if (pending) return 'gold';
    return switch (state) {
      'considering' => 'gold',
      'planned' || 'developing' => 'blue',
      'released' => 'green',
      _ => 'gray',
    };
  }

  Widget _tag(BuildContext context, String text, String tone) {
    final (background, foreground) = _tagColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (Color, Color) _tagColors(BuildContext context, String tone) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    return switch (tone) {
      'red' => (semantic.dangerContainer, semantic.onDangerContainer),
      'green' => (semantic.successContainer, semantic.onSuccessContainer),
      'blue' => (semantic.infoContainer, semantic.onInfoContainer),
      'gold' => (semantic.warningContainer, semantic.onWarningContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
  }

  List<String> get _categoryOptions {
    final seen = <String>[];
    for (final item in _items) {
      final category = _categoryOf(item['title']);
      if (category != null && !seen.contains(category)) seen.add(category);
    }
    return seen;
  }

  List<Map<String, dynamic>> get _visibleItems =>
      _category == null
          ? _items
          : _items
              .where((item) => _categoryOf(item['title']) == _category)
              .toList();

  Widget _buildFollowBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '您也可以通过以下方式联系我们。',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '交流群：1049712941\n公众号：Rinn.Log\n邮箱：mychu@rinn.moe',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/feedback_wechat_qr.jpg',
              width: 96,
              height: 96,
              filterQuality: FilterQuality.none,
              semanticLabel: '公众号二维码',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final categories = _categoryOptions;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('只看我的'),
            selected: _mineOnly,
            onSelected: (value) {
              setState(() {
                _mineOnly = value;
                _category = null;
              });
              _load();
            },
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 22,
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              label: const Text('全部'),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
            for (final category in categories) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(category),
                selected: _category == category,
                onSelected:
                    (selected) =>
                        setState(() => _category = selected ? category : null),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_error!),
                TextButton(onPressed: () => _load(), child: const Text('重试')),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildFollowBanner(context),
                ),
                _buildFilters(context),
                if (!_loading && _error == null && _visibleItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _category != null
                          ? '已加载的内容里没有「$_category」类别。'
                          : _mineOnly
                          ? '你还没有提过建议。'
                          : '还没有建议，来说说你的想法。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ..._visibleItems.map(_tile),
                if (_more)
                  TextButton(
                    onPressed: _loading ? null : () => _load(append: true),
                    child: const Text('加载更多'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('建言献策')),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '提出建议',
        onPressed: _loading ? null : _propose,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _buildList(context),
          ),
        ),
      ),
    );
  }
}

class _ProposalPage extends StatefulWidget {
  const _ProposalPage({required this.service, required this.proposal});
  final FeedbackCommunityService service;
  final Map<String, dynamic> proposal;
  @override
  State<_ProposalPage> createState() => _ProposalPageState();
}

class _ProposalPageState extends State<_ProposalPage> {
  late Map<String, dynamic> _proposal = widget.proposal;
  List<Map<String, dynamic>> _comments = [];
  int _commentOffset = 0, _generation = 0;
  bool _moreComments = false;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    PrivacyAgreementService.revision.addListener(_gateChanged);
    AppRemoteServicesService.revision.addListener(_gateChanged);
    _load();
  }

  void _gateChanged() {
    setState(() {
      _comments = [];
      _proposal = {};
    });
    _load();
  }

  @override
  void dispose() {
    PrivacyAgreementService.revision.removeListener(_gateChanged);
    AppRemoteServicesService.revision.removeListener(_gateChanged);
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final generation = ++_generation;
    if (!append) _commentOffset = 0;
    setState(() => _busy = true);
    try {
      final r = await widget.service.feed(
        proposal: widget.proposal['id'] as String,
        offset: _commentOffset,
      );
      if (!mounted || generation != _generation) return;
      final proposals = (r['proposals'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _proposal = proposals.isEmpty ? {} : proposals.first;
        final rows =
            (r['discussion'] as List? ?? []).cast<Map<String, dynamic>>();
        _comments = [if (append) ..._comments, ...rows];
        _commentOffset += rows.length;
        _moreComments = rows.length == 50;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = e is CommunityException ? e.message : '加载失败，请重试。',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _vote() async {
    setState(() => _busy = true);
    try {
      await widget.service.write(
        action: 'vote',
        id: FeedbackCommunityService.requestId(),
        proposal: _proposal['id'] as String,
        supported: _proposal['voted'] != true,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is CommunityException ? e.message : '操作未完成，请刷新后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WindowControlsAwareAppBar(
      child: AppBar(
        title: const Text('建议详情'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('重试'),
                ),
              ],
              if (_proposal.isNotEmpty) ...[
                Text(
                  _proposal['title'] as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _proposal['moderation'] == 'published'
                      ? _stateLabels[_proposal['state']] ?? ''
                      : '审核中',
                ),
                const SizedBox(height: 20),
                SelectableText(_proposal['body'] as String),
                const SizedBox(height: 20),
                if ((_proposal['official_reply'] as String? ?? '').isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '开发者回复',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(_proposal['official_reply'] as String),
                        ],
                      ),
                    ),
                  ),
                if (_proposal['moderation'] == 'published') ...[
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _vote,
                        icon: Icon(
                          _proposal['voted'] == true
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                        ),
                        label: Text(
                          '${_proposal['voted'] == true ? '已支持' : '支持'} · ${_proposal['votes']}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _busy
                                ? null
                                : () async {
                                  await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder:
                                        (_) => _CommunityComposer(
                                          service: widget.service,
                                          proposal: _proposal['id'] as String,
                                        ),
                                  );
                                  if (mounted) await _load();
                                },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('参与讨论'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text('讨论', style: Theme.of(context).textTheme.titleMedium),
                  if (_comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('还没有人讨论。'),
                    ),
                  for (final c in _comments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c['mine'] == true ? '我' : '其他用户'),
                      subtitle: Text(c['body'] as String),
                      trailing:
                          c['moderation'] == 'pending'
                              ? const Text('审核中')
                              : null,
                    ),
                  if (_moreComments)
                    TextButton(
                      onPressed: _busy ? null : () => _load(append: true),
                      child: const Text('更多评论'),
                    ),
                ],
              ] else if (!_busy && _error == null)
                const Text('这条建议暂时看不了。'),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CommunityComposer extends StatefulWidget {
  const _CommunityComposer({required this.service, this.proposal});
  final FeedbackCommunityService service;
  final String? proposal;
  @override
  State<_CommunityComposer> createState() => _CommunityComposerState();
}

class _CommunityComposerState extends State<_CommunityComposer> {
  final _title = TextEditingController(), _body = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _id = FeedbackCommunityService.requestId();
  bool _busy = false, _uncertain = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.write(
        action: widget.proposal == null ? 'propose' : 'comment',
        id: _id,
        proposal: widget.proposal,
        title: _title.text.trim(),
        body: _body.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uncertain = e is CommunityException && e.uncertain;
          _error = e is CommunityException ? e.message : '提交未完成，请重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.proposal == null ? '提出建议' : '参与讨论'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('发布后其他人可以看到，请不要填写联系方式或个人隐私。'),
                const SizedBox(height: 16),
                if (widget.proposal == null)
                  TextFormField(
                    controller: _title,
                    enabled: !_busy && !_uncertain,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: '标题'),
                    validator:
                        (v) => (v?.trim().length ?? 0) < 3 ? '至少输入 3 个字' : null,
                  ),
                TextFormField(
                  controller: _body,
                  enabled: !_busy && !_uncertain,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: widget.proposal == null ? 4000 : 2000,
                  decoration: const InputDecoration(labelText: '内容'),
                  validator:
                      (v) =>
                          (v?.trim().length ?? 0) <
                                  (widget.proposal == null ? 3 : 1)
                              ? '请补充内容'
                              : null,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(_uncertain ? '关闭' : '取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy
                ? '提交中…'
                : _uncertain
                ? '重试'
                : '发布',
          ),
        ),
      ],
    ),
  );
}
