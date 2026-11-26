import 'package:flutter/widgets.dart';

/// Tracks pushed app pages by their stable route name.
///
/// The shell keeps bottom-tab pages in an IndexedStack, while feature entries
/// push routes above it. Without this registry, opening an app that is already
/// pushed (or already present as a tab) would create a second page and, for
/// chat-demo, a second WebView.
class AppRouteTracker extends NavigatorObserver {
  AppRouteTracker();

  static final AppRouteTracker instance = AppRouteTracker();

  static const String routeNamePrefix = 'app:';

  final Map<String, Route<dynamic>> _routes = <String, Route<dynamic>>{};

  static String routeNameFor(String appId) => '$routeNamePrefix$appId';

  Route<dynamic>? routeFor(String appId) => _routes[appId];

  String? _appIdFor(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || !name.startsWith(routeNamePrefix)) return null;
    final appId = name.substring(routeNamePrefix.length);
    return appId.isEmpty ? null : appId;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final appId = _appIdFor(route);
    if (appId != null) _routes[appId] = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final appId = _appIdFor(route);
    if (appId != null && identical(_routes[appId], route)) {
      _routes.remove(appId);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    final appId = _appIdFor(route);
    if (appId != null && identical(_routes[appId], route)) {
      _routes.remove(appId);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final oldId = _appIdFor(oldRoute);
    if (oldId != null && identical(_routes[oldId], oldRoute)) {
      _routes.remove(oldId);
    }
    final newId = _appIdFor(newRoute);
    if (newId != null && newRoute != null) _routes[newId] = newRoute;
  }
}
