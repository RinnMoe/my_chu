import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/academic_schedule/academic_schedule_capability.dart';
import '../services/auth_service.dart';
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
  @visibleForTesting Future<String> Function()? accountKeyResolver,
}) async {
  if (!AppService.isVisibleInCurrentMode(plugin)) return;
  if (!context.mounted) return;
  final accountKey = await (accountKeyResolver ?? _resolveCurrentAccountKey)();
  if (!context.mounted) return;

  final action = plugin.openAction;
  if (action != null) {
    var opened = false;
    try {
      opened = await action(context);
    } on Object {
      return;
    }
    if (!opened) return;
    _recordAppUsage(plugin, accountKey);
    return;
  }

  final builder = pageBuilder ?? plugin.pageBuilder;
  if (builder == null) return;
  unawaited(Navigator.push(context, MaterialPageRoute(builder: builder)));
  _recordAppUsage(plugin, accountKey);
}

Future<String> _resolveCurrentAccountKey() async =>
    (await AuthService.getCurrentAccount())?.accountKey ?? 'anonymous';

void _recordAppUsage(AppDefinition plugin, String accountKey) {
  unawaited(
    AppService.recordUsage(
      plugin.metadata.id,
      accountKey: accountKey,
    ).then<void>((_) {}, onError: (Object _) {}),
  );
}
