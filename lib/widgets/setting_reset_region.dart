import 'package:flutter/material.dart';

/// Consistent long-press reset, including switch and segmented controls.
class SettingResetRegion extends StatelessWidget {
  const SettingResetRegion({
    super.key,
    required this.onReset,
    required this.child,
  });
  final VoidCallback onReset;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: onReset,
    child: child,
  );
}
