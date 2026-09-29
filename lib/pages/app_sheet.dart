import 'package:flutter/material.dart';

import '../apps/app.dart';
import '../capabilities/dev_visibility.dart';
import '../services/development_mode_service.dart';
export '../apps/app_target_router.dart';

/// Shows a shared feature detail surface: 功能简介、分类和开发信息。
Future<void> showAppDetailSheet(
  BuildContext context,
  AppDefinition plugin,
) async {
  final metadata = plugin.metadata;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      metadata.icon,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            metadata.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (metadata.requiresDev) ...[
                          const SizedBox(width: 8),
                          const DevBadge(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (metadata.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '功能简介',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(metadata.description),
              ],
              if (DevelopmentModeService.isDev) ...[
                const SizedBox(height: 16),
                _DetailLine(label: '功能 ID', value: metadata.id),
              ],
              _DetailLine(label: '分类', value: metadata.category.label),
            ],
          ),
        ),
  );
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
