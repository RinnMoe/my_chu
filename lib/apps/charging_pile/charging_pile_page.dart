import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../charging_piles/charging_pile_models.dart';
import '../../charging_piles/charging_pile_repository.dart';
import 'charging_pile_widgets.dart';

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
  final _ticks = ValueNotifier<int>(0);
  final _requests = <ChargingPileCancellation>{};
  final _favorites = <String>{};
  VoidCallback? _release;
  ChargingPileCancellation? _batch;
  Timer? _clock;
  ChargingPileArea? _area = ChargingPileArea.chaohui;
  _PileSort _sort = _PileSort.number;
  bool _onlyFree = false;
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
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _visible && _foreground) {
        _ticks.value++;
        _changed();
      }
    });
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _repository.removeListener(_changed);
    for (final request in _requests) {
      request.cancel();
    }
    _release?.call();
    _search.dispose();
    _ticks.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool sync = false}) async {
    if (!_visible || !_foreground) return;
    _batch?.cancel();
    final request = ChargingPileCancellation();
    _batch = request;
    _requests.add(request);
    final area = _area;
    try {
      if (sync) {
        await _repository.syncCredential();
        if (_repository.failure != null) return;
      }
      if (!mounted || request.isCancelled) return;
      if (area == null) {
        await _repository.refreshAll(cancellation: request);
      } else {
        await _repository.refreshArea(area, cancellation: request);
      }
    } finally {
      _requests.remove(request);
    }
  }

  Future<void> _refreshDevice(String id) async {
    if (!_visible || !_foreground) return;
    final request = ChargingPileCancellation();
    _requests.add(request);
    try {
      await _repository.refreshDevice(id, cancellation: request);
    } finally {
      _requests.remove(request);
    }
  }

  void _selectArea(String value) {
    final area = value == 'all' ? null : ChargingPileArea.values.byName(value);
    if (area == _area) return;
    _batch?.cancel();
    setState(() => _area = area);
    // Viewing the whole catalog does not implicitly send 109 device requests.
    if (area != null) unawaited(_refresh());
  }

  int _freeRank(ChargingPileDevice device) {
    final entry = _repository.stateFor(device.id);
    return entry.status == null || entry.isHistorical(_repository.now)
        ? -1
        : entry.status!.freeSlots;
  }

  void _showDevice(ChargingPileDevice device) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => AnimatedBuilder(
            animation: Listenable.merge([_repository, _ticks]),
            builder: (context, _) {
              final entry = _repository.stateFor(device.id);
              final status = entry.status;
              final historical = entry.isHistorical(_repository.now);
              final theme = Theme.of(context);
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${device.code} 号桩',
                        style: theme.textTheme.headlineSmall,
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
                        ChargingPilePorts(
                          slots: status.slots,
                          historical: historical,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${historical ? '历史数据' : '更新时间'} ${chargingPileTime(status.fetchedAt, _repository.now)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else
                        const Text('尚无插座状态'),
                      if (entry.failure != null) ...[
                        const SizedBox(height: 12),
                        Text(entry.failure!.message),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.tonalIcon(
                        onPressed:
                            _repository.isDeviceRefreshing(device.id)
                                ? null
                                : () => _refreshDevice(device.id),
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新此设备'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _filterMenu<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );

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
            .where((e) => e.status != null && !e.isHistorical(now))
            .toList();
    final successful =
        devices
            .map((d) => _repository.stateFor(d.id).status?.fetchedAt)
            .whereType<DateTime>()
            .toList()
          ..sort();
    final error = _repository.failure;
    final areaMenu = _filterMenu<String>(
      label: '分区',
      value: _area?.name ?? 'all',
      items: [
        const DropdownMenuItem(value: 'all', child: Text('全部分区')),
        ...ChargingPileArea.values.map(
          (area) => DropdownMenuItem(
            value: area.name,
            child: Text(area.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) {
        if (value != null) _selectArea(value);
      },
    );
    final sortMenu = _filterMenu<_PileSort>(
      label: '排序',
      value: _sort,
      items:
          _PileSort.values
              .map(
                (sort) => DropdownMenuItem(
                  value: sort,
                  child: Text(sort.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _sort = value);
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('共享充电桩'),
        actions: [
          IconButton(
            tooltip: _area == null ? '刷新全部分区' : '刷新当前分区',
            onPressed: _repository.isRefreshing ? null : () => _refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 1080
                      ? 3
                      : constraints.maxWidth >= 720
                      ? 2
                      : 1;
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
                              latest:
                                  successful.isEmpty ? null : successful.last,
                              now: now,
                            ),
                            const SizedBox(height: 20),
                            SearchBar(
                              controller: _search,
                              hintText: '搜索桩号或设备编号',
                              leading: const Icon(Icons.search),
                              elevation: const WidgetStatePropertyAll(0),
                              trailing: [
                                if (_search.text.isNotEmpty)
                                  IconButton(
                                    tooltip: '清空搜索',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() {});
                                    },
                                  ),
                              ],
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 16),
                            if (constraints.maxWidth < 480 &&
                                MediaQuery.textScalerOf(context).scale(14) > 20)
                              Column(
                                children: [
                                  areaMenu,
                                  const SizedBox(height: 16),
                                  sortMenu,
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(flex: 3, child: areaMenu),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: sortMenu),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilterChip(
                                  label: const Text('只看空闲'),
                                  selected: _onlyFree,
                                  onSelected:
                                      (value) =>
                                          setState(() => _onlyFree = value),
                                ),
                                const Spacer(),
                                Text(
                                  '${filtered.length} 台',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ],
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
                    if (filtered.isEmpty)
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
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                          itemCount: (filtered.length / columns).ceil(),
                          itemBuilder:
                              (context, row) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: List.generate(columns, (column) {
                                    final index = row * columns + column;
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: column == 0 ? 0 : 12,
                                        ),
                                        child:
                                            index >= filtered.length
                                                ? const SizedBox()
                                                : ChargingPileDeviceCard(
                                                  device: filtered[index],
                                                  entry: _repository.stateFor(
                                                    filtered[index].id,
                                                  ),
                                                  now: now,
                                                  loading: _repository
                                                      .isDeviceRefreshing(
                                                        filtered[index].id,
                                                      ),
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
                                                  onRefresh:
                                                      () => _refreshDevice(
                                                        filtered[index].id,
                                                      ),
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
