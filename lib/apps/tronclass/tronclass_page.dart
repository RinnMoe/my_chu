import 'package:flutter/material.dart';

import '../../capabilities/in_app_download/in_app_download.dart';
import '../../services/logger_service.dart';
import '../../services/user_error_message.dart';
import 'tronclass_models.dart';
import 'tronclass_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class TronclassPage extends StatelessWidget {
  const TronclassPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('畅课课件下载'), centerTitle: true),
      ),
      body: const _CoursewareTab(),
    );
  }
}

class _CoursewareTab extends StatefulWidget {
  const _CoursewareTab();

  @override
  State<_CoursewareTab> createState() => _CoursewareTabState();
}

class _CoursewareTabState extends State<_CoursewareTab>
    with AutomaticKeepAliveClientMixin {
  /// 默认自动加载的批次数：5 批以内自动分批加载完成，避免用户下拉时
  /// 新数据跳到列表上方；超过 5 批才需要用户下滑触发继续加载。
  static const _autoLoadPages = 5;

  List<TronclassCourse>? _courses;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _autoLoading = false;
  int _page = 1;
  int _pages = 1;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _pages = 1;
      _autoLoading = false;
    });
    try {
      final result = await TronclassService().fetchCoursesPage(page: 1);
      if (!mounted) return;
      setState(() {
        _courses = _sortedCourses(result.courses);
        _pages = result.pages;
        _loading = false;
      });
      await _autoLoadRemaining();
    } catch (error) {
      if (!mounted) return;
      logUserFacingError(UserErrorContext.network, error, operation: 'courses');
      setState(() {
        _error = userFacingError(UserErrorContext.network, error);
        _loading = false;
      });
    }
  }

  Future<void> _autoLoadRemaining() async {
    var current = _page;
    while (current < _pages && current < _autoLoadPages) {
      if (!mounted) return;
      setState(() => _autoLoading = true);
      final next = current + 1;
      try {
        final result = await TronclassService().fetchCoursesPage(page: next);
        if (!mounted) return;
        setState(() {
          _page = next;
          _pages = result.pages;
          _courses = _sortedCourses([...?_courses, ...result.courses]);
        });
        current = next;
      } catch (error) {
        // 自动加载失败时保留已加载内容，之后由手动下滑重试。
        if (!mounted) return;
        AppLogger.recordSafeFailure(
          level: 'WARN',
          code: 'tronclass.courses.auto_page.failed',
          message: '畅课课程自动分页失败',
          error: error,
          domain: 'tronclass',
          fields: const {'stage': 'auto_page'},
        );
        break;
      }
    }
    if (mounted) setState(() => _autoLoading = false);
  }

  Future<void> _loadMore() async {
    final courses = _courses;
    if (_loadingMore || _autoLoading || _loading || courses == null) return;
    if (_page >= _pages) return;
    final nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      final result = await TronclassService().fetchCoursesPage(page: nextPage);
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _pages = result.pages;
        _courses = _sortedCourses([...courses, ...result.courses]);
      });
    } catch (error) {
      // 加载更多失败不打断已有列表，滚动到底部会再次触发。
      if (!mounted) return;
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'tronclass.courses.load_more.failed',
        message: '畅课课程加载更多失败',
        error: error,
        domain: 'tronclass',
        fields: const {'stage': 'load_more'},
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 按开始时间倒序：最新课程在最上面；无开始时间的排最后。
  List<TronclassCourse> _sortedCourses(List<TronclassCourse> courses) {
    final sorted = List<TronclassCourse>.from(courses);
    sorted.sort((a, b) {
      final startA = a.startDate;
      final startB = b.startDate;
      if (startA == null && startB == null) return 0;
      if (startA == null) return 1;
      if (startB == null) return -1;
      final byStart = startB.compareTo(startA);
      if (byStart != 0) return byStart;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final courses = _courses;
    if (_loading && courses == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && courses == null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    if (courses == null || courses.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const _EmptyState(
          icon: Icons.folder_open_outlined,
          message: '暂无课程',
        ),
      );
    }
    final results = _filteredCourses(courses);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: '搜索课程或教师',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Expanded(
          child:
              results.isEmpty
                  ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: Text('没有匹配的课程')),
                      ),
                    ],
                  )
                  : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: results.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == results.length) {
                          final loading = _autoLoading || _loadingMore;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child:
                                  loading
                                      ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '正在加载课程…',
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                          ),
                                        ],
                                      )
                                      : _page < _pages
                                      ? Text(
                                        '继续上滑加载更多课程',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall?.copyWith(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                      : Text(
                                        '已显示全部 ${results.length} 门课程',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall?.copyWith(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                            ),
                          );
                        }
                        final course = results[index];
                        final instructors = course.instructorNames.join('、');
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            title: Text(
                              course.chineseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            subtitle:
                                instructors.isEmpty
                                    ? null
                                    : Text(
                                      instructors,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap:
                                () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => _CoursewareFilesPage(
                                          course: course,
                                        ),
                                  ),
                                ),
                          ),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  List<TronclassCourse> _filteredCourses(List<TronclassCourse> courses) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return courses;
    return courses
        .where(
          (course) =>
              course.chineseName.toLowerCase().contains(query) ||
              course.courseCode.toLowerCase().contains(query) ||
              course.instructorNames.any(
                (name) => name.toLowerCase().contains(query),
              ),
        )
        .toList(growable: false);
  }
}

class _CoursewareFilesPage extends StatefulWidget {
  final TronclassCourse course;

  const _CoursewareFilesPage({required this.course});

  @override
  State<_CoursewareFilesPage> createState() => _CoursewareFilesPageState();
}

class _CoursewareFilesPageState extends State<_CoursewareFilesPage> {
  List<TronclassCoursewareFile>? _files;
  TronclassCoursewareProgress? _progress;
  String? _error;
  bool _loading = true;
  final Set<String> _downloading = {};
  final Map<String, InAppDownloadProgress> _downloadProgress = {};
  final Map<String, InAppDownloadedFile> _downloadedFiles = {};
  static const _downloadCapability = InAppDownloadCapability();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';
  _FileTypeFilter _typeFilter = _FileTypeFilter.all;
  int _visibleCount = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      setState(() => _visibleCount += 20);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _files = null;
      _progress = null;
    });
    try {
      final files = await TronclassService().fetchCoursewareFiles(
        widget.course,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onFilesUpdated: (files) {
          if (!mounted) return;
          setState(() {
            _files = files;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
        _progress = null;
      });
    } catch (error) {
      if (!mounted) return;
      logUserFacingError(
        UserErrorContext.network,
        error,
        operation: 'courseware',
      );
      setState(() {
        _error = userFacingError(UserErrorContext.network, error);
        _loading = false;
        _progress = null;
      });
    }
  }

  List<TronclassCoursewareFile> _filteredFiles() {
    final files = _files ?? const <TronclassCoursewareFile>[];
    final query = _query.toLowerCase();
    return files
        .where(
          (file) =>
              (query.isEmpty || file.name.toLowerCase().contains(query)) &&
              (_typeFilter == _FileTypeFilter.all ||
                  _fileTypeOf(file) == _typeFilter),
        )
        .toList(growable: false);
  }

  Future<void> _download(TronclassCoursewareFile file) async {
    setState(() {
      _downloading.add(file.fileId);
      _downloadProgress.remove(file.fileId);
    });
    try {
      final downloaded = await TronclassService().downloadCoursewareFile(
        file,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress[file.fileId] = progress);
        },
      );
      if (!mounted) return;
      setState(() => _downloadedFiles[file.fileId] = downloaded);
      final savedLocation =
          downloaded.path.startsWith('content://')
              ? 'Download/MyCHU/${downloaded.fileName}'
              : downloaded.path;
      await _showFeedback('已保存到：$savedLocation');
    } catch (error) {
      if (!mounted) return;
      logUserFacingError(
        UserErrorContext.download,
        error,
        operation: 'courseware',
      );
      await _showFeedback(userFacingError(UserErrorContext.download, error));
    } finally {
      if (mounted) {
        setState(() {
          _downloading.remove(file.fileId);
          _downloadProgress.remove(file.fileId);
        });
      }
    }
  }

  Widget _downloadProgressIndicator(
    ThemeData theme,
    InAppDownloadProgress? progress,
  ) {
    final fraction = progress?.fraction;
    final label =
        fraction == null
            ? progress == null
                ? '下载中'
                : formatFileSize(progress.receivedBytes)
            : '${(fraction * 100).round()}%';
    return SizedBox(
      width: 68,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(value: fraction, strokeWidth: 2),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(TronclassCoursewareFile file) async {
    final downloaded = _downloadedFiles[file.fileId];
    if (downloaded == null) return;
    final opened = await _downloadCapability.open(downloaded);
    if (!mounted || opened) return;
    await _showFeedback('无法打开文件，请安装支持该格式的应用。');
  }

  Future<void> _showFeedback(String message) async {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: Text(widget.course.chineseName),
          centerTitle: true,
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final files = _files;
    if (_loading && files == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_progress case final progress?) ...[
              const SizedBox(height: 16),
              Text(
                '扫描课件活动 ${progress.completed}/${progress.total}'
                '，已发现 ${progress.found} 个文件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (_error != null && files == null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    if (files == null || files.isEmpty) {
      return _EmptyState(
        icon: Icons.folder_off_outlined,
        message: '该课程暂无课件',
        onRetry: _load,
      );
    }
    final filtered = _filteredFiles();
    final visible = filtered.take(_visibleCount).toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: '搜索文件名',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _query = value.trim();
                    _visibleCount = 20;
                  });
                },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in _FileTypeFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(type.label),
                          visualDensity: VisualDensity.compact,
                          selected: _typeFilter == type,
                          onSelected: (_) {
                            setState(() {
                              _typeFilter = type;
                              _visibleCount = 20;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          LinearProgressIndicator(
            value:
                _progress == null || _progress!.total == 0
                    ? null
                    : _progress!.completed / _progress!.total,
            minHeight: 2,
          ),
        Expanded(
          child:
              visible.isEmpty
                  ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: Text('没有匹配的课件')),
                      ),
                    ],
                  )
                  : ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: visible.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == visible.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child:
                                _loading
                                    ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : Text(
                                      '已显示全部 ${visible.length} / ${filtered.length} 项',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color:
                                                theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                    ),
                          ),
                        );
                      }
                      final file = visible[index];
                      final downloading = _downloading.contains(file.fileId);
                      final downloadProgress = _downloadProgress[file.fileId];
                      final downloaded = _downloadedFiles[file.fileId] != null;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          title: Text(
                            file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${file.sizeLabel} · ${file.activityTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: downloaded ? '打开' : '下载',
                            onPressed:
                                downloading
                                    ? null
                                    : downloaded
                                    ? () => _open(file)
                                    : () => _download(file),
                            icon:
                                downloading
                                    ? _downloadProgressIndicator(
                                      theme,
                                      downloadProgress,
                                    )
                                    : Icon(
                                      downloaded
                                          ? Icons.open_in_new_outlined
                                          : Icons.download_outlined,
                                    ),
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

enum _FileTypeFilter {
  all('全部'),
  pdf('PDF'),
  ppt('PPT'),
  word('Word'),
  excel('Excel'),
  video('视频'),
  other('其他');

  final String label;

  const _FileTypeFilter(this.label);
}

_FileTypeFilter _fileTypeOf(TronclassCoursewareFile file) {
  final name = file.name.toLowerCase();
  final type = file.type.toLowerCase();
  if (name.endsWith('.pdf') || type.contains('pdf')) {
    return _FileTypeFilter.pdf;
  }
  if (name.endsWith('.ppt') ||
      name.endsWith('.pptx') ||
      type.contains('powerpoint') ||
      type.contains('presentation')) {
    return _FileTypeFilter.ppt;
  }
  if (name.endsWith('.doc') ||
      name.endsWith('.docx') ||
      type.contains('msword') ||
      type.contains('wordprocessing')) {
    return _FileTypeFilter.word;
  }
  if (name.endsWith('.xls') ||
      name.endsWith('.xlsx') ||
      name.endsWith('.csv') ||
      type.contains('excel') ||
      type.contains('spreadsheet')) {
    return _FileTypeFilter.excel;
  }
  if (RegExp(r'\.(mp4|mov|avi|wmv|flv|mkv|m4v|webm)$').hasMatch(name) ||
      type.startsWith('video/')) {
    return _FileTypeFilter.video;
  }
  return _FileTypeFilter.other;
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: colors.error),
            const SizedBox(height: 12),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function()? onRetry;

  const _EmptyState({required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(icon, size: 56, color: colors.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
