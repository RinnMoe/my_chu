import 'package:flutter/widgets.dart';

/// Describes whether a retained root destination is currently selected.
class RootDestinationActiveScope extends InheritedWidget {
  final bool active;

  const RootDestinationActiveScope({
    super.key,
    required this.active,
    required super.child,
  });

  static bool activeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RootDestinationActiveScope>()
            ?.active ??
        true;
  }

  @override
  bool updateShouldNotify(RootDestinationActiveScope oldWidget) {
    return active != oldWidget.active;
  }
}
