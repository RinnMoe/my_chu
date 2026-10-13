import '../capabilities/host_login.dart';
import '../services/auth_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/academic_schedule/academic_schedule_capability.dart';
import '../widgets/campus_auth_boundary.dart';
import '../services/root_navigation_service.dart';
import 'app.dart';
import 'app_registry.dart';
import 'app_service.dart';

/// Opens either a host-owned capability or a registered app by its stable ID.
Future<bool> openTargetId(
  BuildContext context,
  String targetId, {
  WidgetBuilder? appPageBuilder,
}) async {
  if (targetId == AcademicScheduleCapability.targetId) {
    RootNavigationService.selectTab(targetId);
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    return true;
  }
  final app = AppRegistry.publishedById(targetId);
  if (app == null) return false;
  await openAppDefinition(context, app, pageBuilder: appPageBuilder);
  return true;
}

/// Opens an app after recording a successful launch.
Future<void> openAppDefinition(
  BuildContext context,
  AppDefinition plugin, {
  WidgetBuilder? pageBuilder,
}) async {
  if (!AppService.isVisibleInCurrentMode(plugin)) return;
  if (!context.mounted) return;

  final action = plugin.openAction;
  if (action != null) {
    if (plugin.requiresCampusAccount &&
        await AuthService.getCurrentAccount() == null) {
      if (!context.mounted || !await HostLogin.open(context)) return;
      if (!context.mounted) return;
    }
    if (!context.mounted) return;
    var opened = false;
    try {
      opened = await action(context);
    } on Object {
      return;
    }
    if (!opened) return;
    _recordAppUsage(plugin);
    return;
  }

  final builder = pageBuilder ?? plugin.pageBuilder;
  if (builder == null) return;
  unawaited(
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                plugin.requiresCampusAccount
                    ? CampusAuthBoundary(
                      title: plugin.metadata.name,
                      retainGuestShell: plugin.retainsGuestShell,
                      builder: builder,
                    )
                    : builder(context),
      ),
    ),
  );
  _recordAppUsage(plugin);
}

void _recordAppUsage(AppDefinition plugin) {
  unawaited(
    AppService.recordUsage(
      plugin.metadata.id,
    ).then<void>((_) {}, onError: (Object _) {}),
  );
}
