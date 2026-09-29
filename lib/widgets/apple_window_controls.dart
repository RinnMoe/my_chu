import 'dart:async';

import 'package:flutter/material.dart';

import '../services/apple_window_controls_service.dart';

/// Publishes native iOS corner-adaptation metrics to Material app bars.
class AppleWindowControlsMetricsScope extends StatefulWidget {
  const AppleWindowControlsMetricsScope({
    super.key,
    required this.child,
    this.metricsStream,
    this.initialMetrics = const AppleWindowControlsMetrics.zero(),
  });

  final Widget child;
  final Stream<AppleWindowControlsMetrics>? metricsStream;
  final AppleWindowControlsMetrics initialMetrics;

  static AppleWindowControlsMetrics of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<
              _AppleWindowControlsMetricsInherited
            >()
            ?.metrics ??
        const AppleWindowControlsMetrics.zero();
  }

  @override
  State<AppleWindowControlsMetricsScope> createState() =>
      _AppleWindowControlsMetricsScopeState();
}

class _AppleWindowControlsMetricsScopeState
    extends State<AppleWindowControlsMetricsScope> {
  StreamSubscription<AppleWindowControlsMetrics>? _subscription;
  late AppleWindowControlsMetrics _metrics;

  @override
  void initState() {
    super.initState();
    _metrics = widget.initialMetrics;
    _subscribe(
      widget.metricsStream ?? AppleWindowControlsService.metricsStream,
    );
  }

  @override
  void didUpdateWidget(covariant AppleWindowControlsMetricsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metricsStream != widget.metricsStream) {
      _subscription?.cancel();
      _subscribe(
        widget.metricsStream ?? AppleWindowControlsService.metricsStream,
      );
    }
  }

  void _subscribe(Stream<AppleWindowControlsMetrics> stream) {
    _subscription = stream.listen(
      (metrics) {
        if (!mounted || metrics == _metrics) return;
        setState(() => _metrics = metrics);
      },
      onError: (_, __) {
        if (!mounted || _metrics.isZero) return;
        setState(() => _metrics = const AppleWindowControlsMetrics.zero());
      },
    );
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppleWindowControlsMetricsInherited(
      metrics: _metrics,
      child: widget.child,
    );
  }
}

class _AppleWindowControlsMetricsInherited extends InheritedWidget {
  const _AppleWindowControlsMetricsInherited({
    required this.metrics,
    required super.child,
  });

  final AppleWindowControlsMetrics metrics;

  @override
  bool updateShouldNotify(_AppleWindowControlsMetricsInherited oldWidget) {
    return oldWidget.metrics != metrics;
  }
}

/// Keeps Material toolbar content inside the native iOS corner-safe area.
class WindowControlsAwareAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const WindowControlsAwareAppBar({super.key, required this.child});

  final AppBar child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    final metrics = AppleWindowControlsMetricsScope.of(context);
    if (metrics.isZero) return child;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: metrics.leading,
        end: metrics.trailing,
      ),
      child: child,
    );
  }
}
