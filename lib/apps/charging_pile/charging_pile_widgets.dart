import 'package:flutter/material.dart';

import 'charging_pile_models.dart';

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
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          updatedDevices == 0 ? '空闲插座 —' : '空闲插座 $freeSlots / $knownSlots',
          style: theme.textTheme.titleMedium?.copyWith(color: colors.primary),
        ),
        Text(
          updatedDevices == totalDevices
              ? '$totalDevices 台'
              : '已更新 $updatedDevices/$totalDevices 台',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (latest != null)
          Semantics(
            label: '最近成功更新时间 ${chargingPileTime(latest!, now)}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  chargingPileTime(latest!, now),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ChargingPilePorts extends StatelessWidget {
  const ChargingPilePorts({
    super.key,
    required this.slots,
    this.compact = false,
  });
  final List<ChargingPileSlot> slots;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (slots.isEmpty) return const SizedBox.shrink();

    Widget port(ChargingPileSlot slot) {
      final available = slot.free;
      final label =
          slot.free
              ? '空闲'
              : slot.occupied
              ? '占用'
              : '状态 ${slot.status}';
      final foreground =
          available
              ? (compact ? colors.onPrimary : colors.onPrimaryContainer)
              : colors.onSurfaceVariant;
      return Semantics(
        label: '${slot.slotId} 号插座，$label',
        excludeSemantics: true,
        child: ColoredBox(
          color:
              available
                  ? (compact ? colors.primary : colors.primaryContainer)
                  : colors.surfaceContainerHighest,
          child: Padding(
            padding:
                compact
                    ? const EdgeInsets.symmetric(vertical: 5)
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child:
                compact
                    ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${slot.slotId}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground,
                          ),
                        ),
                        if (slot.free || !slot.occupied) ...[
                          const SizedBox(width: 2),
                          Icon(
                            slot.free ? Icons.check : Icons.help_outline,
                            size: 12,
                            color: foreground,
                          ),
                        ],
                      ],
                    )
                    : Column(
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
    }

    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final columns =
              (constraints.maxWidth / (30 * scale.clamp(1.0, 2.0)))
                  .floor()
                  .clamp(1, slots.length.clamp(1, 4))
                  .toInt();
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Wrap(
              runSpacing: 1,
              children:
                  slots
                      .map(
                        (slot) => SizedBox(
                          width: constraints.maxWidth / columns,
                          child: port(slot),
                        ),
                      )
                      .toList(),
            ),
          );
        },
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          slots
              .map(
                (slot) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: port(slot),
                ),
              )
              .toList(),
    );
  }
}

class ChargingPileDeviceCard extends StatelessWidget {
  const ChargingPileDeviceCard({
    super.key,
    required this.device,
    required this.entry,
    required this.loading,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    this.showArea = true,
  });
  final ChargingPileDevice device;
  final ChargingPileDeviceState entry;
  final bool loading;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final bool showArea;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = entry.status;
    final confirmedFree = status != null && status.freeSlots > 0;
    return Card.filled(
      margin: EdgeInsets.zero,
      color:
          confirmedFree ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          label: '${device.code} 号桩',
                          excludeSemantics: true,
                          child: Text(
                            device.code,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color:
                                  confirmedFree
                                      ? colors.onPrimaryContainer
                                      : colors.onSurface,
                            ),
                          ),
                        ),
                        if (showArea)
                          Text(
                            device.area.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  confirmedFree
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                            ),
                          ),
                        if (status != null)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${status.freeSlots}/${status.slots.length} 空闲',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      confirmedFree
                                          ? colors.onPrimaryContainer
                                          : colors.onSurfaceVariant,
                                ),
                              ),
                              if (loading)
                                SizedBox.square(
                                  dimension: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: '正在刷新 ${device.code}',
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: favorite ? '取消收藏' : '收藏',
                    isSelected: favorite,
                    selectedIcon: const Icon(Icons.star_rounded),
                    icon: const Icon(Icons.star_outline_rounded),
                    onPressed: onFavorite,
                    color:
                        confirmedFree
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (status != null) ...[
                ChargingPilePorts(slots: status.slots, compact: true),
              ] else
                Text(
                  loading ? '查询中…' : entry.failure?.message ?? '尚未查询',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
