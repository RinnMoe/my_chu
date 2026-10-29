import '../capabilities/host_login.dart';
import '../services/auth_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/academic_schedule/academic_schedule_capability.dart';
import '../services/remote_feature_policy/feature_access_guard.dart';
import '../widgets/campus_auth_boundary.dart';
import '../widgets/feature_access_notice.dart';
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
///
/// Registered app launches converge here. Custom navigation tabs use
/// FeatureAccessHost directly; host capabilities and background work remain
/// outside this entry gate.
Future<void> openAppDefinition(
  BuildContext context,
  AppDefinition plugin, {
  WidgetBuilder? pageBuilder,
}) async {
  if (!AppService.isVisibleInCurrentMode(plugin)) return;
  if (!context.mounted) return;

  final decision = await FeatureAccessGuard.instance.decideForEntry(plugin);
  if (!context.mounted) return;
  if (!decision.canLaunch) {
    await showFeatureUnavailableNotice(context, decision);
    return;
  }

  final action = plugin.openAction;
  if (action != null) {
    if (plugin.requiresCampusAccount &&
        await AuthService.getCurrentAccount() == null) {
      if (!context.mounted || !await HostLogin.open(context)) return;
      if (!context.mounted) return;
    }
    if (!context.mounted) return;
    // Login can outlive the initial decision while a foreground refresh applies.
    final executionDecision = FeatureAccessGuard.instance.decideForDefinition(
      plugin,
    );
    if (!executionDecision.canLaunch) {
      await showFeatureUnavailableNotice(context, executionDecision);
      return;
    }
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
            (context) => FeatureAccessHost(
              featureId: plugin.metadata.id,
              child:
                  plugin.requiresCampusAccount
                      ? CampusAuthBoundary(
                        title: plugin.metadata.name,
                        retainGuestShell: plugin.retainsGuestShell,
                        builder: builder,
                      )
                      : builder(context),
            ),
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
