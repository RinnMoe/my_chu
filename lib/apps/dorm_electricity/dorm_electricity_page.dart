import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/dorm_electricity.dart';
import '../../capabilities/east8_time.dart';
import '../../widgets/root_destination_active_scope.dart';
import 'dorm_electricity_models.dart';
import 'dorm_electricity_period.dart';
import 'dorm_electricity_balance_card.dart';
import 'dorm_electricity_usage_chart.dart';
import 'dorm_electricity_picker.dart';
import 'dorm_electricity_repository.dart';

class DormElectricityPage extends StatefulWidget {
  const DormElectricityPage({super.key, this.repository});
  final ElectricityRepository? repository;
  @override
  State<DormElectricityPage> createState() => _DormElectricityPageState();
}

class _DormElectricityPageState extends State<DormElectricityPage>
    with WidgetsBindingObserver {
  late final ElectricityRepository _repository;
  bool _ready = false, _active = true, _foreground = true;
  bool _details = false, _periodPickerOpen = false, _cost = false;
  final _periodMenu = MenuController();
  late int _pickerYear;
  String? _displayedMeters;
  String? _restoreError;
  late ElectricityPeriod _period;

  /// The body column stays centered and capped so tablets do not stretch rows.
  static const _contentMaxWidth = 760.0;
  static const _bodyPadding = 24.0;
  static const _appBarTitleSpacing = 16.0;

  @override
  void initState() {
    super.initState();
    final now = east8Now();
    _period = ElectricityPeriod(ElectricityScale.week, now);
    _pickerYear = now.year;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _repository = widget.repository ?? ElectricityRepository();
    _repository.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    setState(() {
      _ready = false;
      _restoreError = null;
    });
    try {
      await _repository.restore();
    } on DormElectricityException catch (error) {
      _restoreError = error.message;
    }
    if (!mounted) return;
    setState(() => _ready = true);
    if (_active && _foreground) unawaited(_refresh());
  }

  void _changed() {
    final meters = _repository.record?.meters.map((m) => m.meter.id).join('|');
    if (meters != _displayedMeters) {
      _displayedMeters = meters;
      _details = false;
      _periodMenu.close();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        RootDestinationActiveScope.activeOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_active == active) return;
    _active = active;
    if (!active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_active) _periodMenu.close();
      });
      _repository.cancelPending();
    } else if (_ready && _foreground) {
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _periodMenu.close();
      _repository.cancelPending();
    } else if (_active && _ready) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (!_active || !_foreground || !_ready) return;
    await _repository.refresh(force: force);
    if (mounted && _active && _foreground) {
      await _loadPeriod(force: force);
    }
  }

  Future<void> _choose() async {
    await showElectricityPicker(context, _repository);
    if (!mounted) return;
    setState(() {
      if (_repository.record != null) _restoreError = null;
    });
    unawaited(_refresh());
  }

  void _setPeriod(ElectricityPeriod period) {
    _periodMenu.close();
    setState(() => _period = period);
    if (_active && _foreground) unawaited(_loadPeriod());
  }

  Future<void> _loadPeriod({bool force = false}) async {
    final period = _period;
    await _repository.loadPeriod(period, force: force);
    if (mounted && _active && _foreground && _period.key == period.key) {
      unawaited(_repository.preload(period));
    }
  }

  Widget _periodControls() {
    final now = east8Now();
    final current = ElectricityPeriod(_period.scale, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: SegmentedButton<ElectricityScale>(
            key: const ValueKey('electricity-scale-selector'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ElectricityScale.week, label: Text('周')),
              ButtonSegment(value: ElectricityScale.month, label: Text('月')),
              ButtonSegment(value: ElectricityScale.year, label: Text('年')),
            ],
            selected: {_period.scale},
            onSelectionChanged: (values) {
              final anchor =
                  _period.end.isAfter(
                        DateTime.utc(now.year, now.month, now.day),
                      )
                      ? now
                      : _period.anchor;
              _setPeriod(ElectricityPeriod(values.single, anchor));
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: '上一时段',
              onPressed:
                  _period.start.year > 2000
                      ? () => _setPeriod(_period.shifted(-1))
                      : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = MediaQuery.sizeOf(context);
                  final width = (size.width - 32).clamp(0.0, 384.0);
                  return PopScope<void>(
                    canPop: !_periodPickerOpen,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _periodMenu.close();
                    },
                    child: MenuAnchor(
                      controller: _periodMenu,
                      consumeOutsideTap: true,
                      alignmentOffset: Offset(
                        (constraints.maxWidth - width) / 2,
                        8,
                      ),
                      style: MenuStyle(
                        alignment: AlignmentDirectional.bottomStart,
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        maximumSize: WidgetStatePropertyAll(
                          Size(
                            width,
                            size.height -
                                MediaQuery.paddingOf(context).vertical -
                                32,
                          ),
                        ),
                        shape: const WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                      ),
                      onOpen: () => setState(() => _periodPickerOpen = true),
                      onClose: () => setState(() => _periodPickerOpen = false),
                      menuChildren: [
                        SizedBox(
                          width: width,
                          child: Padding(
                            key: const ValueKey('electricity-period-menu'),
                            padding: const EdgeInsets.all(16),
                            child: _periodPicker(now, width - 32),
                          ),
                        ),
                      ],
                      builder:
                          (context, controller, child) => TextButton(
                            key: const ValueKey('electricity-period-selector'),
                            onPressed: () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                setState(
                                  () => _pickerYear = _period.anchor.year,
                                );
                                controller.open();
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _period.label,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Icon(
                                  _periodPickerOpen
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: '下一时段',
              onPressed:
                  _period.start.isBefore(current.start)
                      ? () => _setPeriod(_period.shifted(1))
                      : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Widget _periodPicker(DateTime now, double width) => FocusScope(
    autofocus: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: _period.scale == ElectricityScale.year ? '更早年份' : '上一年',
              onPressed:
                  (_period.scale == ElectricityScale.year
                              ? _pickerYear - 11
                              : _pickerYear) >
                          2000
                      ? () => _browseYear(-1)
                      : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              _period.scale == ElectricityScale.year
                  ? '${(_pickerYear - 11).clamp(2000, now.year)}—$_pickerYear'
                  : '$_pickerYear 年',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            IconButton(
              tooltip: _period.scale == ElectricityScale.year ? '更晚年份' : '下一年',
              onPressed: _pickerYear < now.year ? () => _browseYear(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        _periodChoices(now, width),
      ],
    ),
  );

  Widget _periodChoices(DateTime now, double availableWidth) {
    final yearly = _period.scale == ElectricityScale.year;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = (availableWidth / (72 * scale)).floor().clamp(2, 4);
    final width = (availableWidth - (columns - 1) * 8) / columns;
    final first = yearly ? (_pickerYear - 11).clamp(2000, now.year) : 1;
    final last = yearly ? _pickerYear : 12;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var value = first; value <= last; value++)
          SizedBox(
            width: width,
            child: ChoiceChip(
              showCheckmark: false,
              label: Center(child: Text(yearly ? '$value' : '$value 月')),
              selected:
                  yearly
                      ? _period.anchor.year == value
                      : _period.anchor.year == _pickerYear &&
                          _period.anchor.month == value,
              onSelected:
                  yearly || _pickerYear < now.year || value <= now.month
                      ? (_) {
                        var anchor =
                            yearly
                                ? DateTime.utc(value)
                                : DateTime.utc(_pickerYear, value);
                        if (!yearly &&
                            _pickerYear == now.year &&
                            value == now.month) {
                          anchor = now;
                        } else if (_period.scale == ElectricityScale.week) {
                          anchor = anchor.add(
                            Duration(days: (8 - anchor.weekday) % 7),
                          );
                        }
                        _setPeriod(ElectricityPeriod(_period.scale, anchor));
                      }
                      : null,
            ),
          ),
      ],
    );
  }

  void _browseYear(int delta) => setState(() {
    final step = _period.scale == ElectricityScale.year ? 12 : 1;
    _pickerYear = (_pickerYear + delta * step).clamp(2000, east8Now().year);
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repository.removeListener(_changed);
    if (widget.repository == null) {
      _repository.dispose();
    } else {
      _repository.cancelPending();
    }
    super.dispose();
  }

  Widget _error(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );

  Widget _value(String title, String? value, {String unit = ''}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(title)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value == null ? '—' : '$value$unit',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );

  Color _meterColor(int index) =>
      index.isEven
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.tertiary;

  String _meterTitle(ElectricityMeterRecord meter, String label) {
    final name = meter.meter.name;
    if (name != null && name != label.replaceAll(' / ', '')) return name;
    final id = meter.meter.id;
    return '电表 ${id.substring(id.length - 4)}';
  }

  Widget _balances(ElectricityRecord record) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (constraints.maxWidth / (144 * textScale + 12))
          .floor()
          .clamp(1, 2);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var index = 0; index < record.meters.length; index++)
            SizedBox(
              width: width,
              child: ElectricityBalanceCard(
                key: ValueKey(record.meters[index].meter.id),
                record: record.meters[index],
                title: _meterTitle(record.meters[index], record.label),
                color: _meterColor(index),
                stale: _repository.isStale(record.meters[index].balance),
                error: _repository.balanceErrors[record.meters[index].meter.id],
                onRetry: () => unawaited(_refresh(force: true)),
              ),
            ),
        ],
      );
    },
  );

  Widget _billingDetails(ElectricityRecord record) {
    final theme = Theme.of(context);
    Widget cell(String value, {bool numeric = false, bool heading = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            value,
            textAlign: numeric ? TextAlign.end : TextAlign.start,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: heading ? theme.colorScheme.onSurfaceVariant : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < record.meters.length; index++)
          Builder(
            builder: (context) {
              final meter = record.meters[index];
              final readings = _repository.readings(_period, meter.meter.id);
              final byDate = {
                for (final day in readings)
                  DateTime.utc(day.date.year, day.date.month, day.date.day):
                      day,
              };
              final bill =
                  _repository
                      .billingByMonth[ElectricityPeriod.monthKey(
                        _period.start,
                      )]?[meter.meter.id]
                      ?.bill;
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _meterTitle(meter, record.label),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _meterColor(index),
                      ),
                    ),
                    if (_period.scale == ElectricityScale.month) ...[
                      _value('月用电量', bill?.kwh, unit: ' 度'),
                      _value('月电费', bill?.amount, unit: ' 元'),
                      _value('期初示数', bill?.start, unit: ' 度'),
                      _value('期末示数', bill?.end, unit: ' 度'),
                      const Divider(height: 24),
                    ],
                    Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FlexColumnWidth(1.1),
                        1: FlexColumnWidth(),
                        2: FlexColumnWidth(),
                      },
                      children: [
                        TableRow(
                          children: [
                            cell(
                              _period.scale == ElectricityScale.year
                                  ? '月份'
                                  : '日期',
                              heading: true,
                            ),
                            cell('用电量', numeric: true, heading: true),
                            cell('金额', numeric: true, heading: true),
                          ],
                        ),
                        for (final date in _period.dates)
                          TableRow(
                            children: [
                              cell(
                                _period.scale == ElectricityScale.year
                                    ? '${date.month}月'
                                    : '${date.month}/${date.day}',
                              ),
                              cell(
                                byDate[date]?.kwh == null
                                    ? '—'
                                    : '${byDate[date]!.kwh} 度',
                                numeric: true,
                              ),
                              cell(
                                byDate[date]?.amount == null
                                    ? '—'
                                    : '${byDate[date]!.amount} 元',
                                numeric: true,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _statistics(ElectricityRecord record) {
    final theme = Theme.of(context);
    final states = _repository.billingStates;
    final daily = _period.scale != ElectricityScale.year;
    final loading = states.any(
      (state) => state.loadingBill || (daily && state.loadingDaily),
    );
    // A failed month already renders its own error block; showing the empty
    // state next to it would claim there is no data for a period we never read.
    final hasErrors = states.any(
      (state) => state.billError != null || (daily && state.dailyError != null),
    );
    final readings = {
      for (final meter in record.meters)
        meter.meter.id: _repository.readings(_period, meter.meter.id),
    };
    final hasReadings = readings.values
        .expand((rows) => rows)
        .any((day) => day.kwh != null || day.amount != null);
    return SegmentedButtonTheme(
      data: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(72, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide.none,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          selectedBackgroundColor: theme.colorScheme.primaryContainer,
          selectedForegroundColor: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: TabBar(
                controller: null,
                tabs: const [Tab(text: '用电统计'), Tab(text: '账单明细')],
                onTap: (index) => setState(() => _details = index == 1),
                labelStyle: theme.textTheme.titleSmall,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _periodControls(),
          if (loading) const LinearProgressIndicator(),
          for (final month in _repository.billingByMonth.entries)
            for (var index = 0; index < record.meters.length; index++)
              Builder(
                builder: (context) {
                  final state = month.value[record.meters[index].meter.id];
                  final errors =
                      [
                        state?.billError,
                        if (daily) state?.dailyError,
                      ].whereType<DormElectricityException>();
                  if (errors.isEmpty) return const SizedBox.shrink();
                  return _error(
                    '${month.key} · ${_meterTitle(record.meters[index], record.label)}\n${errors.map((error) => error.message).toSet().join(' ')}',
                    () => unawaited(_loadPeriod(force: true)),
                  );
                },
              ),
          if (_details)
            _billingDetails(record)
          else if (!loading && !hasReadings && !hasErrors)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('该时段暂无用电记录。', textAlign: TextAlign.center),
            )
          else ...[
            const SizedBox(height: 8),
            ElectricityUsageChart(
              key: ValueKey(_period.key),
              period: _period,
              cost: _cost,
              onCostChanged: (cost) => setState(() => _cost = cost),
              meters: record.meters,
              titles: [
                for (final meter in record.meters)
                  _meterTitle(meter, record.label),
              ],
              readings: readings,
              colors: [
                for (var i = 0; i < record.meters.length; i++) _meterColor(i),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// On wide windows the centered body starts away from the screen edge, so the
  /// title follows the same left edge instead of hugging the AppBar.
  double _titleInset(BuildContext context) {
    final inset = (MediaQuery.sizeOf(context).width - _contentMaxWidth) / 2;
    if (inset <= 0) return 0;
    return inset + _bodyPadding - _appBarTitleSpacing;
  }

  @override
  Widget build(BuildContext context) {
    final record = _repository.record;
    return Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: EdgeInsets.only(left: _titleInset(context)),
          child: const Text('宿舍电费'),
        ),
        actions: [
          if (record != null || _restoreError != null)
            IconButton(
              tooltip: '更换宿舍',
              onPressed: () => unawaited(_choose()),
              icon: const Icon(Icons.swap_horiz),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(force: true),
        child: LayoutBuilder(
          builder:
              (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _contentMaxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child:
                          !_ready
                              ? const Center(child: CircularProgressIndicator())
                              : _restoreError != null
                              ? _error(
                                _restoreError!,
                                () => unawaited(_restore()),
                              )
                              : record == null
                              ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '尚未保存宿舍',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: _choose,
                                    child: const Text('选择宿舍'),
                                  ),
                                ],
                              )
                              : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    record.label,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  if (_repository.saveError != null)
                                    _error(
                                      _repository.saveError!.message,
                                      () => unawaited(_refresh(force: true)),
                                    ),
                                  if (_repository.loadingBalance)
                                    const LinearProgressIndicator(),
                                  const SizedBox(height: 24),
                                  Text(
                                    '电费余额',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 12),
                                  _balances(record),
                                  const SizedBox(height: 24),
                                  const Divider(height: 1),
                                  DefaultTabController(
                                    key: ValueKey(
                                      'usage-tabs:$_displayedMeters',
                                    ),
                                    length: 2,
                                    child: _statistics(record),
                                  ),
                                ],
                              ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
