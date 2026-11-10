import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'charging_pile_http_client.dart';
import 'charging_pile_models.dart';

/// 站点 `/api/stats` 里一个分区在一个小时上的采样。
class ChargingPileStatsSample {
  const ChargingPileStatsSample({
    this.percent,
    this.free,
    this.total,
  });

  /// 占用率百分比；该小时没有采到数据时为 null。
  final double? percent;
  final int? free;
  final int? total;

  /// 采样时刻相对该小时整点的滞后秒数。

  bool get hasData => percent != null;
}

/// 站点 `/api/stats` 的一个小时点。
class ChargingPileStatsPoint {
  const ChargingPileStatsPoint({
    required this.hour,
    required this.areas,
    required this.coverage,
    this.overall,
  });

  final DateTime hour;
  final Map<String, ChargingPileStatsSample> areas;

  /// 该小时真正采到的分区数。**这是「凑齐」判定的分母**，不是今天的分区总数。
  final int coverage;
  final double? overall;
}

/// 一周回顾数据。
class ChargingPileStats {
  const ChargingPileStats({required this.points, this.updatedAt});

  final List<ChargingPileStatsPoint> points;
  final DateTime? updatedAt;

  bool get isEmpty => points.isEmpty;

  /// 某分区的七天平均占用率；该分区一个点都没有时返回 null。
  double? averagePercent(String statsKey) {
    var sum = 0.0;
    var count = 0;
    for (final point in points) {
      final sample = point.areas[statsKey];
      final percent = sample?.percent;
      if (percent == null) continue;
      sum += percent;
      count += 1;
    }
    if (count == 0) return null;
    return sum / count;
  }

  /// 该分区最近一个有数据的点。
  ChargingPileStatsSample? latestSample(String statsKey) {
    for (final point in points.reversed) {
      final sample = point.areas[statsKey];
      if (sample?.hasData == true) return sample;
    }
    return null;
  }

  /// 该分区在给定小时上「本该有几个分区」（用该点自己的键数）。
  int expectedAreas(ChargingPileStatsPoint point) =>
      point.areas.isEmpty ? point.coverage : point.areas.length;

  /// 24 小时平均占用率（按站点口径：北京时间整点，逐小时对全部点求平均）。
  List<double?> hourlyAverage() {
    final sums = List<double>.filled(24, 0);
    final counts = List<int>.filled(24, 0);
    for (final point in points) {
      final percent = point.overall;
      if (percent == null) continue;
      final hour = point.hour.toUtc().add(const Duration(hours: 8)).hour;
      sums[hour] += percent;
      counts[hour] += 1;
    }
    return [
      for (var hour = 0; hour < 24; hour++)
        counts[hour] == 0 ? null : sums[hour] / counts[hour],
    ];
  }
}

/// 站点统计接口的只读客户端。
///
/// 边缘缓存 300 秒（响应头 `max-age=300`），客户端再按 5 分钟去重，
/// 与站点 `RV_TTL_MS` 一致。
class ChargingPileStatsClient {
  ChargingPileStatsClient({
    ChargingPileHttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
    this.ttl = const Duration(minutes: 5),
  }) : _http = httpClient ?? ChargingPileHttpClient(),
       _ownsClient = httpClient == null;

  static final Uri endpoint = Uri.parse('https://chd-charge.pages.dev/api/stats');

  final ChargingPileHttpClient _http;
  final bool _ownsClient;
  final Duration timeout;
  final Duration ttl;

  ChargingPileStats? _cached;
  DateTime? _cachedAt;

  Future<ChargingPileStats> fetch({bool force = false}) async {
    final cached = _cached;
    final at = _cachedAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < ttl) {
      return cached;
    }
    final response = await _http.get(endpoint, timeout: timeout);
    if (response.statusCode != 200) {
      throw const ChargingPileException(ChargingPileFailure.network);
    }
    final parsed = parse(utf8.decode(response.bodyBytes));
    _cached = parsed;
    _cachedAt = DateTime.now();
    return parsed;
  }

  /// 解析统计响应。字段缺失按「该点没数据」处理，不让一个坏点毁掉整份回顾。
  static ChargingPileStats parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    if (decoded['ok'] != true) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    final rawPoints = decoded['points'];
    if (rawPoints is! List) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
    final points = <ChargingPileStatsPoint>[];
    for (final raw in rawPoints) {
      if (raw is! Map) continue;
      final hourSeconds = _asInt(raw['h']);
      if (hourSeconds == null || hourSeconds <= 0) continue;
      final areas = <String, ChargingPileStatsSample>{};
      final rawAreas = raw['areas'];
      if (rawAreas is Map) {
        for (final entry in rawAreas.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is! String || value is! Map) continue;
          areas[key] = ChargingPileStatsSample(
            percent: _asDouble(value['pct']),
            free: _asInt(value['free']),
            total: _asInt(value['total']),
          );
        }
      }
      points.add(
        ChargingPileStatsPoint(
          hour: DateTime.fromMillisecondsSinceEpoch(
            hourSeconds * 1000,
            isUtc: true,
          ),
          areas: areas,
          coverage: _asInt(raw['coverage']) ?? areas.length,
          overall: _asDouble(raw['all']),
        ),
      );
    }
    points.sort((a, b) => a.hour.compareTo(b.hour));
    final updatedSeconds = _asInt(decoded['updated']);
    return ChargingPileStats(
      points: points,
      updatedAt: updatedSeconds == null || updatedSeconds <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              updatedSeconds * 1000,
              isUtc: true,
            ),
    );
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    return null;
  }

  static double? _asDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    return null;
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}

/// 「一周回顾 / 各时段占用率」面板。
///
/// 数据来自站点 `/api/stats`，分区与统计键的对应关系来自目录文档
/// （`ChargingPileArea.statsKey`），不在代码里重复一遍。
Future<void> showChargingPileStats(
  BuildContext context, {
  required List<ChargingPileArea> areas,
  ChargingPileStatsClient? client,
}) {
  final statsClient = client ?? ChargingPileStatsClient();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ChargingPileStatsSheet(
      areas: areas.where((area) => area.statsKey != null).toList(growable: false),
      client: statsClient,
    ),
  ).whenComplete(statsClient.close);
}

class _ChargingPileStatsSheet extends StatefulWidget {
  const _ChargingPileStatsSheet({required this.areas, required this.client});

  final List<ChargingPileArea> areas;
  final ChargingPileStatsClient client;

  @override
  State<_ChargingPileStatsSheet> createState() => _ChargingPileStatsSheetState();
}

class _ChargingPileStatsSheetState extends State<_ChargingPileStatsSheet> {
  ChargingPileStats? _stats;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final stats = await widget.client.fetch(force: true);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _stats;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('一周回顾', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed || stats == null || stats.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _failed ? '云端统计暂时取不到' : '这一周还没有统计点',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._areaRows(theme, stats),
                      const SizedBox(height: 20),
                      Text('各时段占用率', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _HourlyBars(values: stats.hourlyAverage()),
                      if (stats.updatedAt != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '更新于 ${_formatHour(stats.updatedAt!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _areaRows(ThemeData theme, ChargingPileStats stats) {
    final rows = <Widget>[];
    for (final area in widget.areas) {
      final key = area.statsKey!;
      final average = stats.averagePercent(key);
      final latest = stats.latestSample(key);
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(area.label)),
              Text(
                average == null ? '无数据' : '${average.toStringAsFixed(1)}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Text(
                  latest?.free == null || latest?.total == null
                      ? ''
                      : '剩 ${latest!.free} / ${latest.total}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  static String _formatHour(DateTime utc) {
    final local = utc.toUtc().add(const Duration(hours: 8));
    return '${local.month}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:00';
  }
}

/// 24 根柱子的时段占用率；缺失小时留空。
class _HourlyBars extends StatelessWidget {
  const _HourlyBars({required this.values});

  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var hour = 0; hour < values.length; hour++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor:
                            values[hour] == null
                                ? 0
                                : (math.max(values[hour]!, 2) / 100).clamp(
                                  0.02,
                                  1,
                                ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.7,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var hour = 0; hour < values.length; hour += 6)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(
                    '$hour',
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
