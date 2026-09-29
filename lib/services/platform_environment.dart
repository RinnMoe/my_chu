import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Device form factor reported by the host display.
///
/// This is intentionally separate from [WindowClass]. A tablet in a narrow
/// split window is still a tablet, while a phone rotated to landscape remains
/// a phone and keeps the mobile navigation model.
enum DeviceFamily { phone, tablet }

/// Responsive window class shared by the host and feature presentation.
enum WindowClass { compact, medium, expanded }

extension WindowClassPresentation on WindowClass {
  bool get isAtLeastMedium => this != WindowClass.compact;

  bool get isExpanded => this == WindowClass.expanded;
}

/// A small, injectable description of the current presentation environment.
@immutable
class PlatformEnvironment {
  static const mediumWidthBreakpoint = 600.0;
  static const expandedWidthBreakpoint = 840.0;

  final DeviceFamily deviceFamily;
  final WindowClass windowClass;

  const PlatformEnvironment({
    required this.deviceFamily,
    required this.windowClass,
  });

  factory PlatformEnvironment.fromContext(
    BuildContext context, {
    DeviceFamily? deviceFamilyOverride,
    WindowClass? windowClassOverride,
  }) {
    return PlatformEnvironment(
      deviceFamily: deviceFamilyOverride ?? deviceFamilyForContext(context),
      windowClass:
          windowClassOverride ??
          windowClassForWidth(MediaQuery.sizeOf(context).width),
    );
  }

  /// Determines the physical device family from the full display rather than
  /// the current app window. This keeps an iPad/Android Pad classified as a
  /// tablet while it is in a narrow split window.
  static DeviceFamily deviceFamilyForContext(BuildContext context) {
    final view = View.of(context);
    final display = view.display;
    final devicePixelRatio = display.devicePixelRatio;
    final logicalDisplaySize = Size(
      display.size.width / devicePixelRatio,
      display.size.height / devicePixelRatio,
    );
    return deviceFamilyForShortestSide(
      math.min(logicalDisplaySize.width, logicalDisplaySize.height),
    );
  }

  static DeviceFamily deviceFamilyForShortestSide(double shortestSide) {
    return shortestSide >= mediumWidthBreakpoint
        ? DeviceFamily.tablet
        : DeviceFamily.phone;
  }

  static WindowClass windowClassForWidth(double width) {
    if (width >= expandedWidthBreakpoint) return WindowClass.expanded;
    if (width >= mediumWidthBreakpoint) return WindowClass.medium;
    return WindowClass.compact;
  }

  bool get usesTabletNavigation =>
      deviceFamily == DeviceFamily.tablet && windowClass.isAtLeastMedium;
}
