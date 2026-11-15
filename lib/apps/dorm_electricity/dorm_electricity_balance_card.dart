import 'package:flutter/material.dart';

import '../../capabilities/dorm_electricity.dart';
import 'dorm_electricity_models.dart';

class ElectricityBalanceCard extends StatelessWidget {
  const ElectricityBalanceCard({
    super.key,
    required this.record,
    required this.title,
    required this.color,
    required this.stale,
    required this.onRetry,
    this.error,
  });

  final ElectricityMeterRecord record;
  final String title;
  final Color color;
  final bool stale;
  final VoidCallback onRetry;
  final DormElectricityException? error;

  String _time(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  void _details(BuildContext context) {
    final balance = record.balance;
    final values = <String, String?>{
      '表号': record.meter.id,
      '预付费余额': balance.prepaid == null ? null : '${balance.prepaid} 元',
      '补助余额': balance.subsidy == null ? null : '${balance.subsidy} 元',
      '累计电量': balance.totalKwh == null ? null : '${balance.totalKwh} 度',
      '闸位': balance.status,
      '抄表时间': balance.readingTime,
      '查询时间': '${balance.fetchedAt.toLocal().year}-${_time(balance.fetchedAt)}',
    };
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .85,
                maxWidth: 640,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    for (final entry in values.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Text(
                                entry.value ?? '—',
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = record.balance;
    final negative = (double.tryParse(balance.total ?? '') ?? 0) < 0;
    final status = balance.status?.split(RegExp(r'[-|]')).first.trim();
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _details(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(color: color),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  balance.total == null ? '—' : '¥ ${balance.total}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color:
                        negative
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                status == null || status.isEmpty ? '闸位未知' : status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      status?.contains('跳闸') == true
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _time(balance.fetchedAt),
                semanticsLabel:
                    '${stale ? '上次查询' : '查询时间'} ${_time(balance.fetchedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: theme.colorScheme.error,
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: onRetry,
                  child: const Text('未更新，重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
