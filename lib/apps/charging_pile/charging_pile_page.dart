import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../charging_piles/charging_pile_models.dart';
import '../../charging_piles/charging_pile_repository.dart';
import 'charging_pile_widgets.dart';
import 'charging_pile_credits.dart';

enum _PileSort {
  number('按编号'),
  available('空闲优先'),
  favorite('收藏优先');

  const _PileSort(this.label);
  final String label;
}

class ChargingPilePage extends StatefulWidget {
  const ChargingPilePage({super.key, this.repositoryForTesting});
  final ChargingPileRepository? repositoryForTesting;

  @override
  State<ChargingPilePage> createState() => _ChargingPilePageState();
}

class _ChargingPilePageState extends State<ChargingPilePage>
    with WidgetsBindingObserver {
  static const _favoritesKey = 'charging_pile.favorites.v1';
  late final ChargingPileRepository _repository;
  final _search = TextEditingController();
  final _viewRevision = ValueNotifier<int>(0);
  final _requests = <ChargingPileCancellation>{};
  final _favorites = <String>{};
  VoidCallback? _release;
  ChargingPileCancellation? _batch;
  ChargingPileArea? _area = ChargingPileArea.chaohui;
  _PileSort _sort = _PileSort.number;
  bool _onlyFree = false;
  bool _searching = false;
  bool _visible = true;
  bool _foreground = true;
  int _favoriteRevision = 0;
  Future<void> _favoriteWrites = Future.value();

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repositoryForTesting ?? ChargingPileRepository.shared();
    WidgetsBinding.instance.addObserver(this);
    _repository.addListener(_changed);
    _release = _repository.acquire();
    unawaited(_loadFavorites());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible && _foreground) unawaited(_refresh());
    });
  }

  Future<void> _loadFavorites() async {
    final revision = _favoriteRevision;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved =
          preferences.getStringList(_favoritesKey) ?? const <String>[];
      if (!mounted || revision != _favoriteRevision) return;
      setState(() => _favorites.addAll(saved));
    } catch (_) {
      _preferenceError();
    }
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (!_favorites.remove(id)) _favorites.add(id);
      _favoriteRevision++;
    });
    _viewRevision.value++;
    final saved = _favorites.toList()..sort();
    _favoriteWrites = _favoriteWrites
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          if (!await preferences.setStringList(_favoritesKey, saved)) {
            throw StateError('preference write failed');
          }
        })
        .catchError((Object _) => _preferenceError());
  }

  void _preferenceError() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('收藏未能保存到本机，请稍后重试。')));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible != visible) {
      _visible = visible;
      _updateLease();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateLease();
  }

  void _updateLease() {
    if (_visible && _foreground) {
      _release ??= _repository.acquire();
    } else {
      for (final request in _requests) {
        request.cancel();
      }
      _release?.call();
      _release = null;
    }
  }

  void _changed() {
    if (!mounted) return;
    final areas = _repository.loadAreas();
    if (_area != null && areas.isNotEmpty && !areas.contains(_area))
      _area = areas.first;
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repository.removeListener(_changed);
    for (final request in _requests) {
      request.cancel();
    }
    _release?.call();
    _search.dispose();
    _viewRevision.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool sync = false}) async {
    if (!_visible || !_foreground) return;
    _batch?.cancel();
    final request = ChargingPileCancellation();
    _batch = request;
    _requests.add(request);
    try {
      if (!mounted || request.isCancelled) return;
      if (sync) {
        await _repository.syncCredential();
        if (_repository.failure != null) return;
      }
      if (!mounted || request.isCancelled) return;
      await _repository.refreshAll();
    } finally {
      _requests.remove(request);
    }
  }

  void _selectArea(String value) {
    final area =
        value == 'all'
            ? null
            : _repository.loadAreas().singleWhere((area) => area.name == value);
    if (area == _area) return;
    setState(() => _area = area);
  }

  int _freeRank(ChargingPileDevice device) {
    final entry = _repository.stateFor(device.id);
    return entry.status == null ? -1 : entry.status!.freeSlots;
  }

  void _showDevice(ChargingPileDevice device) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => AnimatedBuilder(
            animation: Listenable.merge([_repository, _viewRevision]),
            builder: (context, _) {
              final entry = _repository.stateFor(device.id);
              final status = entry.status;
              final theme = Theme.of(context);
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${device.code} 号桩',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          IconButton(
                            tooltip:
                                _favorites.contains(device.id) ? '取消收藏' : '收藏',
                            isSelected: _favorites.contains(device.id),
                            icon: const Icon(Icons.star_outline_rounded),
                            selectedIcon: const Icon(Icons.star_rounded),
                            onPressed: () => _toggleFavorite(device.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '渭水 · ${device.area.label} · ${device.id}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      if (status != null) ...[
                        Text(
                          '空闲 ${status.freeSlots} · 占用 ${status.occupiedSlots} · 其他 ${status.otherSlots}',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        ChargingPilePorts(slots: status.slots),
                        const SizedBox(height: 16),
                        Text(
                          '更新时间 ${chargingPileTime(status.fetchedAt, _repository.now)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else if (entry.failure == null)
                        const Text('尚无插座状态'),
                      if (entry.failure != null) ...[
                        const SizedBox(height: 12),
                        Text(entry.failure!.message),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _repository.now;
    final devices =
        _repository
            .loadCatalog()
            .where((device) => _area == null || device.area == _area)
            .toList();
    final query = _search.text.trim().toLowerCase();
    final filtered =
        devices
            .where(
              (device) =>
                  '${device.code} ${device.name} ${device.id}'
                      .toLowerCase()
                      .contains(query) &&
                  (!_onlyFree || _freeRank(device) > 0),
            )
            .toList();
    filtered.sort((a, b) {
      if (_sort == _PileSort.available) {
        final rank = _freeRank(b).compareTo(_freeRank(a));
        if (rank != 0) return rank;
      } else if (_sort == _PileSort.favorite) {
        final rank = (_favorites.contains(b.id) ? 1 : 0).compareTo(
          _favorites.contains(a.id) ? 1 : 0,
        );
        if (rank != 0) return rank;
      }
      return a.code.compareTo(b.code);
    });
    final current =
        devices
            .map((d) => _repository.stateFor(d.id))
            .where((e) => e.status != null)
            .toList();
    final error = _repository.failure;
    return Scaffold(
      appBar: AppBar(
        title: const Text('空闲充电桩'),
        actions: [
          IconButton(
            tooltip: '致谢&贡献名单',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showChargingPileCredits(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final cardWidth = 156 * textScale.clamp(1.0, 2.0);
              final columns =
                  ((constraints.maxWidth - 32 + 8) / (cardWidth + 8))
                      .floor()
                      .clamp(1, 4)
                      .toInt();
              return RefreshIndicator(
                onRefresh: () => _refresh(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: PopupMenuButton<String>(
                                    tooltip: '选择分区',
                                    initialValue: _area?.name ?? 'all',
                                    onSelected: _selectArea,
                                    itemBuilder:
                                        (context) => [
                                          CheckedPopupMenuItem(
                                            value: 'all',
                                            checked: _area == null,
                                            child: const Text('全部分区'),
                                          ),
                                          ..._repository.loadAreas().map(
                                            (area) => CheckedPopupMenuItem(
                                              value: area.name,
                                              checked: _area == area,
                                              child: Text(area.label),
                                            ),
                                          ),
                                        ],
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 48,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                _area?.label ?? '全部分区',
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.arrow_drop_down),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _searching ? '关闭搜索' : '搜索',
                                  isSelected: _searching,
                                  icon: const Icon(Icons.search),
                                  onPressed:
                                      () => setState(() {
                                        _searching = !_searching;
                                        if (!_searching) _search.clear();
                                      }),
                                ),
                                PopupMenuButton<_PileSort>(
                                  tooltip: '排序：${_sort.label}',
                                  icon: const Icon(Icons.sort),
                                  initialValue: _sort,
                                  onSelected:
                                      (value) => setState(() => _sort = value),
                                  itemBuilder:
                                      (context) =>
                                          _PileSort.values
                                              .map(
                                                (sort) => CheckedPopupMenuItem(
                                                  value: sort,
                                                  checked: _sort == sort,
                                                  child: Text(sort.label),
                                                ),
                                              )
                                              .toList(),
                                ),
                                const SizedBox(width: 4),
                                FilterChip(
                                  side: BorderSide.none,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHigh,
                                  label: Text(
                                    _onlyFree
                                        ? '空闲 ${filtered.length} 台'
                                        : '只看空闲',
                                  ),
                                  selected: _onlyFree,
                                  onSelected:
                                      (value) =>
                                          setState(() => _onlyFree = value),
                                ),
                              ],
                            ),
                            if (_searching) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _search,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: '桩号或设备编号',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  suffixIcon: IconButton(
                                    tooltip: '清空搜索',
                                    icon: const Icon(Icons.close),
                                    onPressed:
                                        () => setState(() => _search.clear()),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                            const SizedBox(height: 8),
                            ChargingPileSummary(
                              freeSlots: current.fold(
                                0,
                                (sum, e) => sum + e.status!.freeSlots,
                              ),
                              knownSlots: current.fold(
                                0,
                                (sum, e) => sum + e.status!.slots.length,
                              ),
                              updatedDevices: current.length,
                              totalDevices: devices.length,
                              latest: _repository.updatedAt,
                              now: now,
                            ),
                            if (_repository.isRefreshing) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value:
                                    _repository.total == 0
                                        ? null
                                        : _repository.completed /
                                            _repository.total,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '查询中 ${_repository.completed}/${_repository.total}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Card.filled(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    8,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(error.message),
                                      if (_repository.pausedUntil
                                          case final until?)
                                        Text(
                                          '暂停至 ${chargingPileTime(until, now)}',
                                        ),
                                      TextButton.icon(
                                        onPressed:
                                            _repository.isRefreshing
                                                ? null
                                                : () => _refresh(sync: true),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (filtered.isEmpty &&
                        _repository.loadCatalog().isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 36,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _onlyFree ? '暂无已确认空闲的设备' : '没有匹配的设备',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed:
                                    () => setState(() {
                                      _search.clear();
                                      _onlyFree = false;
                                    }),
                                child: const Text('清除筛选'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (filtered.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                          itemCount: (filtered.length / columns).ceil(),
                          itemBuilder:
                              (context, row) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: List.generate(columns, (column) {
                                    final index = row * columns + column;
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: column == 0 ? 0 : 8,
                                        ),
                                        child:
                                            index >= filtered.length
                                                ? const SizedBox()
                                                : ChargingPileDeviceCard(
                                                  device: filtered[index],
                                                  entry: _repository.stateFor(
                                                    filtered[index].id,
                                                  ),
                                                  loading:
                                                      _repository.isRefreshing,
                                                  favorite: _favorites.contains(
                                                    filtered[index].id,
                                                  ),
                                                  onFavorite:
                                                      () => _toggleFavorite(
                                                        filtered[index].id,
                                                      ),
                                                  onOpen:
                                                      () => _showDevice(
                                                        filtered[index],
                                                      ),
                                                  showArea: _area == null,
                                                ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '数据来自第三方充电平台，请以现场为准。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
