import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../capabilities/campus_map/campus_map_capability.dart';
import '../../capabilities/campus_places/campus_registry.dart';
import 'charging_pile_map_link.dart';
import 'charging_pile_models.dart';
import 'charging_pile_scan.dart';
import 'charging_pile_service.dart';
import 'charging_pile_stats.dart';
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
  const ChargingPilePage({
    super.key,
    this.repositoryForTesting,
    this.initialDeviceId,
  });
  final ChargingPileRepository? repositoryForTesting;

  /// Opens directly on one device: the page switches to its area, reveals the
  /// card and shows the detail sheet. Used when the campus map focuses a pile.
  /// Leaving it null keeps the previous page behaviour unchanged.
  final String? initialDeviceId;

  @override
  State<ChargingPilePage> createState() => _ChargingPilePageState();
}

class _ChargingPilePageState extends State<ChargingPilePage>
    with WidgetsBindingObserver {
  static const _favoritesKey = 'charging_pile.favorites.v1';
  late final ChargingPileRepository _repository;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _deviceKeys = <String, GlobalKey>{};
  final _viewRevision = ValueNotifier<int>(0);
  final _requests = <ChargingPileCancellation>{};
  final _favorites = <String>{};
  VoidCallback? _release;
  ChargingPileCancellation? _batch;
  /// `null` is the "全部分区" selection, which is the default on open. A map
  /// jump may narrow it to the device's area once the page receives a target.
  ChargingPileArea? _area;

  /// 当前校区；源站把多个校区的桩放在同一份目录里，页面按校区收窄。
  String? _campusId;

  /// 校区 id → 显示名，来自地图的校区清单；加载失败时退回 id 本身。
  Map<String, String> _campusNames = const <String, String>{};
  _PileSort _sort = _PileSort.number;
  bool _onlyFree = false;
  bool _searching = false;
  bool _visible = true;
  bool _foreground = true;
  bool _resumeScheduled = false;
  String? _highlighted;
  int _favoriteRevision = 0;
  Future<void> _favoriteWrites = Future.value();

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repositoryForTesting ?? ChargingPileRepository.shared();
    unawaited(_loadCampusNames());
    WidgetsBinding.instance.addObserver(this);
    _repository.addListener(_changed);
    _release = _repository.acquire();
    unawaited(_loadFavorites());
    unawaited(_ensureCatalog());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_visible && _foreground) unawaited(_refresh());
      unawaited(_openInitialDevice());
    });
  }

  Future<void> _ensureCatalog() async {
    try {
      await _repository.ensureCatalog();
    } catch (_) {
      // 目录失败时页面保留空列表 + 重试入口，不阻断其他功能。
    }
    if (!mounted) return;
    setState(() {});
    // 首屏用全校快照铺满：1 个请求换全部设备的状态，比逐台查便宜一个量级。
    if (_visible && _foreground && _repository.needsRefresh) {
      unawaited(_repository.refreshSnapshot());
    }
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
        .then<void>((_) async {
          final preferences = await SharedPreferences.getInstance();
          if (!await preferences.setStringList(_favoritesKey, saved)) {
            throw StateError('preference write failed');
          }
        })
        .catchError((Object _) {
          _preferenceError();
        });
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
      _scheduleResumeRefresh();
    } else {
      for (final request in _requests) {
        request.cancel();
      }
      _release?.call();
      _release = null;
    }
  }

  /// Resumes an interrupted page transaction when the page becomes active
  /// again. Without this, backgrounding during a refresh would leave an empty
  /// grid until the user pulled to refresh manually. With a usable snapshot the
  /// page only re-queries devices that are no longer live.
  void _scheduleResumeRefresh() {
    if (_resumeScheduled) return;
    _resumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeScheduled = false;
      if (!mounted || !_visible || !_foreground) return;
      if (_repository.needsRefresh) {
        unawaited(_repository.refreshSnapshot());
        return;
      }
      unawaited(_repository.refreshIfStale());
    });
  }

  /// Focuses the device the campus map asked for: switch to its area, reveal
  /// its card, then open the existing detail sheet.
  Future<void> _openInitialDevice() async {
    final deviceId = widget.initialDeviceId;
    if (deviceId == null) return;
    final device = _repository.deviceFor(deviceId);
    if (device == null) return;
    final area = device.area;
    setState(() {
      // An unmapped location keeps "all areas" so its card is not filtered away.
      _area = area == ChargingPileArea.unknown ? null : area;
      _highlighted = deviceId;
    });
    await _revealDevice(device);
    if (!mounted) return;
    await _showDevice(device);
    if (!mounted) return;
    setState(() => _highlighted = null);
  }

  GlobalKey _deviceKey(String deviceId) =>
      _deviceKeys.putIfAbsent(deviceId, () => GlobalKey());

  /// Scrolls the virtualized grid until the target card has been built, then
  /// centers it. Bounded so a missing target can never spin forever.
  Future<void> _revealDevice(ChargingPileDevice device) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      final target = _deviceKeys[device.id]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.2,
          duration: const Duration(milliseconds: 220),
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) return;
      _scroll.jumpTo(
        math.min(
          position.maxScrollExtent,
          position.pixels + position.viewportDimension * 0.8,
        ),
      );
    }
  }

  /// 校区显示名取自地图的校区清单（`assets/maps/campuses.json`），
  /// 这样新增校区时不用在充电桩这边再抄一份名字。
  Future<void> _loadCampusNames() async {
    try {
      final registry = await CampusRegistryLoader().load();
      if (!mounted) return;
      setState(() {
        _campusNames = <String, String>{
          for (final campus in registry.campuses)
            campus.campusId: campus.displayName,
        };
      });
    } catch (_) {
      // 名字读不出来不影响功能：下拉里显示 id。
    }
  }

  String get _activeCampusId =>
      _campusId ?? _repository.loadAreas().firstOrNull?.campusId ?? '';

  String _campusLabel(String campusId) =>
      _campusNames[campusId] ?? campusId;

  /// 当前校区的分区；没选校区（目录为空）时回退到全部分区。
  List<ChargingPileArea> get _campusAreas {
    final areas = _repository.loadAreas();
    final campusId = _activeCampusId;
    if (campusId.isEmpty) return areas;
    return areas.where((area) => area.campusId == campusId).toList();
  }

  void _selectCampus(String campusId) {
    if (campusId == _activeCampusId) return;
    setState(() {
      _campusId = campusId;
      // 分区属于校区，切校区后原来的分区不再适用。
      _area = null;
    });
  }

  void _changed() {
    if (!mounted) return;
    final areas = _campusAreas;
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
    _scroll.dispose();
    _viewRevision.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool sync = false, bool force = false}) async {
    if (!_visible || !_foreground) return;
    // The source gates manual whole-catalog refreshes to one per minute; a
    // pull-to-refresh inside that window would only burn the proxy budget and
    // come back throttled. Retry (`sync`) resets the window itself, so it is
    // not blocked here.
    if (force && !sync) {
      final wait = _repository.refreshCooldown;
      if (wait != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('刚更新过，${wait.inSeconds + 1} 秒后才能再刷')),
          );
        }
        return;
      }
    }
    _batch?.cancel();
    final request = ChargingPileCancellation();
    _batch = request;
    _requests.add(request);
    try {
      if (!mounted || request.isCancelled) return;
      if (sync) {
        await _repository.syncCredential(force: force);
        if (_repository.failure != null) return;
      }
      if (!mounted || request.isCancelled) return;
      await _repository.refreshAll(force: force);
    } finally {
      _requests.remove(request);
      // The source reports a degraded scan as a transient toast and keeps the
      // previous numbers on screen, never as a page-wide banner.
      if (mounted && _repository.consumeDegradation()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('这一分钟查得太多，先用最近一次的结果，过十几秒再点'),
          ),
        );
      }
    }
  }

  void _selectArea(String value) {
    final area =
        value == 'all'
            ? null
            : _repository.loadAreas().singleWhere(
              (area) => area.areaId == value,
            );
    if (area == _area) return;
    setState(() => _area = area);
  }

  /// 排序与「只看空闲」共用的排序键：未知 -1、已满 0、空闲为插座数。
  ///
  /// 按最近一次成功数据排序与筛选。
  int _freeRank(ChargingPileDevice device) {
    return switch (_repository.availabilityFor(device.id)) {
      ChargingPileAvailability.unknown => -1,
      ChargingPileAvailability.occupied => 0,
      ChargingPileAvailability.free =>
        _repository.stateFor(device.id).status?.freeSlots ?? 1,
    };
  }

  Future<void> _showDevice(ChargingPileDevice device) {
    return showModalBottomSheet<void>(
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
                        Text(
                          entry.failure == ChargingPileFailure.consentRequired
                              ? '请先同意用户协议'
                              : '设备状态未知，请重新查询。',
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  /// 打开校园地图并聚焦该设备；不使用任何绕过地图 Capability 的跳转方式。
  Future<void> _openOnMap(ChargingPileDevice device) async {
    final result = await openChargingPileOnMap(
      context,
      deviceId: device.id,
      campusId: device.campusId,
    );
    if (!mounted) return;
    final message = switch (result) {
      MapLayerOpenResult.opened => null,
      MapLayerOpenResult.unknownLayer => '地图图层暂不可用，请稍后重试。',
      MapLayerOpenResult.unsupportedCampus => '该校区暂不支持充电桩地图。',
      MapLayerOpenResult.openFailed => '暂时无法打开地图，请稍后重试。',
    };
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _repository.now;
    final campusId = _activeCampusId;
    final devices =
        _repository
            .loadCatalog()
            .where(
              (device) =>
                  (campusId.isEmpty || device.campusId == campusId) &&
                  (_area == null || device.area == _area),
            )
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
    // 汇总统计所有有成功数据的设备。
    final live =
        devices
            .where(
              (device) =>
                  _repository.freshnessFor(device.id) ==
                  ChargingPileStatusFreshness.live,
            )
            .toList();
    final error = _repository.failure;
    return Scaffold(
      appBar: AppBar(
        title: const Text('空闲充电桩'),
        actions: [
          IconButton(
            tooltip: '扫码采设备号',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => showChargingPileScan(
              context,
              knownDeviceIds: {
                for (final device in _repository.loadCatalog())
                  device.id.toUpperCase(),
              },
            ),
          ),
          IconButton(
            tooltip: '一周回顾',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => showChargingPileStats(
              context,
              areas: _repository.loadAreas(),
            ),
          ),
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
              final cardWidth = 180 * textScale.clamp(1.0, 2.0);
              final columns =
                  ((constraints.maxWidth - 32 + 8) / (cardWidth + 8))
                      .floor()
                      .clamp(1, 4)
                      .toInt();
              return RefreshIndicator(
                onRefresh: () => _refresh(force: true),
                child: CustomScrollView(
                  controller: _scroll,
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
                                PopupMenuButton<String>(
                                  tooltip: '切换校区',
                                  initialValue: _activeCampusId,
                                  onSelected: _selectCampus,
                                  itemBuilder:
                                      (context) => [
                                        for (final id in _repository
                                            .loadAreas()
                                            .map((area) => area.campusId)
                                            .toSet())
                                          CheckedPopupMenuItem(
                                            value: id,
                                            checked: id == _activeCampusId,
                                            child: Text(_campusLabel(id)),
                                          ),
                                      ],
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        right: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _campusLabel(_activeCampusId),
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const Icon(
                                            Icons.arrow_drop_down,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: PopupMenuButton<String>(
                                    tooltip: '选择分区',
                                    initialValue: _area?.areaId ?? 'all',
                                    onSelected: _selectArea,
                                    itemBuilder:
                                        (context) => [
                                          CheckedPopupMenuItem(
                                            value: 'all',
                                            checked: _area == null,
                                            child: const Text('全部分区'),
                                          ),
                                          ..._campusAreas.map(
                                            (area) => CheckedPopupMenuItem(
                                              value: area.areaId,
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
                                        ? '${filtered.length} 台有空闲'
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
                              freeSlots: live.fold(
                                0,
                                (sum, device) =>
                                    sum +
                                    _repository.confirmedFreeSlots(device.id),
                              ),
                              knownSlots: live.fold(
                                0,
                                (sum, device) =>
                                    sum +
                                    (_repository
                                            .stateFor(device.id)
                                            .status
                                            ?.slots
                                            .length ??
                                        0),
                              ),
                              updatedDevices: live.length,
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
                              SizedBox(
                                width: double.infinity,
                                child: Card.filled(
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
                                            '已暂停自动刷新，手动「重试」不受影响 · 恢复于 ${chargingPileTime(until, now)}',
                                          ),
                                        TextButton.icon(
                                          onPressed:
                                              _repository.isRefreshing
                                                  ? null
                                                  : () => _refresh(
                                                    sync: true,
                                                    force: true,
                                                  ),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('重试'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!_repository.hasCatalog)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else if (filtered.isEmpty &&
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
                                                : _buildCard(
                                                  filtered[index],
                                                  theme,
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

  /// One grid card, wrapped with a reveal key and outline while the map-opened
  /// device is being focused.
  Widget _buildCard(ChargingPileDevice device, ThemeData theme) {
    final card = ChargingPileDeviceCard(
      device: device,
      entry: _repository.stateFor(device.id),
      freshness: _repository.freshnessFor(device.id),
      loading: _repository.isRefreshing,
      favorite: _favorites.contains(device.id),
      onFavorite: () => _toggleFavorite(device.id),
      onMap: () => _openOnMap(device),
      onOpen: () => _showDevice(device),
      showArea: _area == null,
    );
    if (device.id != _highlighted) return card;
    return KeyedSubtree(
      key: _deviceKey(device.id),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
        ),
        child: card,
      ),
    );
  }
}
