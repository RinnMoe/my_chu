import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/reliability_event.dart';
import '../../services/mail/mail_error.dart';
import '../../services/mail/mail_models.dart';
import '../../services/mail/mail_session.dart';
import '../../services/platform_environment.dart';
import '../../services/user_error_message.dart';
import '../../widgets/adaptive_action_sheet.dart';
import '../../widgets/adaptive_feedback.dart';
import 'mail_compose_page.dart';
import 'mail_detail_page.dart';
import 'mail_settings_page.dart';
import 'mail_setup_page.dart';
import 'mail_widgets.dart';

class MailPage extends StatefulWidget {
  final MailSession? session;

  const MailPage({super.key, this.session});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  late final MailSession _session = widget.session ?? MailSession.instance;

  MailSessionState _state = MailSessionState.initial;
  String? _folderPath;
  List<MailHeader> _headers = const [];
  int? _nextBeforeUid;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  MailHeader? _selected;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _state = _session.state.value;
    _session.state.addListener(_onStateChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _session.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() => _state = _session.state.value);
  }

  Future<void> _bootstrap() async {
    try {
      await _session.initialize();
      if (!mounted) return;
      setState(() => _state = _session.state.value);
      if (_state.isConfigured) {
        await _reload(refreshFolders: true);
      } else {
        setState(() => _loading = false);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '邮箱初始化失败，请稍后重试';
      });
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailSync,
      );
    }
  }

  Future<void> _reload({bool refreshFolders = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      List<MailFolder> folders;
      if (refreshFolders || _state.folders.isEmpty) {
        try {
          folders = await _session.refreshFolders();
        } on MailException catch (error) {
          if (_state.folders.isEmpty || !error.isRetryable) rethrow;
          folders = _state.folders;
        }
      } else {
        folders = _state.folders;
      }
      if (!mounted || generation != _generation) return;

      final folder = _resolveFolder(folders);
      if (folder == null) {
        setState(() {
          _headers = const [];
          _hasMore = false;
          _loading = false;
        });
        return;
      }
      final page = await _session.loadHeaders(folder.path, limit: 20);
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = _session.state.value;
        _folderPath = folder.path;
        _headers = page.items;
        _nextBeforeUid = page.nextBeforeUid;
        _hasMore = page.hasMore;
        _selected = null;
        _loading = false;
      });
    } on MailException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.userMessage;
        _loading = false;
      });
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailSync,
      );
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '邮箱加载失败，请稍后重试';
        _loading = false;
      });
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailSync,
      );
    }
  }

  MailFolder? _resolveFolder(List<MailFolder> folders) {
    if (folders.isEmpty) return null;
    final preferred = _folderPath;
    if (preferred != null) {
      for (final folder in folders) {
        if (folder.path == preferred) return folder;
      }
    }
    for (final folder in folders) {
      if (folder.role == MailFolderRole.inbox) return folder;
    }
    return folders.first;
  }

  Future<void> _loadMore() async {
    final folder = _folderPath;
    if (_loadingMore || !_hasMore || folder == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _session.loadHeaders(
        folder,
        beforeUid: _nextBeforeUid,
        limit: 20,
      );
      if (!mounted || generation != _generation || folder != _folderPath) {
        return;
      }
      setState(() {
        _headers = [..._headers, ...page.items];
        _nextBeforeUid = page.nextBeforeUid;
        _hasMore = page.hasMore;
      });
    } on MailException catch (error) {
      if (!mounted || generation != _generation) return;
      _toast(error.userMessage);
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      _toast('加载失败，请稍后重试');
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.mailSync,
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _selectFolder(MailFolder folder) async {
    if (_folderPath == folder.path) return;
    setState(() {
      _folderPath = folder.path;
      _headers = const [];
      _selected = null;
      _hasMore = false;
      _loadingMore = false;
    });
    await _reload();
  }

  Future<void> _openMessage(MailHeader header) async {
    final folder = _folderPath;
    if (folder == null) return;
    if (PlatformEnvironment.fromContext(context).windowClass.isExpanded) {
      setState(() => _selected = header);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => MailDetailPage(
              folderPath: folder,
              header: header,
              onMarkedRead: _setHeaderRead,
              session: _session,
              onSent: _handleSent,
            ),
      ),
    );
  }

  /// 写信页发送成功后刷新文件夹未读数与列表。
  void _handleSent() => unawaited(_reload(refreshFolders: true));

  void _setHeaderRead(int uid) {
    if (!mounted) return;
    setState(() {
      _headers = [
        for (final item in _headers)
          item.uid == uid ? item.copyWith(isRead: true) : item,
      ];
      final selected = _selected;
      if (selected != null && selected.uid == uid) {
        _selected = selected.copyWith(isRead: true);
      }
    });
  }

  Future<void> _showFolderSheet() async {
    final folders = _state.folders;
    if (folders.isEmpty) return;
    final selected = await showAdaptiveActionSheet<MailFolder>(
      context,
      title: '选择文件夹',
      options: [
        for (final folder in folders)
          AdaptiveActionSheetOption(
            label:
                folder.unread > 0
                    ? '${folder.name}（${folder.unread}）'
                    : folder.name,
            value: folder,
            selected: folder.path == _folderPath,
          ),
      ],
    );
    if (selected == null) return;
    if (!mounted) return;
    await _selectFolder(selected);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MailSettingsPage(session: _session)),
    );
    if (!mounted) return;
    setState(() => _state = _session.state.value);
    if (_state.isConfigured) {
      await _reload(refreshFolders: true);
    } else {
      setState(() {
        _headers = const [];
        _selected = null;
        _folderPath = null;
      });
    }
  }

  Future<void> _openCompose() async {
    final result = await Navigator.of(context).push<MailSendResult>(
      MaterialPageRoute(builder: (_) => MailComposePage(session: _session)),
    );
    if (!mounted || result == null) return;
    _toast(result.sentCopyStored ? '已发送' : '已发送，未保存到已发送文件夹');
    await _reload(refreshFolders: true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final windowClass = PlatformEnvironment.fromContext(context).windowClass;
    final wide = windowClass.isAtLeastMedium;
    final expanded = windowClass.isExpanded;
    final folder = _currentFolder;

    return Scaffold(
      appBar: AppBar(
        title: Text(folder?.name ?? '校园邮箱'),
        actions: [
          if (expanded && _state.isConfigured)
            IconButton(
              tooltip: '写信',
              onPressed: () => unawaited(_openCompose()),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (!wide && _state.isConfigured)
            IconButton(
              tooltip: '文件夹',
              onPressed: _showFolderSheet,
              icon: const Icon(Icons.folder_outlined),
            ),
          if (_state.isConfigured)
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : () => _reload(refreshFolders: true),
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton:
          _state.isConfigured && !expanded
              ? FloatingActionButton.extended(
                onPressed: () => unawaited(_openCompose()),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('写信'),
              )
              : null,
      body: _buildBody(wide, expanded),
    );
  }

  MailFolder? get _currentFolder {
    for (final folder in _state.folders) {
      if (folder.path == _folderPath) return folder;
    }
    return _state.inbox;
  }

  Widget _buildBody(bool wide, bool expanded) {
    if (_loading) {
      return const AdaptiveLoadingState(label: '正在收取邮件…');
    }
    if (!_state.isConfigured) {
      return MailSetupView(
        initialConfig: _state.config,
        onSaved: () => unawaited(_bootstrap()),
      );
    }
    if (_error != null) {
      return AdaptiveErrorState(
        title: '邮箱加载失败',
        message: _error,
        onRetry: () => _reload(refreshFolders: true),
      );
    }

    final listPane = _buildListPane();
    if (!wide) return listPane;

    return Row(
      children: [
        SizedBox(width: 200, child: _buildFolderPane()),
        const VerticalDivider(width: 1),
        Expanded(child: listPane),
        if (expanded) ...[
          const VerticalDivider(width: 1),
          SizedBox(width: 340, child: _buildDetailPane()),
        ],
      ],
    );
  }

  Widget _buildFolderPane() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            '文件夹',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final folder in _state.folders)
          _FolderTile(
            folder: folder,
            selected: folder.path == _folderPath,
            onTap: () => _selectFolder(folder),
          ),
      ],
    );
  }

  Widget _buildListPane() {
    final theme = Theme.of(context);
    final unread = _headers.where((header) => !header.isRead).length;

    return RefreshIndicator(
      onRefresh: () => _reload(refreshFolders: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _headers.length + 1 + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_headers.isEmpty) {
              return const MailEmptyCard(
                icon: Icons.inbox_outlined,
                text: '还没有邮件',
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                unread > 0 ? '$unread 封未读' : '共 ${_headers.length} 封',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          final itemIndex = index - 1;
          if (itemIndex >= _headers.length) {
            return Center(
              child:
                  _loadingMore
                      ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                      : OutlinedButton(
                        onPressed: _loadMore,
                        child: const Text('加载更多'),
                      ),
            );
          }
          final header = _headers[itemIndex];
          return MailListTile(
            header: header,
            selected: _selected?.uid == header.uid,
            onTap: () => _openMessage(header),
          );
        },
      ),
    );
  }

  Widget _buildDetailPane() {
    final folder = _folderPath;
    final selected = _selected;
    if (folder == null || selected == null) {
      return Center(
        child: Text(
          '选择一封邮件查看',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return MailDetailView(
      key: ValueKey('${folder}_${selected.uid}'),
      folderPath: folder,
      header: selected,
      session: _session,
      onMarkedRead: _setHeaderRead,
      onSent: _handleSent,
    );
  }
}

class _FolderTile extends StatelessWidget {
  final MailFolder folder;
  final bool selected;
  final VoidCallback onTap;

  const _FolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  _iconFor(folder.role),
                  size: 20,
                  color:
                      selected
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color:
                          selected
                              ? colors.onSecondaryContainer
                              : colors.onSurface,
                    ),
                  ),
                ),
                if (folder.unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          selected ? colors.primary : colors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${folder.unread}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            selected
                                ? colors.onPrimary
                                : colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(MailFolderRole role) => switch (role) {
    MailFolderRole.inbox => Icons.inbox_outlined,
    MailFolderRole.sent => Icons.send_outlined,
    MailFolderRole.drafts => Icons.drafts_outlined,
    MailFolderRole.trash => Icons.delete_outline,
    MailFolderRole.junk => Icons.report_gmailerrorred_outlined,
    MailFolderRole.archive => Icons.archive_outlined,
    MailFolderRole.other => Icons.folder_outlined,
  };
}
