import 'package:flutter/material.dart';

import '../../charging_piles/charging_pile_models.dart';

String chargingPileTime(DateTime value, DateTime now) {
  final local = value.toLocal();
  final today = now.toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
  return local.year == today.year &&
          local.month == today.month &&
          local.day == today.day
      ? time
      : '${local.month}/${local.day} $time';
}

class ChargingPileSummary extends StatelessWidget {
  const ChargingPileSummary({
    super.key,
    required this.freeSlots,
    required this.knownSlots,
    required this.updatedDevices,
    required this.totalDevices,
    required this.latest,
    required this.now,
  });
  final int freeSlots;
  final int knownSlots;
  final int updatedDevices;
  final int totalDevices;
  final DateTime? latest;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 32,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '空闲插座',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  updatedDevices == 0 ? '—' : '$freeSlots',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  updatedDevices == 0 ? '尚无实时数据' : '已统计 $knownSlots 个插座',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已更新 $updatedDevices / $totalDevices 台',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  latest == null
                      ? '选择分区后查询'
                      : '最近成功 ${chargingPileTime(latest!, now)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                if (updatedDevices < totalDevices) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${totalDevices - updatedDevices} 台未知或历史数据',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChargingPilePorts extends StatelessWidget {
  const ChargingPilePorts({
    super.key,
    required this.slots,
    this.historical = false,
  });
  final List<ChargingPileSlot> slots;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          slots.map((slot) {
            final available = slot.free && !historical;
            final foreground =
                available ? colors.onPrimaryContainer : colors.onSurfaceVariant;
            final label =
                slot.free
                    ? '空闲'
                    : slot.occupied
                    ? '占用'
                    : '状态 ${slot.status}';
            return Semantics(
              label: '${slot.slotId} 号插座，${historical ? '历史数据，' : ''}$label',
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color:
                      available
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${slot.slotId}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

class ChargingPileDeviceCard extends StatelessWidget {
  const ChargingPileDeviceCard({
    super.key,
    required this.device,
    required this.entry,
    required this.now,
    required this.loading,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    required this.onRefresh,
  });
  final ChargingPileDevice device;
  final ChargingPileCachedDevice entry;
  final DateTime now;
  final bool loading;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = entry.status;
    final historical = entry.isHistorical(now);
    final confirmedFree = !historical && status != null && status.freeSlots > 0;
    final badge =
        status == null
            ? (loading ? '查询中' : '未知')
            : '${historical ? '历史 ' : ''}${status.freeSlots}/${status.slots.length} 空闲';
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${device.code} 号桩',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            device.area.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: favorite ? '取消收藏' : '收藏',
                    isSelected: favorite,
                    selectedIcon: const Icon(Icons.star_rounded),
                    icon: const Icon(Icons.star_outline_rounded),
                    onPressed: onFavorite,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color:
                      confirmedFree
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          confirmedFree
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (status != null)
                ChargingPilePorts(slots: status.slots, historical: historical)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    loading
                        ? '正在查询插座状态…'
                        : entry.failure?.message ?? '尚未查询插座状态',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (historical) ...[
                    Icon(
                      Icons.history,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      status == null
                          ? (loading ? '查询中' : '暂无更新时间')
                          : '${historical ? '历史' : '更新'} ${chargingPileTime(status.fetchedAt, now)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新 ${device.code}',
                    onPressed: loading ? null : onRefresh,
                    icon:
                        loading
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
