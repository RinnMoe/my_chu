import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

@immutable
class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;

  /// Optional detail. Omit when the title alone explains the highlighted
  /// control; the coach mark then renders the title only.
  final String? message;
  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    this.message,
  });
}

/// Shared visual configuration for the package-backed coach marks.
abstract final class CoachMarkPresenter {
  static const _focusPadding = 8.0;

  static bool show(
    BuildContext context, {
    required List<CoachMarkStep> steps,

    required VoidCallback onFinished,
  }) {
    if (steps.isEmpty ||
        steps.any((step) => step.targetKey.currentContext == null)) {
      return false;
    }

    final overlay = Overlay.of(context);
    TutorialCoachMark(
      targets: [
        for (var index = 0; index < steps.length; index++)
          TargetFocus(
            identify: 'guide-step-$index',
            keyTarget: steps[index].targetKey,
            shape: ShapeLightFocus.RRect,
            radius: 16,
            contents: [
              TargetContent(
                align: ContentAlign.custom,
                customPosition: CustomTargetContentPosition(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  left: 0,
                ),
                padding: EdgeInsets.zero,
                builder: (context, _) {
                  final step = steps[index];
                  final box = step.targetKey.currentContext?.findRenderObject();
                  if (box is! RenderBox || !box.hasSize) {
                    return const SizedBox.shrink();
                  }
                  final origin = box.localToGlobal(
                    Offset.zero,
                    ancestor: overlay.context.findRenderObject(),
                  );
                  return CustomSingleChildLayout(
                    delegate: _CoachMarkLayout(
                      target: (origin & box.size).inflate(_focusPadding),
                      safeInsets: MediaQuery.paddingOf(context),
                    ),
                    child: _CoachMarkContent(
                      title: step.title,
                      message: step.message,
                    ),
                  );
                },
              ),
            ],
          ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.72,
      paddingFocus: _focusPadding,
      pulseEnable: false,
      disableBackButton: true,
      textSkip: '跳过',
      onFinish: onFinished,
      onSkip: () {
        onFinished();
        return true;
      },
    ).showWithOverlayState(overlay: overlay);
    return true;
  }
}

class _CoachMarkLayout extends SingleChildLayoutDelegate {
  final Rect target;
  final EdgeInsets safeInsets;

  const _CoachMarkLayout({required this.target, required this.safeInsets});

  Rect _usableBounds(Size size) {
    final left = safeInsets.left + 20;
    final top = safeInsets.top + 8;
    return Rect.fromLTRB(
      left,
      top,
      math.max(left, size.width - safeInsets.right - 20),
      // Reserve the bottom-right skip action.
      math.max(top, size.height - safeInsets.bottom - 48),
    );
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _usableBounds(constraints.biggest);
    return BoxConstraints.tightFor(
      width: bounds.width,
    ).copyWith(maxHeight: bounds.height);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _usableBounds(size);
    final below = target.bottom + 8;
    final above = target.top - 8 - childSize.height;
    final preferredTop =
        below + childSize.height <= bounds.bottom ||
                (above < bounds.top && target.center.dy <= bounds.center.dy)
            ? below
            : above;
    return Offset(
      bounds.left,
      preferredTop.clamp(bounds.top, bounds.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_CoachMarkLayout oldDelegate) =>
      target != oldDelegate.target || safeInsets != oldDelegate.safeInsets;
}

class _CoachMarkContent extends StatelessWidget {
  final String title;
  final String? message;

  const _CoachMarkContent({required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final messageStyle = Theme.of(context).textTheme.bodyMedium;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: titleStyle),
            if (message case final message?) ...[
              const SizedBox(height: 8),
              Text(message, style: messageStyle),
            ],
          ],
        ),
      ),
    );
  }
}
