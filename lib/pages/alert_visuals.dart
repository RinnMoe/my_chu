import 'package:flutter/material.dart';

import '../capabilities/alert_models.dart';
import '../theme/app_palette.dart';

/// 提醒严重程度对应的强调色。
Color alertSeverityColor(BuildContext context, AlertSeverity severity) {
  final colors = Theme.of(context).colorScheme;
  final semantic = AppSemanticColors.of(context);
  return switch (severity) {
    AlertSeverity.info => colors.primary,
    AlertSeverity.warning => semantic.warning,
    AlertSeverity.critical => colors.error,
  };
}

/// 提醒严重程度对应的图标。
IconData alertSeverityIcon(AlertSeverity severity) {
  return switch (severity) {
    AlertSeverity.info => Icons.info_outline,
    AlertSeverity.warning => Icons.warning_amber_rounded,
    AlertSeverity.critical => Icons.error_outline,
  };
}
