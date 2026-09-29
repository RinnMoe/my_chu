import 'package:flutter/material.dart';

import '../../capabilities/east8_time.dart';
import '../../services/error_feedback_service.dart';
import '../../theme/app_palette.dart';
import '../../services/user_error_message.dart';
import 'classroom_usage_models.dart';
import 'classroom_usage_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

typedef ClassroomBuildingsLoader =
    Future<List<RoomBuilding>> Function({bool force});
typedef ClassroomSpacesLoader =
    Future<List<RoomUsageItem>> Function({
      required String date,
      String? beginTime,
      String? endTime,
      String? locationId,
    });

/// 空教室查询：只读查询各时段空教室，楼栋 + 日期 + 时段筛选。
class ClassroomUsagePage extends StatefulWidget {
  final ClassroomBuildingsLoader? buildingsLoader;
  final ClassroomSpacesLoader? spacesLoader;

  const ClassroomUsagePage({
    super.key,
    this.buildingsLoader,
    this.spacesLoader,
  });

  @override
  State<ClassroomUsagePage> createState() => _ClassroomUsagePageState();
}

class _ClassroomUsagePageState extends State<ClassroomUsagePage> {
  List<RoomBuilding> _buildings = const [];
  Object? _buildingsError;
  bool _buildingsLoading = true;

  List<RoomUsageItem> _items = const [];
  Object? _itemsError;
  bool _itemsLoading = false;
  bool _queried = false;
  int _buildingsRequestGeneration = 0;
  int _spacesRequestGeneration = 0;

  String? _selectedBuildingId;
  DateTime _date = east8Now();
  String _beginTime = '10:00';
  String _endTime = '12:00';

  @override
  void initState() {
    super.initState();
    _loadBuildings();
  }

  Future<void> _loadBuildings({bool force = false}) async {
    if (!mounted) return;
    final generation = ++_buildingsRequestGeneration;
    setState(() {
      _buildingsLoading = true;
      _buildingsError = null;
    });
    try {
      final loader =
          widget.buildingsLoader ?? ClassroomUsageService.fetchBuildings;
      final buildings = await loader(force: force);
      if (!mounted || generation != _buildingsRequestGeneration) return;
      setState(() {
        _buildings = buildings;
        _buildingsLoading = false;
        if (_selectedBuildingId != null &&
            !buildings.any((item) => item.id == _selectedBuildingId)) {
          _selectedBuildingId = null;
        }
      });
    } catch (error) {
      if (!mounted || generation != _buildingsRequestGeneration) return;
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.classroomUsage,
      );
      setState(() {
        _buildingsError = error;
        _buildingsLoading = false;
      });
    }
  }

  Future<void> _loadSpaces({bool force = false}) async {
    if (!mounted) return;
    final generation = ++_spacesRequestGeneration;
    final date = _formatDate(_date);
    final beginTime = _beginTime;
    final endTime = _endTime;
    final locationId = _selectedBuildingId;
    setState(() {
      _itemsLoading = true;
      _itemsError = null;
    });
    try {
      final loader = widget.spacesLoader ?? ClassroomUsageService.fetchSpaces;
      final items = await loader(
        date: date,
        beginTime: beginTime,
        endTime: endTime,
        locationId: locationId,
      );
      if (!mounted || generation != _spacesRequestGeneration) return;
      setState(() {
        _items = items;
        _itemsLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _spacesRequestGeneration) return;
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.classroomUsage,
      );
      setState(() {
        _itemsError = error;
        _itemsLoading = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// 日期按钮只显示月日，年份在点击打开日期选择器后可见/可设置。
  String _formatShortDate(DateTime date) => '${date.month}月${date.day}日';

  Future<void> _refresh() async {
    await Future.wait([_loadBuildings(force: true), _loadSpaces(force: true)]);
  }

  /// 点击“查询”才发起教室占用查询。
  Future<void> _query() async {
    setState(() => _queried = true);
    await _loadSpaces();
  }

  List<String> _timeOptions() {
    return [
      for (var hour = 0; hour < 24; hour++)
        for (final minute in ['00', '30'])
          '${hour.toString().padLeft(2, '0')}:$minute',
    ];
  }

  /// 日期与时段合并为一个按钮：弹出对话框一次性设置日期、开始/结束时间。
  /// 设置只保存到本地，点击“查询”按钮后才发起查询。
  Future<void> _openQuerySettings() async {
    var date = _date;
    var begin = _beginTime;
    var end = _endTime;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('设置查询条件'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(_formatShortDate(date)),
                      subtitle: const Text('点击选择日期'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: east8Now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: east8Now().add(const Duration(days: 180)),
                        );
                        if (picked != null) {
                          setDialogState(() => date = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _timeDropdown(
                      label: '开始时间',
                      value: begin,
                      onChanged: (value) => setDialogState(() => begin = value),
                    ),
                    const SizedBox(height: 12),
                    _timeDropdown(
                      label: '结束时间',
                      value: end,
                      onChanged: (value) => setDialogState(() => end = value),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (begin.compareTo(end) >= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('开始时间必须早于结束时间')),
                        );
                        return;
                      }
                      Navigator.pop(dialogContext, true);
                    },
                    child: const Text('确定'),
                  ),
                ],
              );
            },
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _date = date;
      _beginTime = begin;
      _endTime = end;
    });
  }

  Widget _timeDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: [
        for (final time in _timeOptions())
          DropdownMenuItem<String>(value: time, child: Text(time)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildClassroomBody(context);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('空教室查询'),
          actions: [
            IconButton(
              tooltip: '数据说明',
              onPressed: _showDataNotice,
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _buildClassroomBody(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(context),
        const Divider(height: 1),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  void _showDataNotice() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('数据说明'),
            content: const Text('数据由学校教室预约平台提供，请以实际为准'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buildingSelector = _buildBuildingSelector(theme);
          final querySettingsButton = _buildQuerySettingsButton(context);
          final queryButton = _buildQueryButton();

          // On narrow screens the three controls cannot each keep enough room
          // for their labels. Let the building selector use the full first row
          // and keep the date/action controls together below it.
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildingSelector,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: querySettingsButton),
                    const SizedBox(width: 8),
                    queryButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              // 教学楼选择控件（收起状态）加宽；展开菜单限高，内部滚动。
              Expanded(child: buildingSelector),
              const SizedBox(width: 8),
              querySettingsButton,
              const SizedBox(width: 8),
              queryButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuerySettingsButton(BuildContext context) {
    final label = '${_formatShortDate(_date)} $_beginTime–$_endTime';

    return OutlinedButton(
      onPressed: _openQuerySettings,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildQueryButton() {
    return FilledButton.icon(
      onPressed: _query,
      icon: const Icon(Icons.search, size: 18),
      label: const Text('查询'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildBuildingSelector(ThemeData theme) {
    if (_buildingsLoading && _buildings.isEmpty) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_buildingsError != null && _buildings.isEmpty) {
      return OutlinedButton.icon(
        onPressed: () => _loadBuildings(force: true),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('楼栋加载失败，重试'),
      );
    }

    return DropdownButtonFormField<String?>(
      initialValue: _selectedBuildingId,
      isExpanded: true,
      menuMaxHeight: 320,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部教学楼')),
        for (final building in _buildings)
          DropdownMenuItem<String?>(
            value: building.id,
            child: Text(building.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        setState(() => _selectedBuildingId = value);
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    if (!_queried) {
      return const _EmptyState(
        icon: Icons.search,
        message: '设置筛选条件后，点击“查询”查看空教室',
      );
    }
    if (_itemsLoading && _items.isEmpty) {
      final skeletonColor = theme.colorScheme.surfaceContainerHigh;
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder:
            (_, _) => Container(
              height: 84,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: skeletonColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
      );
    }
    if (_itemsError != null && _items.isEmpty) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        message: _errorMessage(_itemsError!),

        action: FilledButton.tonalIcon(
          onPressed: _loadSpaces,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const _EmptyState(
        icon: Icons.meeting_room_outlined,
        message: '该时段没有空教室',
      );
    }

    final list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _RoomUsageCard(item: _items[index]),
    );
    return RefreshIndicator(onRefresh: _refresh, child: list);
  }
}

class _RoomUsageCard extends StatelessWidget {
  final RoomUsageItem item;

  const _RoomUsageCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final iconBackground = colors.secondaryContainer;
    final iconForeground = colors.onSecondaryContainer;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final status = item.displayStatus;
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.meeting_room_outlined,
              size: 22,
              color: iconForeground,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.buildingName != null) item.buildingName!,
                    if (item.capacity != null) '容量 ${item.capacity}',
                    if (_hasTime(item)) _timeLabel(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: detailStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status: status),
        ],
      ),
    );

    return Card(clipBehavior: Clip.antiAlias, child: content);
  }

  bool _hasTime(RoomUsageItem item) =>
      (item.beginTime?.isNotEmpty ?? false) &&
      (item.endTime?.isNotEmpty ?? false);

  String _timeLabel() => '${item.beginTime}–${item.endTime}';
}

class _StatusChip extends StatelessWidget {
  final RoomUsageStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);

    final (label, background, foreground) = switch (status) {
      RoomUsageStatus.free => (
        '空闲',
        semantic.successContainer,
        semantic.success,
      ),
      RoomUsageStatus.occupied => (
        '占用',
        semantic.warningContainer,
        semantic.warning,
      ),
      RoomUsageStatus.unknown => (
        '未知',
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: textStyle),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const _EmptyState({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final iconColor = colors.onSurfaceVariant;
    const messageStyle = null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: messageStyle),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

String _errorMessage(Object error) {
  if (error is RoomUsageAuthenticationException) {
    return '教室服务登录状态已失效，请重新登录后重试。';
  }
  return '教室信息暂时无法加载，请稍后重试。';
}
