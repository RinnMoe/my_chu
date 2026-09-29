import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/host_permission_service.dart';

/// Shows a short, non-blocking purpose card at the top of the current app
/// surface before the Android permission dialog is opened.
Future<HostPermissionPromptHandle?> presentHostPermissionPurpose(
  BuildContext context,
  HostPermissionPurpose purpose,
) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      final top = MediaQuery.of(overlayContext).padding.top + 12;
      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: _HostPermissionPurposeCard(purpose: purpose),
      );
    },
  );
  overlay.insert(entry);
  await WidgetsBinding.instance.endOfFrame;

  return HostPermissionPromptHandle(() {
    if (entry.mounted) entry.remove();
  });
}

class _HostPermissionPurposeCard extends StatelessWidget {
  final HostPermissionPurpose purpose;

  const _HostPermissionPurposeCard({required this.purpose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _permissionIcon(purpose.permission),
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    purpose.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    purpose.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _permissionIcon(Permission permission) {
  if (permission == Permission.notification) {
    return Icons.notifications_outlined;
  }
  if (permission == Permission.locationWhenInUse) {
    return Icons.location_on_outlined;
  }
  if (permission == Permission.camera) return Icons.camera_alt_outlined;
  if (permission == Permission.microphone) return Icons.mic_none_outlined;
  return Icons.security_outlined;
}
