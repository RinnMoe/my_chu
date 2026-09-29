import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/platform_environment.dart';
import '../../services/logger_service.dart';
import '../../services/user_error_message.dart';
import 'mobile_campus_notice_models.dart';
import 'mobile_campus_notice_service.dart';
import 'portal_notices_models.dart';
import 'portal_notice_detail_page.dart';
import 'portal_notice_presentation.dart';

export 'portal_notice_detail_page.dart'
    show PortalNoticeDetailLoader, PortalNoticeDetailPage;

/// 通知公告内容面板：通知中心“公告”Tab 的唯一列表载体。
class PortalNoticesPanel extends StatefulWidget {
  final List<PortalNotice>? initialNotices;
  final PortalNoticesLoader? loader;
  final Future<List<MobileCampusNoticeSearchGroup>> Function(String)?
  searchGroupsLoader;

  const PortalNoticesPanel({
    super.key,
    this.initialNotices,
    this.loader,
    this.searchGroupsLoader,
  });

  @override
  State<PortalNoticesPanel> createState() => PortalNoticesPanelState();
}

class PortalNoticesPanelState extends State<PortalNoticesPanel> {
  static const _pageSize = 10;

  final MobileCampusNoticeService _service = MobileCampusNoticeService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<PortalNotice> _notices = const [];
  List<MobileCampusNoticeColumn> _columns = const [];
  List<MobileCampusNoticeSearchGroup> _searchGroups = const [];
  String? _activeTagId;
  String? _activeTagName;
  String _query = '';
  String? _error;
  int _pageNumber = 0;
  int _requestGeneration = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _searchLoading = false;
  PortalNotice? _selectedNotice;

  bool get _isBrowseMode => _activeTagId == null && _query.isEmpty;
  bool get _isSearchGroupMode => _activeTagId == null && _query.isNotEmpty;
  bool get _isTagMode => _activeTagId != null;

  @override
  void initState() {
    super.initState();
    final initialNotices = widget.initialNotices;
    if (initialNotices != null) {
      _notices = initialNotices;
      _loading = false;
      _pageNumber = 1;
      _hasMore = _notices.length == _pageSize;
    } else {
      unawaited(_refresh());
    }
    unawaited(_loadColumns());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> refresh() => _retryCurrentMode();

  Future<void> _retryCurrentMode() {
    if (_isSearchGroupMode) return _loadSearchGroups();
    return _refresh(forceNotices: true);
  }

  Future<void> _refresh({bool forceNotices = false}) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _searchLoading = false;
      _error = null;
    });
    try {
      final page = await _loadPage(1, forceNotices: forceNotices);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _notices = page.items;
        _pageNumber = 1;
        _hasMore = _hasMoreFor(page);
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      logUserFacingError(UserErrorContext.network, error, operation: 'notices');
      setState(() => _error = userFacingError(UserErrorContext.network, error));
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final generation = _requestGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await _loadPage(_pageNumber + 1);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _notices = [..._notices, ...page.items];
        _pageNumber += 1;
        _hasMore = _hasMoreFor(page);
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      logUserFacingError(UserErrorContext.network, error, operation: 'notices');
      _showMessage('加载更多失败，请稍后重试');
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<PortalNoticePage> _loadPage(int offset, {bool forceNotices = false}) {
    if (offset == 1 && _isBrowseMode) {
      final injected = widget.loader;
      final firstPage =
          injected == null
              ? _service.fetchNotices(force: forceNotices)
              : injected();
      return firstPage.then(
        (items) => PortalNoticePage(
          items: items,
          totalSize: 0,
          pageNumber: offset,
          pageSize: _pageSize,
        ),
      );
    }
    return _service.fetchListPage(
      offset: offset,
      tagId: _activeTagId,
      theme: _query,
      limit: _pageSize,
    );
  }

  bool _hasMoreFor(PortalNoticePage page) {
    return page.hasMore;
  }

  Future<void> _loadColumns() async {
    try {
      final columns = await _service.fetchColumns();
      if (!mounted) return;
      setState(() => _columns = columns);
    } catch (error) {
      // 栏目摘要加载失败不阻塞公告列表。
      if (!mounted) return;
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'portal.notices.columns.failed',
        message: '公告栏目加载失败',
        error: error,
        domain: 'portal',
        fields: const {'stage': 'columns'},
      );
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    if (query == _query) return;
    _searchDebounce?.cancel();
    ++_requestGeneration;
    setState(() {
      _query = query;
      _activeTagId = null;
      _activeTagName = null;
      _resetListResultState();
      _searchGroups = const [];
      _loading = false;
      _loadingMore = false;
      _searchLoading = query.isNotEmpty;
    });
    if (query.isEmpty) {
      unawaited(_refresh());
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      _loadSearchGroups,
    );
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();
    _loadSearchGroups();
  }

  Future<void> _loadSearchGroups() async {
    final query = _query.trim();
    if (!_isSearchGroupMode) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = false;
      _loadingMore = false;
      _searchLoading = true;
      _error = null;
      _searchGroups = const [];
    });
    try {
      final groups =
          await (widget.searchGroupsLoader?.call(query) ??
              _service.searchGroups(query));
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _searchGroups = groups;
        _searchLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      logUserFacingError(UserErrorContext.network, error, operation: 'notices');
      setState(() {
        _searchGroups = const [];
        _searchLoading = false;
        _error = userFacingError(UserErrorContext.network, error);
      });
    }
  }

  void _openSearchGroup(MobileCampusNoticeSearchGroup group) {
    _searchDebounce?.cancel();
    setState(() {
      _activeTagId = group.tagId;
      _activeTagName = group.tagName;
      _resetListResultState();
      _searchLoading = false;
    });
    unawaited(_refresh());
  }

  void _resetListResultState() {
    _notices = const [];
    _pageNumber = 0;
    _hasMore = true;
    _error = null;
    _selectedNotice = null;
  }

  void _backToSearchOrBrowse() {
    _searchDebounce?.cancel();
    setState(() {
      _activeTagId = null;
      _activeTagName = null;
      _resetListResultState();
      _loading = false;
      _loadingMore = false;
      _searchLoading = false;
    });
    if (_isSearchGroupMode) {
      unawaited(_loadSearchGroups());
    } else {
      unawaited(_refresh());
    }
  }

  void _selectColumn(String? tagId) {
    setState(() {
      _activeTagId = tagId;
      if (tagId == null) {
        _activeTagName = null;
      } else {
        final matches = _columns.where((column) => column.tagId == tagId);
        _activeTagName = matches.isEmpty ? null : matches.first.tagName;
      }
      _resetListResultState();
      _searchLoading = false;
    });
    unawaited(_refresh());
  }

  Future<void> _openNotice(PortalNotice notice) async {
    if (notice.id.isEmpty) {
      _showMessage('该公告暂无详情页面');
      return;
    }

    final environment = PlatformEnvironment.fromContext(context);
    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded) {
      setState(() => _selectedNotice = notice);
      return;
    }
    final route = MaterialPageRoute<MobileCampusNoticeDetail>(
      builder:
          (_) => PortalNoticeDetailPage(
            messageId: notice.id,
            tagId: notice.tagId,
            title: notice.title,
          ),
    );
    final detail = await Navigator.push<MobileCampusNoticeDetail>(
      context,
      route,
    );
    if (!mounted || detail == null) return;
    setState(() {
      _notices = [
        for (final item in _notices)
          if (item.id == detail.messageId)
            _withRead(item, detail.read)
          else
            item,
      ];
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  PortalNotice _withRead(PortalNotice notice, bool read) => PortalNotice(
    id: notice.id,
    title: notice.title,
    department: notice.department,
    publishedAt: notice.publishedAt,
    detailUrl: notice.detailUrl,
    type: notice.type,
    column: notice.column,
    tagId: notice.tagId,
    pinned: notice.pinned,
    read: read,
  );

  void _applyRegularDetail(MobileCampusNoticeDetail detail) {
    if (!mounted) return;
    setState(() {
      _notices = [
        for (final item in _notices)
          if (item.id == detail.messageId)
            _withRead(item, detail.read)
          else
            item,
      ];
      final selected = _selectedNotice;
      if (selected?.id == detail.messageId) {
        _selectedNotice = _withRead(selected!, detail.read);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _notices.isEmpty && !_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _notices.isEmpty) {
      return PortalNoticeFullPageError(
        message: _error!,
        onRetry: _retryCurrentMode,
      );
    }

    final environment = PlatformEnvironment.fromContext(context);

    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded) {
      return _buildMaterialTabletBody();
    }
    return _buildMaterialBody();
  }

  Widget _buildMaterialTabletBody() {
    final selected = _selectedNotice;
    return Row(
      children: [
        SizedBox(
          key: const ValueKey('material-portal-notices-master'),
          width: 340,
          child: _buildMaterialBody(),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child:
              selected == null
                  ? const KeyedSubtree(
                    key: ValueKey('material-portal-notices-detail'),
                    child: _MaterialNoticeDetailPlaceholder(),
                  )
                  : PortalNoticeDetailPage(
                    key: ValueKey(
                      'material-portal-notice-detail-${selected.id}',
                    ),
                    messageId: selected.id,
                    tagId: selected.tagId,
                    title: selected.title,

                    embedded: true,
                    onLoaded: _applyRegularDetail,
                  ),
        ),
      ],
    );
  }

  Widget _buildMaterialBody() {
    final showBrowse = _isBrowseMode;
    final showSearchGroups = _isSearchGroupMode;
    final showTagList = _isTagMode;
    return RefreshIndicator(
      onRefresh: _retryCurrentMode,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _NoticeSearchField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onSubmitted: _submitSearch,
            onClear: () {
              _searchController.clear();
              _onSearchChanged('');
            },
          ),
          const SizedBox(height: 8),
          if (_activeTagName != null && _activeTagName!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.filter_alt_outlined, size: 16),
                label: Text(
                  _query.isEmpty
                      ? _activeTagName!
                      : '$_activeTagName · $_query',
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: _backToSearchOrBrowse,
                onDeleted: _backToSearchOrBrowse,
              ),
            ),
          if (showBrowse)
            _NoticeFilters(
              columns: _columns,
              selectedTagId: _activeTagId,
              onColumnChanged: _selectColumn,
            ),
          if (_searchLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (showSearchGroups) ...[
            if (_searchGroups.isNotEmpty)
              _SearchGroupList(groups: _searchGroups, onTap: _openSearchGroup)
            else if (!_searchLoading && _error == null)
              const _EmptyCard(
                icon: Icons.search_off_outlined,
                text: '没有找到匹配的公告',
              ),
          ] else ...[
            const SizedBox(height: 6),
            if (_loading && _notices.isNotEmpty) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 6),
              Text(
                '正在刷新…',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (!showTagList || _notices.isEmpty) ...[
              Text(
                '已显示 ${_notices.length} 条通知',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_notices.isEmpty && !_loading && _error == null)
              const _EmptyCard(
                icon: Icons.search_off_outlined,
                text: '没有符合条件的通知',
              )
            else if (_notices.isNotEmpty)
              _NoticeList(notices: _notices, onNoticeTap: _openNotice),
            const SizedBox(height: 16),
            if (_hasMore && _notices.isNotEmpty)
              Center(
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                ),
              )
            else if (!_hasMore && _notices.isNotEmpty)
              Center(
                child: Text(
                  '已显示全部 ${_notices.length} 条通知',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NoticeSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _NoticeSearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: '搜索公告标题或部门',
        prefixIcon: const Icon(Icons.search),
        suffixIcon:
            controller.text.isEmpty
                ? null
                : IconButton(
                  tooltip: '清空搜索',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }
}

class _NoticeFilters extends StatelessWidget {
  final List<MobileCampusNoticeColumn> columns;
  final String? selectedTagId;
  final ValueChanged<String?> onColumnChanged;

  const _NoticeFilters({
    required this.columns,
    required this.selectedTagId,
    required this.onColumnChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (columns.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            initialValue: selectedTagId,
            isDense: true,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('全部栏目')),
              for (final column in columns)
                DropdownMenuItem<String?>(
                  value: column.tagId,
                  child: Text(column.tagName, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onColumnChanged,
          ),
          const SizedBox(height: 8),
        ],
        Divider(height: 20, color: colors.outlineVariant),
      ],
    );
  }
}

class _SearchGroupList extends StatelessWidget {
  final List<MobileCampusNoticeSearchGroup> groups;
  final ValueChanged<MobileCampusNoticeSearchGroup> onTap;

  const _SearchGroupList({required this.groups, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var index = 0; index < groups.length; index++) ...[
            InkWell(
              onTap: () => onTap(groups[index]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.apartment_outlined, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groups[index].tagName,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            groups[index].latestTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${groups[index].count} 条',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (index != groups.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _NoticeList extends StatelessWidget {
  final List<PortalNotice> notices;
  final ValueChanged<PortalNotice> onNoticeTap;

  const _NoticeList({required this.notices, required this.onNoticeTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var index = 0; index < notices.length; index++) ...[
            InkWell(
              onTap: () => onNoticeTap(notices[index]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        notices[index].read
                            ? Icons.mark_email_read_outlined
                            : Icons.campaign_outlined,
                        size: 20,
                        color:
                            notices[index].read
                                ? colors.onSurfaceVariant
                                : colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notices[index].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight:
                                  notices[index].pinned
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (notices[index].pinned ||
                              _publisher(notices[index]).isNotEmpty)
                            Row(
                              children: [
                                if (notices[index].pinned) ...[
                                  Icon(
                                    Icons.push_pin_outlined,
                                    size: 14,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '置顶',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    _publisher(notices[index]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (notices[index].publishedAt.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              notices[index].publishedAt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (index != notices.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  String _publisher(PortalNotice notice) {
    final column = notice.column.isEmpty ? notice.department : notice.column;
    return column;
  }
}

class _MaterialNoticeDetailPlaceholder extends StatelessWidget {
  const _MaterialNoticeDetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 40, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              '选择一条公告查看详情',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colors.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
