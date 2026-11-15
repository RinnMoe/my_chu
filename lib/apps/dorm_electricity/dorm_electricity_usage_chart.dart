import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dorm_electricity_models.dart';
import 'dorm_electricity_period.dart';

/// Presentation only. Dates without a reading stay missing, including future
/// days, and negative corrections are drawn below the zero baseline.
class ElectricityUsageChart extends StatefulWidget {
  const ElectricityUsageChart({
    super.key,
    required this.period,
    required this.cost,
    required this.onCostChanged,
    required this.meters,
    required this.readings,
    required this.colors,
    this.titles,
  }) : assert(titles == null || titles.length == meters.length);
  final ElectricityPeriod period;
  final bool cost;
  final ValueChanged<bool> onCostChanged;
  final List<ElectricityMeterRecord> meters;
  final Map<String, List<ElectricityDailyUsage>> readings;
  final List<Color> colors;
  final List<String>? titles;

  @override
  State<ElectricityUsageChart> createState() => _ElectricityUsageChartState();
}

class _ElectricityUsageChartState extends State<ElectricityUsageChart> {
  int? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final dates = widget.period.dates;
    final days = dates.length;
    final readings = [
      for (final meter in widget.meters)
        <int, ElectricityDailyUsage>{
          for (final day
              in widget.readings[meter.meter.id] ??
                  const <ElectricityDailyUsage>[])
            if (dates.contains(
              DateTime.utc(day.date.year, day.date.month, day.date.day),
            ))
              dates.indexOf(
                        DateTime.utc(
                          day.date.year,
                          day.date.month,
                          day.date.day,
                        ),
                      ) +
                      1:
                  day,
        },
    ];
    final recordedDays = readings.expand((series) => series.keys);
    final latest = recordedDays.isEmpty ? 1 : recordedDays.reduce(math.max);
    final selected = _selectedDay ?? latest;
    String? value(int meter, int day) =>
        widget.cost ? readings[meter][day]?.amount : readings[meter][day]?.kwh;
    final series = [
      for (var meter = 0; meter < readings.length; meter++)
        [
          for (var day = 1; day <= days; day++)
            double.tryParse(value(meter, day) ?? ''),
        ],
    ];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            SegmentedButton<bool>(
              key: const ValueKey('electricity-metric-selector'),
              segments: const [
                ButtonSegment(value: false, label: Text('用电量')),
                ButtonSegment(value: true, label: Text('费用')),
              ],
              showSelectedIcon: false,
              selected: {widget.cost},
              onSelectionChanged:
                  (values) => widget.onCostChanged(values.single),
            ),
            Text(
              '${widget.cost ? '元' : '度'} / ${widget.period.scale == ElectricityScale.year ? '月' : '日'}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.period.scale == ElectricityScale.year
                    ? '${dates[selected - 1].year}年${dates[selected - 1].month}月'
                    : '${dates[selected - 1].month}月${dates[selected - 1].day}日',
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip:
                  widget.period.scale == ElectricityScale.year ? '上月读数' : '上一天',
              onPressed:
                  selected > 1
                      ? () => setState(() => _selectedDay = selected - 1)
                      : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip:
                  widget.period.scale == ElectricityScale.year ? '下月读数' : '下一天',
              onPressed:
                  selected < days
                      ? () => setState(() => _selectedDay = selected + 1)
                      : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        for (var index = 0; index < widget.meters.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: widget.colors[index]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.titles?[index] ??
                        widget.meters[index].meter.name ??
                        widget.meters[index].meter.displayName,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    value(index, selected) == null
                        ? '暂无记录'
                        : '${value(index, selected)} ${widget.cost ? '元' : '度'}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            void select(Offset position) {
              final day =
                  ((position.dx - _UsagePainter.left) /
                          (constraints.maxWidth - _UsagePainter.left - 8) *
                          days)
                      .floor() +
                  1;
              setState(() => _selectedDay = day.clamp(1, days));
            }

            return Semantics(
              label: widget.cost ? '费用柱状图' : '用电量柱状图',
              child: GestureDetector(
                onTapDown: (details) => select(details.localPosition),
                onHorizontalDragUpdate:
                    (details) => select(details.localPosition),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _UsagePainter(
                      series: series,
                      labels: [
                        for (final date in dates)
                          widget.period.scale == ElectricityScale.week
                              ? const [
                                '一',
                                '二',
                                '三',
                                '四',
                                '五',
                                '六',
                                '日',
                              ][date.weekday - 1]
                              : '${widget.period.scale == ElectricityScale.year ? date.month : date.day}',
                      ],
                      colors: widget.colors,
                      selectedDay: selected,
                      gridColor: theme.colorScheme.outlineVariant,
                      labelStyle: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      textDirection: Directionality.of(context),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _UsagePainter extends CustomPainter {
  _UsagePainter({
    required this.series,
    required this.labels,
    required this.colors,
    required this.selectedDay,
    required this.gridColor,
    required this.labelStyle,
    required this.textDirection,
  });
  static const left = 42.0;
  final List<List<double?>> series;
  final List<String> labels;
  final List<Color> colors;
  final int selectedDay;
  final Color gridColor;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final values = series.expand((row) => row).whereType<double>();
    final maximum = values.fold(0.0, math.max);
    final minimum = values.fold(0.0, math.min);
    final top = maximum == 0 && minimum == 0 ? 1.0 : maximum;
    final span = top - minimum;
    final height = size.height - 28;
    final width = size.width - left - 8;
    final days = series.first.length;
    final step = width / days;
    double y(double value) => 4 + (top - value) / span * (height - 8);
    void label(String text, Offset offset) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: textDirection,
      )..layout();
      painter.paint(canvas, offset);
    }

    final cursorX = left + (selectedDay - .5) * step;
    canvas.drawLine(
      Offset(cursorX, 0),
      Offset(cursorX, height),
      Paint()
        ..color = gridColor.withValues(alpha: .6)
        ..strokeWidth = 1,
    );
    for (final tick in {top, minimum, 0.0}) {
      final axis = y(tick);
      if (tick != 0 && (axis - y(0)).abs() < 18) continue;
      canvas.drawLine(
        Offset(left, axis),
        Offset(size.width - 8, axis),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1,
      );
      label(_axisLabel(tick), Offset(0, axis - 6));
    }
    final groupWidth = step * .72;
    final barWidth = groupWidth / series.length;
    for (var meter = 0; meter < series.length; meter++) {
      for (var day = 0; day < days; day++) {
        final value = series[meter][day];
        if (value == null) continue;
        final x =
            left + day * step + (step - groupWidth) / 2 + meter * barWidth;
        final baseline = y(0);
        final valueY = y(value);
        // A zero is a short baseline mark. Missing values have no mark.
        final rect = Rect.fromLTWH(
          x,
          math.min(baseline, valueY) - (value == 0 ? 1 : 0),
          math.max(.5, barWidth - 1),
          math.max(2, (baseline - valueY).abs()),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color = colors[meter].withValues(
              alpha: day + 1 == selectedDay ? 1 : .75,
            ),
        );
      }
    }
    final interval =
        days > 20
            ? 7
            : days > 8
            ? 2
            : 1;
    for (var day = 0; day < days; day += interval) {
      label(labels[day], Offset(left + (day + .5) * step - 4, height + 8));
    }
  }

  String _axisLabel(double value) {
    if (value == 0) return '0';
    final absolute = value.abs();
    if (absolute >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (absolute >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    final decimals =
        absolute >= 100
            ? 0
            : absolute >= 10
            ? 1
            : (2 - math.log(absolute) / math.ln10).floor().clamp(0, 6);
    return value.toStringAsFixed(decimals);
  }

  @override
  bool shouldRepaint(_UsagePainter oldDelegate) => true;
}
