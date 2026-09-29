import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../capabilities/channel_resources_link_capability.dart';
import '../../services/channel_resources_session_service.dart';
import 'channel_resources_models.dart';
import 'channel_resources_service.dart';
import 'channel_resources_widgets.dart';

class ChannelResourcesResourcesPage extends StatefulWidget {
  final ChannelResourcesService service;
  final VoidCallback? onPointsChanged;
  final ValueListenable<bool>? searchVisibility;

  const ChannelResourcesResourcesPage({
    super.key,
    required this.service,
    this.onPointsChanged,
    this.searchVisibility,
  });

  @override
  State<ChannelResourcesResourcesPage> createState() =>
      _ChannelResourcesResourcesPageState();
}

class _ChannelResourcesResourcesPageState
    extends State<ChannelResourcesResourcesPage> {
  final _searchController = TextEditingController();
  final _linkCapability = const ChannelResourcesLinkCapability();
  final _purchasing = <String>{};
  final _opening = <String>{};

  ChannelResourcePage? _page;
  List<ChannelTag> _tags = const [];
  List<ChannelAnnouncement> _announcements = const [];
  List<ChannelLink> _links = const [];
  String _selectedTagName = '';
  String _sort = 'downloads';
  int _pageNumber = 1;
  bool _loading = true;
  String? _error;
  bool _searchVisible = false;

  @override
  void initState() {
    super.initState();
    _searchVisible = widget.searchVisibility?.value ?? false;
    widget.searchVisibility?.addListener(_handleSearchVisibilityChanged);
    _load();
  }

  @override
  void didUpdateWidget(ChannelResourcesResourcesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchVisibility != widget.searchVisibility) {
      oldWidget.searchVisibility?.removeListener(
        _handleSearchVisibilityChanged,
      );
      _searchVisible = widget.searchVisibility?.value ?? false;
      widget.searchVisibility?.addListener(_handleSearchVisibilityChanged);
    }
  }

  @override
  void dispose() {
    widget.searchVisibility?.removeListener(_handleSearchVisibilityChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchVisibilityChanged() {
    final visible = widget.searchVisibility?.value ?? false;
    if (mounted && visible != _searchVisible) {
      setState(() => _searchVisible = visible);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resources = widget.service.loadResources(
        search: _searchController.text,
        tags: _selectedTagName,
        page: _pageNumber,
        sortBy: _sort,
      );
      final tags = widget.service.loadTags();
      final announcements = widget.service.loadAnnouncements();
      final links = widget.service.loadLinks();
      final values = await Future.wait<Object>([
        resources,
        tags,
        announcements,
        links,
      ]);
      if (!mounted) return;
      setState(() {
        _page = values[0] as ChannelResourcePage;
        _tags = values[1] as List<ChannelTag>;
        _announcements = values[2] as List<ChannelAnnouncement>;
        _links = values[3] as List<ChannelLink>;
        _loading = false;
      });
    } on ChannelResourcesSessionException catch (error) {
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
        _error = '资料加载失败，请稍后重试。';
      });
    }
  }

  Future<void> _loadResources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.loadResources(
        search: _searchController.text,
        tags: _selectedTagName,
        page: _pageNumber,
        sortBy: _sort,
      );
      if (mounted) {
        setState(() {
          _page = page;
          _loading = false;
        });
      }
    } on ChannelResourcesSessionException catch (error) {
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
          _error = '资料加载失败，请稍后重试。';
        });
      }
    }
  }

  Future<void> _purchase(ChannelResource resource) async {
    if (_purchasing.contains(resource.id)) return;
    setState(() => _purchasing.add(resource.id));
    try {
      final purchased = await widget.service.purchaseResource(resource.id);
      if (!mounted) return;
      if (purchased) widget.onPointsChanged?.call();
      showChannelResourcesSnack(
        context,
        purchased ? '已兑换资料。' : '这份资料已经在你的资料库中。',
      );
      await _loadResources();
    } on ChannelResourcesSessionException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.message);
    } on Object {
      if (mounted) showChannelResourcesSnack(context, '兑换失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _purchasing.remove(resource.id));
    }
  }

  Future<void> _openResource(ChannelResource resource) async {
    if (_opening.contains(resource.id)) return;
    setState(() => _opening.add(resource.id));
    try {
      final target = await widget.service.resolveResource(resource);
      final opened = await _linkCapability.open(target);
      if (!opened && mounted) {
        showChannelResourcesSnack(context, '无法打开资料链接。');
      }
    } on ChannelResourcesSessionException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.userMessage);
    } on ChannelResourcesServiceException catch (error) {
      if (mounted) showChannelResourcesSnack(context, error.message);
    } on Object {
      if (mounted) showChannelResourcesSnack(context, '资料暂时无法打开，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() => _opening.remove(resource.id));
      }
    }
  }

  Future<void> _openAnnouncement(ChannelAnnouncement announcement) async {
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(announcement.title),
            content: SingleChildScrollView(
              child: ChannelMarkdownText(
                markdown:
                    announcement.content.isEmpty
                        ? '暂无公告正文。'
                        : announcement.content,
                linkCapability: _linkCapability,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _page == null) {
      return ChannelResourcesErrorView(message: _error!, onRetry: _load);
    }
    final page = _page;
    if (page == null) {
      return ChannelResourcesEmptyView(
        icon: Icons.folder_off_outlined,
        message: '暂时没有资料。',
        onRetry: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_announcements.isNotEmpty) _buildAnnouncements(),
          if (_links.isNotEmpty) ...[const SizedBox(height: 12), _buildLinks()],
          const SizedBox(height: 12),
          _buildSearchControls(),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (page.resources.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: ChannelResourcesEmptyView(
                icon: Icons.search_off,
                message: '没有找到匹配的资料。',
                onRetry: _loadResources,
              ),
            )
          else
            for (final resource in page.resources) ...[
              _buildResourceCard(resource),
              const SizedBox(height: 10),
            ],
          if (page.totalPages > 1) _buildPagination(page),
        ],
      ),
    );
  }

  Widget _buildAnnouncements() => ChannelResourcesSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(icon: Icons.campaign_outlined, title: '公告'),
        const SizedBox(height: 8),
        for (var index = 0; index < _announcements.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              _announcements[index].title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _announcements[index].publishedAt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openAnnouncement(_announcements[index]),
          ),
      ],
    ),
  );

  Widget _buildLinks() => ChannelResourcesSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(icon: Icons.link_outlined, title: '常用链接'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in _links)
              ActionChip(
                avatar: const Icon(Icons.open_in_new, size: 16),
                label: Text(link.name),
                onPressed: () async {
                  final uri = Uri.tryParse(link.url);
                  if (uri == null || !await _linkCapability.open(uri)) {
                    if (mounted) showChannelResourcesSnack(context, '无法打开链接。');
                  }
                },
              ),
          ],
        ),
      ],
    ),
  );

  Widget _buildSearchControls() {
    return Column(
      children: [
        if (_searchVisible) ...[
          SearchBar(
            controller: _searchController,
            hintText: '搜索资料名称或编号',
            leading: const Icon(Icons.search),
            trailing: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    _pageNumber = 1;
                    _loadResources();
                  },
                  icon: const Icon(Icons.clear),
                ),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              _pageNumber = 1;
              _loadResources();
            },
          ),
          const SizedBox(height: 12),
        ],
        Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _sort,
              decoration: const InputDecoration(labelText: '排序'),
              items: const [
                DropdownMenuItem(value: 'downloads', child: Text('最热门')),
                DropdownMenuItem(value: 'weekly_queries', child: Text('本周查询')),
                DropdownMenuItem(
                  value: 'weekly_downloads',
                  child: Text('本周下载'),
                ),
                DropdownMenuItem(value: 'fake_id', child: Text('最新')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _sort = value;
                  _pageNumber = 1;
                });
                _loadResources();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedTagName,
              decoration: const InputDecoration(labelText: '资料标签'),
              items: [
                const DropdownMenuItem(value: '', child: Text('全部标签')),
                for (final tag in _tags)
                  DropdownMenuItem(value: tag.name, child: Text(tag.name)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedTagName = value;
                  _pageNumber = 1;
                });
                _loadResources();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResourceCard(ChannelResource resource) {
    final busy =
        _purchasing.contains(resource.id) || _opening.contains(resource.id);
    final owned = resource.owned;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: !busy,
        onTap:
            owned ? () => _openResource(resource) : () => _purchase(resource),
        title: Text(
          resource.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${resource.points} 积分 · ${resource.downloads} 次下载'),
            if (resource.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final tag in resource.tags) Chip(label: Text(tag)),
                ],
              ),
            ],
          ],
        ),
        trailing:
            busy
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(),
                )
                : Tooltip(
                  message: owned ? '打开资料' : '兑换资料',
                  child: Icon(
                    owned
                        ? Icons.open_in_new
                        : Icons.shopping_cart_checkout_outlined,
                  ),
                ),
      ),
    );
  }

  Widget _buildPagination(ChannelResourcePage page) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上一页',
            onPressed:
                _loading || _pageNumber <= 1
                    ? null
                    : () {
                      setState(() => _pageNumber--);
                      _loadResources();
                    },
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page.page} / ${page.totalPages}'),
          IconButton(
            tooltip: '下一页',
            onPressed:
                _loading || _pageNumber >= page.totalPages
                    ? null
                    : () {
                      setState(() => _pageNumber++);
                      _loadResources();
                    },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeading({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
