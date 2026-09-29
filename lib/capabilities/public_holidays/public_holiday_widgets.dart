import 'package:flutter/material.dart';

import 'public_holiday_models.dart';

/// Returns the semantic color for a public-holiday label.
///
/// The text label must remain visible alongside this color so the meaning is
/// not conveyed by color alone.
Color publicHolidayColor(BuildContext context, {required bool isOffDay}) {
  if (isOffDay) {
    return Theme.of(context).colorScheme.error;
  }

  return Theme.of(context).brightness == Brightness.dark
      ? Colors.orange.shade300
      : Colors.orange.shade700;
}

/// A compact, accessible label for one public-holiday record.
class PublicHolidayLabel extends StatelessWidget {
  final PublicHolidayDay day;
  final bool showName;
  final TextStyle? style;

  const PublicHolidayLabel({
    super.key,
    required this.day,
    this.showName = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final color = publicHolidayColor(context, isOffDay: day.isOffDay);
    final text = showName ? '${day.label} · ${day.name}' : day.label;
    return Semantics(
      container: true,
      label: '${day.label}${day.name}',
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            style?.copyWith(color: color) ??
            TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
      ),
    );
  }
}
