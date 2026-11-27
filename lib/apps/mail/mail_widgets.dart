import 'package:flutter/material.dart';

import '../../services/mail/mail_models.dart';

String formatMailDate(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  final local = date.toLocal();
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(local.year, local.month, local.day);
  String two(int value) => value.toString().padLeft(2, '0');
  if (target == today) return '${two(local.hour)}:${two(local.minute)}';
  if (local.year == current.year) return '${local.month}月${local.day}日';
  return '${local.year}/${local.month}/${local.day}';
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 附件展示名：去掉控制字符，空名回退为「附件」，限制长度。
///
/// 路径分隔符与 Windows 保留名由 `FileSaveService` 在保存时继续处理。
String mailDisplayFileName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return '附件';
  return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
}

class MailEmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const MailEmptyCard({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colors.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class MailListTile extends StatelessWidget {
  final MailHeader header;
  final bool selected;
  final VoidCallback onTap;

  const MailListTile({
    super.key,
    required this.header,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = !header.isRead;
    final sender = header.from?.displayName ?? '未知发件人';

    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(label: header.from?.initial ?? '?', highlighted: unread),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatMailDate(header.date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (unread) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            header.displaySubject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (header.hasAttachments) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.attach_file,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _Avatar({required this.label, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            highlighted
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color:
              highlighted ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
