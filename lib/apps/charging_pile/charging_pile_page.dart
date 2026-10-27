import 'dart:async';

import 'package:flutter/material.dart';

import 'charging_pile_catalog.dart';
import 'charging_pile_models.dart';
import 'charging_pile_service.dart';

/// Shows real-time free slots for campus charging piles.
///
/// The data comes from a read-only third-party endpoint and requires a
/// user-provided token stored locally in secure storage.
class ChargingPilePage extends StatefulWidget {
  final ChargingPileService? serviceForTesting;
  final List<ChargingPileDevice> devicesForTesting;

  const ChargingPilePage({
    super.key,
    this.serviceForTesting,
    this.devicesForTesting = const [],
  });

  @override
  State<ChargingPilePage> createState() => _ChargingPilePageState();
}

class _ChargingPilePageState extends State<ChargingPilePage> {
  late final ChargingPileService _service;
  late final List<ChargingPileDevice> _devices;
  late final List<String> _locations;

  final Map<String, ChargingPileDeviceStatus> _statuses = {};
  final Map<String, ChargingPileDeviceFailure> _failures = {};

  ChargingPileTokenInfo _tokenInfo = ChargingPileTokenInfo.none;
  String? _token;
  bool _loading = false;
  bool _authFailed = false;
  String? _loadError;
  DateTime? _lastRefreshAt;
  Timer? _countdownTimer;
  String _selectedLocation = '全部';

  @override
  void initState() {
    super.initState();
    _service = widget.serviceForTesting ?? ChargingPileService();
    _devices =
        widget.devicesForTesting.isEmpty
            ? kChargingPileDevices
            : widget.devicesForTesting;
    _locations = [
      '全部',
      ..._devices.map((device) => device.location).toSet().toList(),
    ];
    unawaited(_loadSavedToken());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _service.timeUntilNextRefresh != Duration.zero) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _service.close();
    super.dispose();
  }

  Future<void> _loadSavedToken() async {
    try {
      final token = await _service.readToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _tokenInfo = ChargingPileService.tokenInfo(token);
      });
      if (token != null) {
        await _refresh();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '读取本地凭证失败：$error');
    }
  }

  Future<void> _refresh() async {
    if (_loading || _token == null) return;
    if (!_service.shouldRefresh()) return;

    setState(() {
      _loading = true;
      _authFailed = false;
      _loadError = null;
      _statuses.clear();
      _failures.clear();
    });

    try {
      await _service.refresh(
        devices: _devices,
        token: _token!,
        onDeviceResult: (status, failure) {
          if (!mounted) return;
          setState(() {
            if (status != null) {
              _statuses[status.device.id] = status;
              _failures.remove(status.device.id);
            }
            if (failure != null) {
              _failures[failure.device.id] = failure;
              _statuses.remove(failure.device.id);
            }
            if (failure?.authFailure ?? false) {
              _authFailed = true;
              _tokenInfo = ChargingPileTokenInfo(
                state: ChargingPileTokenState.expired,
                expiresAt: _tokenInfo.expiresAt,
              );
            }
          });
        },
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '查询失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _lastRefreshAt = _service.lastRefreshAt;
        });
      }
    }
  }

  Future<void> _openTokenDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('设置充电桩凭证'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '在微信「街电」小程序中任选一个柜机，抓包 union.zhumanggroup.com 的 '
                  'Authorization，整段复制粘贴即可。凭证仅保存在本机安全存储，约 7 天过期。',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  minLines: 2,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Authorization / token',
                    border: OutlineInputBorder(),
                    hintText: 'Bearer eyJ...',
                  ),
                ),
              ],
            ),
            actions: [
              if (_token != null)
                TextButton(
                  onPressed: () => Navigator.of(context).pop('__clear__'),
                  child: const Text('清除'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('保存并查询'),
              ),
            ],
          ),
    );
    controller.dispose();

    if (result == null) return;
    if (result == '__clear__') {
      await _service.clearToken();
      if (!mounted) return;
      setState(() {
        _token = null;
        _tokenInfo = ChargingPileTokenInfo.none;
        _statuses.clear();
        _failures.clear();
        _lastRefreshAt = null;
        _authFailed = false;
        _loadError = null;
      });
      return;
    }

    final normalized = ChargingPileService.normalizeToken(result);
    final token = normalized.token;
    final error = normalized.error;
    if (token == null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('凭证无效'),
              content: Text(error ?? '请检查粘贴内容。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
      );
      return;
    }

    await _service.saveToken(token);
    if (!mounted) return;
    setState(() {
      _token = token;
      _tokenInfo = ChargingPileService.tokenInfo(token);
      _authFailed = false;
      _loadError = null;
      _statuses.clear();
      _failures.clear();
      _lastRefreshAt = null;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final devices =
        _selectedLocation == '全部'
            ? _devices
            : _devices
                .where((device) => device.location == _selectedLocation)
                .toList(growable: false);
    final summary = _Summary.of(devices, _statuses, _failures, _loading);

    return Scaffold(
      appBar: AppBar(
        title: const Text('充电桩空位'),
        actions: [
          IconButton(
            tooltip: '设置凭证',
            onPressed: _openTokenDialog,
            icon: const Icon(Icons.key_outlined),
          ),
          IconButton(
            tooltip: _refreshTooltip,
            onPressed: _canRefresh ? _refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _canRefresh ? _refresh : () async {},
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _TokenPanel(
              tokenInfo: _tokenInfo,
              lastRefreshAt: _lastRefreshAt,
              nextRefreshIn: _service.timeUntilNextRefresh,
              loading: _loading,
              authFailed: _authFailed,
              error: _loadError,
              onSetToken: _openTokenDialog,
            ),
            const SizedBox(height: 12),
            _SummaryBar(summary: summary),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _locations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final location = _locations[index];
                  final selected = location == _selectedLocation;
                  return ChoiceChip(
                    label: Text(location),
                    selected: selected,
                    onSelected:
                        _loading
                            ? null
                            : (value) {
                              if (value) {
                                setState(() => _selectedLocation = location);
                              }
                            },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ...devices.map(
              (device) => _DeviceStateScope(
                state: this,
                child: _DeviceCard(device: device),
              ),
            ),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('该区域暂无充电桩。')),
              ),
            const SizedBox(height: 12),
            Text(
              '数据来自第三方平台只读接口（每次查询间隔至少 60 秒）。凭证由使用者自行提供并仅保存在本机，'
              '应用不会代为登录、下单或支付。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canRefresh =>
      !_loading && _token != null && _service.shouldRefresh();

  String get _refreshTooltip {
    final remaining = _service.timeUntilNextRefresh;
    if (_loading) return '正在查询';
    if (_token == null) return '请先设置凭证';
    if (remaining != Duration.zero) {
      final seconds = remaining.inSeconds;
      return '$seconds 秒后可刷新';
    }
    return '刷新';
  }
}

class _TokenPanel extends StatelessWidget {
  final ChargingPileTokenInfo tokenInfo;
  final DateTime? lastRefreshAt;
  final Duration nextRefreshIn;
  final bool loading;
  final bool authFailed;
  final String? error;
  final VoidCallback onSetToken;

  const _TokenPanel({
    required this.tokenInfo,
    required this.lastRefreshAt,
    required this.nextRefreshIn,
    required this.loading,
    required this.authFailed,
    required this.error,
    required this.onSetToken,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final expired = authFailed || tokenInfo.state == ChargingPileTokenState.expired;

    return Card(
      margin: EdgeInsets.zero,
      color: expired ? colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  expired ? Icons.error_outline : Icons.verified_outlined,
                  color:
                      expired
                          ? colorScheme.onErrorContainer
                          : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_tokenLabel, style: theme.textTheme.bodyMedium)),
                if (!tokenInfo.exists)
                  TextButton(onPressed: onSetToken, child: const Text('设置凭证'))
                else if (expired)
                  TextButton(onPressed: onSetToken, child: const Text('更新凭证')),
              ],
            ),
            if (lastRefreshAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '最近刷新：${_formatTime(lastRefreshAt!)}'
                '${nextRefreshIn != Duration.zero ? '，${nextRefreshIn.inSeconds} 秒后可刷新' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (loading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (authFailed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '凭证已失效。请在微信「街电」小程序重新抓取 Authorization 后更新。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _tokenLabel {
    if (!tokenInfo.exists) return '尚未设置凭证';
    if (authFailed || tokenInfo.state == ChargingPileTokenState.expired) {
      return '凭证已过期';
    }
    final expiresAt = tokenInfo.expiresAt;
    final expiresText =
        expiresAt == null ? '' : '（${_formatDate(expiresAt)} 到期）';
    switch (tokenInfo.state) {
      case ChargingPileTokenState.expiringSoon:
        return '凭证即将过期$expiresText';
      case ChargingPileTokenState.valid:
        return '凭证有效$expiresText';
      case ChargingPileTokenState.opaque:
        return '已保存凭证（无法解析有效期）';
      case ChargingPileTokenState.invalid:
        return '已保存凭证（格式无效）';
      case ChargingPileTokenState.expired:
      case ChargingPileTokenState.none:
        return '凭证状态未知';
    }
  }

  static String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  static String _formatDate(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

class _Summary {
  final int totalDevices;
  final int availableDevices;
  final int freeSlots;
  final int occupiedSlots;
  final int unknownDevices;

  const _Summary({
    required this.totalDevices,
    required this.availableDevices,
    required this.freeSlots,
    required this.occupiedSlots,
    required this.unknownDevices,
  });

  static _Summary of(
    List<ChargingPileDevice> devices,
    Map<String, ChargingPileDeviceStatus> statuses,
    Map<String, ChargingPileDeviceFailure> failures,
    bool loading,
  ) {
    var availableDevices = 0;
    var freeSlots = 0;
    var occupiedSlots = 0;
    var unknownDevices = 0;
    for (final device in devices) {
      final status = statuses[device.id];
      if (status != null) {
        if (status.hasFreeSlot) availableDevices++;
        freeSlots += status.freeSlots;
        occupiedSlots += status.occupiedSlots;
      } else if (failures[device.id] != null) {
        unknownDevices++;
      } else if (loading) {
        // Query is in flight; do not count it as an error yet.
      } else {
        unknownDevices++;
      }
    }
    return _Summary(
      totalDevices: devices.length,
      availableDevices: availableDevices,
      freeSlots: freeSlots,
      occupiedSlots: occupiedSlots,
      unknownDevices: unknownDevices,
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final _Summary summary;

  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _SummaryItem(
              label: '有位桩',
              value: '${summary.availableDevices}/${summary.totalDevices}',
              color: colorScheme.primary,
            ),
            _SummaryItem(
              label: '空位',
              value: '${summary.freeSlots}',
              color: Colors.green.shade700,
            ),
            _SummaryItem(
              label: '占用',
              value: '${summary.occupiedSlots}',
              color: colorScheme.onSurfaceVariant,
            ),
            _SummaryItem(
              label: '未知',
              value: '${summary.unknownDevices}',
              color: colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final ChargingPileDevice device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pageState = context
        .dependOnInheritedWidgetOfExactType<_DeviceStateScope>()
        ?.state;
    final status = pageState?._statuses[device.id];
    final failure = pageState?._failures[device.id];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                      ),
                      Text(
                        device.location,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: status, failure: failure),
              ],
            ),
            const SizedBox(height: 10),
            if (status != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    status.slots
                        .map((slot) => _SlotIndicator(slot: slot))
                        .toList(growable: false),
              )
            else if (failure != null)
              Text(
                failure.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: failure.authFailure
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              )
            else
              Text(
                '查询中…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
class _StatusBadge extends StatelessWidget {
  final ChargingPileDeviceStatus? status;
  final ChargingPileDeviceFailure? failure;

  const _StatusBadge({required this.status, required this.failure});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (status != null) {
      final text =
          '${status!.freeSlots}/${status!.slots.length} 空';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              status!.hasFreeSlot
                  ? Colors.green.withValues(alpha: 0.12)
                  : colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color:
                status!.hasFreeSlot
                    ? Colors.green.shade800
                    : colorScheme.onErrorContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return Text(
      failure?.authFailure ?? false ? '凭证失效' : '未知',
      style: theme.textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SlotIndicator extends StatelessWidget {
  final ChargingPileSlot slot;

  const _SlotIndicator({required this.slot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: 42,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            slot.free
                ? Colors.green.withValues(alpha: 0.14)
                : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${slot.slotId}',
        style: theme.textTheme.labelMedium?.copyWith(
          color:
              slot.free
                  ? Colors.green.shade800
                  : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DeviceStateScope extends InheritedWidget {
  final _ChargingPilePageState state;

  const _DeviceStateScope({
    required this.state,
    required super.child,
  });

  @override
  bool updateShouldNotify(_DeviceStateScope oldWidget) => true;
}
