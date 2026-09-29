import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/development_mode_service.dart';
import '../services/viewport_preview_service.dart';

/// Constrains the complete app Navigator to a DEV-only phone-sized canvas.
///
/// The child is the existing app tree, so routes, dialogs, sessions and
/// platform views are not duplicated for preview purposes.
class ViewportPreviewHost extends StatelessWidget {
  final Widget child;

  const ViewportPreviewHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ViewportPreviewConfig?>(
      valueListenable: ViewportPreviewService.config,
      child: child,
      builder: (context, config, child) {
        if (config == null || !DevelopmentModeService.isDev) {
          return child!;
        }

        final parentMediaQuery = MediaQuery.of(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : parentMediaQuery.size.width;
            final availableHeight =
                constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : parentMediaQuery.size.height;
            final scale = math.min(
              1.0,
              math.min(
                availableWidth / config.width,
                availableHeight / config.height,
              ),
            );
            final safeScale = scale.isFinite && scale > 0 ? scale : 1.0;
            final mediaQuery = parentMediaQuery.copyWith(
              size: config.size,
              padding: config.safeArea,
              viewPadding: config.safeArea,
              viewInsets: EdgeInsets.zero,
              systemGestureInsets: EdgeInsets.zero,
            );

            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: SizedBox(
                  width: config.width * safeScale,
                  height: config.height * safeScale,
                  child: ClipRect(
                    child: Transform.scale(
                      scale: safeScale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: config.width,
                        height: config.height,
                        child: MediaQuery(data: mediaQuery, child: child!),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
