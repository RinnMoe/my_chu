import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'channel_resources_models.dart';
import 'channel_resources_service.dart';
import 'channel_resources_widgets.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class ChannelResourcesProfilePage extends StatefulWidget {
  final ChannelResourcesService service;
  final ValueListenable<int>? pointsInvalidation;

  const ChannelResourcesProfilePage({
    super.key,
    required this.service,
    this.pointsInvalidation,
  });

  @override
  State<ChannelResourcesProfilePage> createState() =>
      _ChannelResourcesProfilePageState();
}

class _ChannelResourcesProfilePageState
    extends State<ChannelResourcesProfilePage> {
  bool _checkingIn = false;
  int? _points;
  int _pointsRequestGeneration = 0;
  int? _lastPointsInvalidation;

  @override
  void initState() {
    super.initState();
    final invalidation = widget.pointsInvalidation;
    if (invalidation != null) {
      _lastPointsInvalidation = invalidation.value;
      invalidation.addListener(_handlePointsInvalidated);
    }
    _loadPoints();
  }

  @override
  void didUpdateWidget(ChannelResourcesProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pointsInvalidation == widget.pointsInvalidation) return;
    oldWidget.pointsInvalidation?.removeListener(_handlePointsInvalidated);
    final invalidation = widget.pointsInvalidation;
    _lastPointsInvalidation = invalidation?.value;
    invalidation?.addListener(_handlePointsInvalidated);
    _loadPoints();
  }

  @override
  void dispose() {
    widget.pointsInvalidation?.removeListener(_handlePointsInvalidated);
    super.dispose();
  }

  void _handlePointsInvalidated() {
    final invalidation = widget.pointsInvalidation;
    if (invalidation == null || invalidation.value == _lastPointsInvalidation) {
      return;
    }
    _lastPointsInvalidation = invalidation.value;
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final requestGeneration = ++_pointsRequestGeneration;
    int? points;
    try {
      points = await widget.service.loadCurrentPoints();
    } on Object {
      points = null;
    }
    if (mounted && requestGeneration == _pointsRequestGeneration) {
      setState(() => _points = points);
    }
  }

  Future<void> _checkIn() async {
    if (_checkingIn) return;
    setState(() => _checkingIn = true);
    try {
      final result = await widget.service.checkIn();
      if (!mounted) return;
      if (!result.alreadyCheckedIn) {
        await _loadPoints();
        if (!mounted) return;
      }
      showChannelResourcesSnack(
        context,
        result.alreadyCheckedIn
            ? '今天已经签到过了。'
            : '签到成功，获得 ${result.rewardPoints} 积分。',
      );
    } on ChannelAccountException catch (error) {
      if (mounted) {
        showChannelResourcesSnack(context, error.userMessage);
      }
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.message);
    } on Object {
      if (mounted) showChannelResourcesSnack(context, '签到失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  Future<void> _submitResource() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChannelResourcesSubmitResourcePage(service: widget.service),
      ),
    );
  }

  Future<void> _contactAdmin() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChannelResourcesContactAdminPage(service: widget.service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.service.user!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user.nickname),
            subtitle: _points == null ? null : Text('积分：$_points'),
            isThreeLine: false,
          ),
        ),
        const SizedBox(height: 12),
        ChannelResourcesActionTile(
          icon: Icons.task_alt_outlined,
          title: '每日签到',
          subtitle: '领取资料站积分',
          onTap: _checkingIn ? null : _checkIn,
          trailing:
              _checkingIn
                  ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : null,
        ),
        const SizedBox(height: 4),
        ChannelResourcesActionTile(
          icon: Icons.upload_file_outlined,
          title: '分享资料',
          onTap: _submitResource,
        ),
        const SizedBox(height: 4),
        ChannelResourcesActionTile(
          icon: Icons.help_outline,
          title: '联系管理员',
          onTap: _contactAdmin,
        ),
      ],
    );
  }
}

class ChannelResourcesSubmitResourcePage extends StatefulWidget {
  final ChannelResourcesService service;

  const ChannelResourcesSubmitResourcePage({super.key, required this.service});

  @override
  State<ChannelResourcesSubmitResourcePage> createState() =>
      _ChannelResourcesSubmitResourcePageState();
}

class _ChannelResourcesSubmitResourcePageState
    extends State<ChannelResourcesSubmitResourcePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _link = TextEditingController();
  final _points = TextEditingController(text: '0');
  List<ChannelTag> _availableTags = const [];
  Set<String> _selectedTags = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    _points.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await widget.service.loadTags();
      if (mounted) setState(() => _availableTags = tags);
    } on Object {
      // Tag selection is optional; the form remains usable if this read fails.
    }
  }

  Future<void> _chooseTags() async {
    if (_availableTags.isEmpty) {
      showChannelResourcesSnack(context, '暂时没有可选资料标签。');
      return;
    }
    final selected = Set<String>.of(_selectedTags);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                        children: [
                          Text(
                            '选择资料标签',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final tag in _availableTags)
                                  CheckboxListTile(
                                    value: selected.contains(tag.id),
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(tag.name),
                                    onChanged: (value) {
                                      setSheetState(() {
                                        if (value == true) {
                                          selected.add(tag.id);
                                        } else {
                                          selected.remove(tag.id);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  () => Navigator.pop(sheetContext, selected),
                              child: const Text('完成'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
    );
    if (result != null && mounted) setState(() => _selectedTags = result);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.submitResource(
        name: _name.text,
        link: _link.text,
        points: int.tryParse(_points.text.trim()) ?? 0,
        tags: _selectedTags.toList(growable: false),
      );
      if (mounted) {
        showChannelResourcesSnack(context, '资料已提交，等待管理员审核。');
        Navigator.pop(context);
      }
    } on ChannelAccountException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '资料提交失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: Text(channelResourcesSubPageTitle('分享资料'))),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '资料名称'),
              validator:
                  (value) =>
                      value == null || value.trim().isEmpty ? '请输入资料名称。' : null,
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '资料链接'),
              validator: (value) {
                final uri = Uri.tryParse(value?.trim() ?? '');
                if (uri == null ||
                    (uri.scheme != 'http' && uri.scheme != 'https') ||
                    uri.host.isEmpty) {
                  return '请输入有效的 HTTP(S) 链接。';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _points,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '兑换所需积分'),
              validator:
                  (value) =>
                      int.tryParse(value?.trim() ?? '') == null
                          ? '请输入数字。'
                          : null,
            ),
            const SizedBox(height: 22),
            FormField<void>(
              builder:
                  (field) => InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '资料标签',
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: InkWell(
                      onTap: _busy ? null : _chooseTags,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedTags.isEmpty
                                  ? '请选择标签（可多选）'
                                  : _availableTags
                                      .where(
                                        (tag) => _selectedTags.contains(tag.id),
                                      )
                                      .map((tag) => tag.name)
                                      .join('、'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child:
                  _busy
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('提交审核'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChannelResourcesContactAdminPage extends StatefulWidget {
  final ChannelResourcesService service;

  const ChannelResourcesContactAdminPage({super.key, required this.service});

  @override
  State<ChannelResourcesContactAdminPage> createState() =>
      _ChannelResourcesContactAdminPageState();
}

class _ChannelResourcesContactAdminPageState
    extends State<ChannelResourcesContactAdminPage> {
  final _formKey = GlobalKey<FormState>();
  final _content = TextEditingController();
  List<ChannelAdmin> _admins = const [];
  String? _selectedAdminId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admins = await widget.service.loadAdmins();
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _selectedAdminId = admins.isEmpty ? null : admins.first.id;
        _loading = false;
      });
    } on ChannelAccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.userMessage;
      });
    } on ChannelResourcesServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '管理员列表加载失败，请稍后重试。';
      });
    }
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    final adminId = _selectedAdminId;
    if (adminId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.sendMessageToAdmin(
        adminId: adminId,
        content: _content.text.trim(),
      );
      if (!mounted) return;
      _content.clear();
      showChannelResourcesSnack(context, '发送成功');
    } on ChannelAccountException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.message);
    } on Object {
      if (mounted) showChannelResourcesSnack(context, '发送失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMessages() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelResourcesMessagesPage(service: widget.service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: Text(channelResourcesSubPageTitle('联系管理员'))),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _admins.isEmpty) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: Text(channelResourcesSubPageTitle('联系管理员'))),
        ),
        body: ChannelResourcesErrorView(message: _error!, onRetry: _loadAdmins),
      );
    }
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: Text(channelResourcesSubPageTitle('联系管理员')),
          actions: [
            IconButton(
              tooltip: '系统消息',
              onPressed: _openMessages,
              icon: const Icon(Icons.inbox_outlined),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 32),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedAdminId,
              decoration: const InputDecoration(labelText: '管理员'),
              items: [
                for (final admin in _admins)
                  DropdownMenuItem(
                    value: admin.id,
                    child: Text(admin.nickname),
                  ),
              ],
              onChanged:
                  _busy
                      ? null
                      : (value) => setState(() => _selectedAdminId = value),
              validator: (value) => value == null ? '请选择管理员。' : null,
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _content,
              minLines: 4,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(labelText: '消息内容'),
              validator:
                  (value) =>
                      value == null || value.trim().isEmpty ? '请输入消息内容。' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _send,
              child:
                  _busy
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChannelResourcesMessagesPage extends StatefulWidget {
  final ChannelResourcesService service;

  const ChannelResourcesMessagesPage({super.key, required this.service});

  @override
  State<ChannelResourcesMessagesPage> createState() =>
      _ChannelResourcesMessagesPageState();
}

class _ChannelResourcesMessagesPageState
    extends State<ChannelResourcesMessagesPage> {
  List<ChannelMessage> _messages = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.service.loadMessages();
      if (mounted) {
        setState(() {
          _messages = messages;
          _loading = false;
        });
      }
    } on ChannelAccountException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.userMessage;
        });
      }
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '消息加载失败，请稍后重试。';
        });
      }
    }
  }

  Future<void> _delete(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.deleteMessage(id);
      await _load();
    } on ChannelAccountException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    if (_busy || _messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('清空消息？'),
            content: const Text('这会删除当前账号的全部消息。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('清空'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.service.deleteAllMessages();
      await _load();
    } on ChannelAccountException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: Text(channelResourcesSubPageTitle('系统消息'))),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: Text(channelResourcesSubPageTitle('系统消息'))),
        ),
        body: ChannelResourcesErrorView(message: _error!, onRetry: _load),
      );
    }
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: Text(channelResourcesSubPageTitle('系统消息')),
          actions: [
            IconButton(
              tooltip: '清空消息',
              onPressed: _busy ? null : _deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child:
            _messages.isEmpty
                ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 180),
                    ChannelResourcesEmptyView(
                      icon: Icons.forum_outlined,
                      message: '还没有消息。',
                    ),
                  ],
                )
                : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        title: Text(message.content),
                        subtitle:
                            message.createdAt.isEmpty
                                ? null
                                : Text(message.createdAt),
                        trailing: IconButton(
                          tooltip: '删除',
                          onPressed: _busy ? null : () => _delete(message.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}

class ChannelResourcesReviewPage extends StatefulWidget {
  final ChannelResourcesService service;

  const ChannelResourcesReviewPage({super.key, required this.service});

  @override
  State<ChannelResourcesReviewPage> createState() =>
      _ChannelResourcesReviewPageState();
}

class _ChannelResourcesReviewPageState
    extends State<ChannelResourcesReviewPage> {
  ChannelReviewStats? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await widget.service.loadReviewStats();
      if (mounted) setState(() => _stats = stats);
    } on ChannelAccountException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '审核记录加载失败，请稍后重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _error == null) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: Text(channelResourcesSubPageTitle('审核记录'))),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_stats == null) {
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: Text(channelResourcesSubPageTitle('审核记录'))),
        ),
        body: ChannelResourcesErrorView(message: _error!, onRetry: _load),
      );
    }
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: Text(channelResourcesSubPageTitle('审核记录'))),
      ),
      body:
          _stats!.counts.isEmpty
              ? const ChannelResourcesEmptyView(
                icon: Icons.fact_check_outlined,
                message: '暂时没有审核记录。',
              )
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final entry in _stats!.counts.entries)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(entry.key),
                        trailing: Text('${entry.value} 条'),
                      ),
                    ),
                ],
              ),
    );
  }
}
