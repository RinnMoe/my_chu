import 'package:flutter/material.dart';

import '../capabilities/live_update.dart';
import '../services/development_mode_service.dart';

export '../services/development_mode_service.dart' show DevelopmentFlag;

/// User-facing catalog categories. Values are host-defined;
/// Labels belong to the host so applications use consistent names.
enum AppCategory { learning, academic, campus, life, development, other }

extension AppCategoryLabel on AppCategory {
  String get label {
    switch (this) {
      case AppCategory.learning:
        return '学习';
      case AppCategory.academic:
        return '教务';
      case AppCategory.campus:
        return '校园';
      case AppCategory.life:
        return '生活';
      case AppCategory.development:
        return 'DEV';
      case AppCategory.other:
        return '其他';
    }
  }
}

bool isCoreAppId(String id) => id.trim().toLowerCase().startsWith('core');

class AppMetadata {
  final String id;
  final String name;
  final String description;
  final int iconCodePoint;
  final AppCategory category;
  final bool removable;
  final bool defaultPinned;
  final bool showInNavigation;
  final String? navigationLabel;
  final DevelopmentFlag developmentFlag;

  const AppMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.iconCodePoint,
    this.category = AppCategory.other,
    this.removable = true,
    this.defaultPinned = false,
    this.showInNavigation = false,
    this.navigationLabel,
    this.developmentFlag = DevelopmentFlag.dev,
  });

  IconData get icon {
    if (iconCodePoint == Icons.dashboard_customize_outlined.codePoint) {
      return Icons.dashboard_customize_outlined;
    }
    if (iconCodePoint == Icons.storefront_outlined.codePoint) {
      return Icons.storefront_outlined;
    }
    if (iconCodePoint == Icons.bug_report_outlined.codePoint) {
      return Icons.bug_report_outlined;
    }
    if (iconCodePoint == Icons.bluetooth_outlined.codePoint) {
      return Icons.bluetooth_outlined;
    }
    if (iconCodePoint == Icons.school_outlined.codePoint) {
      return Icons.school_outlined;
    }
    if (iconCodePoint == Icons.dashboard_outlined.codePoint) {
      return Icons.dashboard_outlined;
    }
    if (iconCodePoint == Icons.space_dashboard_outlined.codePoint) {
      return Icons.space_dashboard_outlined;
    }
    if (iconCodePoint == Icons.map_outlined.codePoint) {
      return Icons.map_outlined;
    }
    if (iconCodePoint == Icons.campaign_outlined.codePoint) {
      return Icons.campaign_outlined;
    }
    if (iconCodePoint == Icons.account_balance_wallet_outlined.codePoint) {
      return Icons.account_balance_wallet_outlined;
    }
    if (iconCodePoint == Icons.fitness_center_outlined.codePoint) {
      return Icons.fitness_center_outlined;
    }
    if (iconCodePoint == Icons.local_library_outlined.codePoint) {
      return Icons.local_library_outlined;
    }
    if (iconCodePoint == Icons.payment_outlined.codePoint) {
      return Icons.payment_outlined;
    }
    if (iconCodePoint == Icons.verified_outlined.codePoint) {
      return Icons.verified_outlined;
    }
    if (iconCodePoint == Icons.event_available_outlined.codePoint) {
      return Icons.event_available_outlined;
    }
    if (iconCodePoint == Icons.grade_outlined.codePoint) {
      return Icons.grade_outlined;
    }
    if (iconCodePoint == Icons.volunteer_activism_outlined.codePoint) {
      return Icons.volunteer_activism_outlined;
    }
    if (iconCodePoint == Icons.wifi_outlined.codePoint) {
      return Icons.wifi_outlined;
    }
    if (iconCodePoint == Icons.calendar_view_week_outlined.codePoint) {
      return Icons.calendar_view_week_outlined;
    }
    if (iconCodePoint == Icons.calendar_month_outlined.codePoint) {
      return Icons.calendar_month_outlined;
    }
    if (iconCodePoint == Icons.date_range_outlined.codePoint) {
      return Icons.date_range_outlined;
    }
    if (iconCodePoint == Icons.meeting_room_outlined.codePoint) {
      return Icons.meeting_room_outlined;
    }
    if (iconCodePoint == Icons.directions_bus_outlined.codePoint) {
      return Icons.directions_bus_outlined;
    }
    if (iconCodePoint == Icons.fact_check_outlined.codePoint) {
      return Icons.fact_check_outlined;
    }
    if (iconCodePoint == Icons.folder_open_outlined.codePoint) {
      return Icons.folder_open_outlined;
    }
    if (iconCodePoint == Icons.play_circle_outline.codePoint) {
      return Icons.play_circle_outline;
    }
    if (iconCodePoint == Icons.video_library_outlined.codePoint) {
      return Icons.video_library_outlined;
    }
    if (iconCodePoint == Icons.qr_code_2_outlined.codePoint) {
      return Icons.qr_code_2_outlined;
    }
    if (iconCodePoint == Icons.power_outlined.codePoint) {
      return Icons.power_outlined;
    }
    if (iconCodePoint == Icons.camera_alt_outlined.codePoint) {
      return Icons.camera_alt_outlined;
    }
    return Icons.extension_outlined;
  }

  bool get core => isCoreAppId(id);

  bool get requiresDev => developmentFlag == DevelopmentFlag.dev;

  /// Effective catalog category derived by the host.
  ///
  /// The DEV section is controlled only by the host-managed development flag.
  AppCategory get catalogCategory {
    if (requiresDev) return AppCategory.development;
    if (category == AppCategory.development) return AppCategory.other;
    return category;
  }
}

typedef AppOpenAction = Future<bool> Function(BuildContext context);

class AppDefinition {
  final AppMetadata metadata;
  final WidgetBuilder? pageBuilder;
  final AppOpenAction? openAction;
  final List<SystemLiveActivityDefinition> systemLiveActivityDefinitions;

  WidgetBuilder? get builder => pageBuilder;

  const AppDefinition({
    required this.metadata,
    required WidgetBuilder builder,
    this.systemLiveActivityDefinitions = const [],
  }) : pageBuilder = builder,
       openAction = null;

  AppDefinition.action({
    required this.metadata,
    required AppOpenAction action,
    this.systemLiveActivityDefinitions = const [],
  }) : pageBuilder = null,
       openAction = action {
    if (metadata.showInNavigation) {
      throw ArgumentError.value(
        metadata.showInNavigation,
        'metadata.showInNavigation',
      );
    }
  }
}
