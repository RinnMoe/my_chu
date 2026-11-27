import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../apps/app.dart';
import 'root_destination_active_scope.dart';

final _pendingNotices = <String>{};

/// Prompts once per feature on this installation, using the stable feature ID.
Future<bool> acknowledgeBetaFeature(
  BuildContext context,
  AppMetadata metadata,
) async {
  final key = 'preferences.v1.beta_acknowledged.${metadata.id}';
  if (!_pendingNotices.add(key)) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return true;
    if (!context.mounted || !RootDestinationActiveScope.activeOf(context)) {
      return false;
    }
    final description = metadata.BETA_DES?.trim() ?? '';
    final acknowledged = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            title: const Text('测试中的功能'),
            content: Text(
              [
                '这是一项测试中的功能，可能存在预期外的异常。欢迎试用和反馈。',
                if (description.isNotEmpty) description,
              ].join('\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('知道了'),
              ),
            ],
          ),
    );
    if (acknowledged != true) return false;
    await prefs.setBool(key, true);
    return true;
  } finally {
    _pendingNotices.remove(key);
  }
}

/// Shows the same notice when a registered feature is opened as a root tab.
class BetaFeatureTab extends StatefulWidget {
  final AppMetadata metadata;
  final Widget child;

  const BetaFeatureTab({
    super.key,
    required this.metadata,
    required this.child,
  });

  @override
  State<BetaFeatureTab> createState() => _BetaFeatureTabState();
}

class _BetaFeatureTabState extends State<BetaFeatureTab> {
  bool _acknowledged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_acknowledged || !RootDestinationActiveScope.activeOf(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _acknowledged) return;
      _acknowledged = await acknowledgeBetaFeature(context, widget.metadata);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'BETA',
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.brown.shade900,
            fontWeight: FontWeight.w700,
            height: 1.25,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
