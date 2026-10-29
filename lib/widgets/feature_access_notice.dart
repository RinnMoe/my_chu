import 'package:flutter/material.dart';

import '../services/remote_feature_policy/feature_access_guard.dart';
import '../services/remote_feature_policy/remote_feature_policy_service.dart';

/// Presentation used for a blocked feature. Kept in one place so the notice
/// sheet and the runtime overlay stay consistent.
class FeatureAccessPresentation {
  const FeatureAccessPresentation({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  static FeatureAccessPresentation of(FeatureAccessDecision decision) {
    switch (decision.status) {
      case FeatureAccessStatus.maintenance:
        return FeatureAccessPresentation(
          icon: Icons.construction_outlined,
          title: '功能维护中',
          message: decision.message ?? FeatureAccessGuard.maintenanceMessage,
        );
      case FeatureAccessStatus.disabled:
        return FeatureAccessPresentation(
          icon: Icons.block_outlined,
          title: '功能已停用',
          message: decision.message ?? FeatureAccessGuard.disabledMessage,
        );
      case FeatureAccessStatus.unavailable:
        return FeatureAccessPresentation(
          icon: Icons.cloud_off_outlined,
          title: '暂时不可用',
          message: decision.message ?? FeatureAccessGuard.unavailableMessage,
        );
      case FeatureAccessStatus.developmentOnly:
        return FeatureAccessPresentation(
          icon: Icons.science_outlined,
          title: '当前版本不可用',
          message:
              decision.message ?? FeatureAccessGuard.developmentOnlyMessage,
        );
      case FeatureAccessStatus.notInstalled:
        return FeatureAccessPresentation(
          icon: Icons.extension_off_outlined,
          title: '尚未添加',
          message: decision.message ?? FeatureAccessGuard.notInstalledMessage,
        );
      case FeatureAccessStatus.unknownFeature:
        return FeatureAccessPresentation(
          icon: Icons.help_outline,
          title: '功能不可用',
          message: decision.message ?? FeatureAccessGuard.unknownFeatureMessage,
        );
      case FeatureAccessStatus.available:
      case FeatureAccessStatus.hidden:
        return FeatureAccessPresentation(
          icon: Icons.check_circle_outline,
          title: '功能可用',
          message: decision.message ?? '',
        );
    }
  }
}

/// Explains why an entry point refused to open a feature.
Future<void> showFeatureUnavailableNotice(
  BuildContext context,
  FeatureAccessDecision decision,
) {
  final presentation = FeatureAccessPresentation.of(decision);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FeatureStatusIcon(icon: presentation.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          presentation.title,
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  presentation.message,
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        ),
  );
}

/// Keeps an already-open feature page in sync with the policy snapshot.
///
/// When the policy blocks the feature the page stays mounted (in-flight work is
/// not cancelled, and this widget never claims otherwise) but every further
/// interaction is absorbed and the maintenance/disabled notice replaces the
/// visible surface. Returning to `enabled` restores the page immediately.
class FeatureAccessHost extends StatefulWidget {
  const FeatureAccessHost({
    super.key,
    required this.featureId,
    required this.child,
  });

  final String featureId;
  final Widget child;

  @override
  State<FeatureAccessHost> createState() => _FeatureAccessHostState();
}

class _FeatureAccessHostState extends State<FeatureAccessHost> {
  RemoteFeaturePolicyService? _service;
  bool _childMounted = false;
  bool _cacheReady = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(FeatureAccessHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featureId != widget.featureId) _bind();
  }

  @override
  void dispose() {
    _service?.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _bind() {
    _service?.revision.removeListener(_onRevision);
    final service = RemoteFeaturePolicyService.instance;
    _service = service;
    service.revision.addListener(_onRevision);
    _cacheReady = false;
    service.initialize().then((_) {
      if (mounted && identical(_service, service)) {
        setState(() => _cacheReady = true);
      }
    });
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_cacheReady) return const SizedBox.shrink();
    final decision = FeatureAccessGuard.instance.decide(
      featureId: widget.featureId,
    );
    if (!decision.isBlocked) {
      _childMounted = true;
    }

    final presentation = FeatureAccessPresentation.of(decision);
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_childMounted)
          ExcludeFocus(
            excluding: decision.isBlocked,
            child: ExcludeSemantics(
              excluding: decision.isBlocked,
              child: IgnorePointer(
                ignoring: decision.isBlocked,
                child: widget.child,
              ),
            ),
          ),
        if (decision.isBlocked)
          ColoredBox(
            color: theme.colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FeatureStatusIcon(icon: presentation.icon, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        presentation.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        presentation.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (canPop) ...[
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('返回'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FeatureStatusIcon extends StatelessWidget {
  const _FeatureStatusIcon({required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: scheme.onSecondaryContainer, size: size * 0.55),
    );
  }
}
