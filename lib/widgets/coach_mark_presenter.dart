import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

@immutable
class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String message;
  final ContentAlign contentAlign;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.message,
    this.contentAlign = ContentAlign.bottom,
  });
}

/// Shared visual configuration for the package-backed coach marks.
abstract final class CoachMarkPresenter {
  static bool show(
    BuildContext context, {
    required List<CoachMarkStep> steps,

    required VoidCallback onFinished,
  }) {
    if (steps.isEmpty ||
        steps.any((step) => step.targetKey.currentContext == null)) {
      return false;
    }

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
                align: steps[index].contentAlign,
                padding: EdgeInsets.zero,
                child: _CoachMarkContent(
                  title: steps[index].title,
                  message: steps[index].message,
                ),
              ),
            ],
          ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.72,
      paddingFocus: 8,
      pulseEnable: false,
      disableBackButton: true,
      textSkip: '跳过',
      onFinish: onFinished,
      onSkip: () {
        onFinished();
        return true;
      },
    ).show(context: context);
    return true;
  }
}

class _CoachMarkContent extends StatelessWidget {
  final String title;
  final String message;

  const _CoachMarkContent({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final messageStyle = Theme.of(context).textTheme.bodyMedium;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 40,
      ),
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 8),
          Text(message, style: messageStyle),
        ],
      ),
    );
  }
}
