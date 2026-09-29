import 'dart:async';

import 'package:flutter/material.dart';

/// Shared system-back handling for WebView pages.
///
/// When the WebView has internal history, system back is consumed so the page
/// can navigate inside the WebView instead of popping the enclosing Flutter
/// route. When there is no history, the route pops normally. Use
/// [WebViewCloseButton] for the AppBar leading button when it should always
/// close the WebView route instead of navigating the WebView history.
class WebViewBackHandler extends StatefulWidget {
  final bool canGoBack;
  final Future<void> Function() onBack;
  final Widget child;

  const WebViewBackHandler({
    super.key,
    required this.canGoBack,
    required this.onBack,
    required this.child,
  });

  @override
  State<WebViewBackHandler> createState() => _WebViewBackHandlerState();
}

class _WebViewBackHandlerState extends State<WebViewBackHandler> {
  bool _backInFlight = false;
  bool _closeInFlight = false;

  void _closeRoute() {
    if (!mounted || _closeInFlight) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;

    _closeInFlight = true;
    navigator.pop();
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop || _backInFlight) return;
    _backInFlight = true;
    unawaited(
      widget.onBack().whenComplete(() {
        if (mounted) _backInFlight = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !widget.canGoBack,
      onPopInvokedWithResult: _onPopInvoked,
      child: _WebViewBackHandlerScope(
        closeRoute: _closeRoute,
        child: widget.child,
      ),
    );
  }
}

class _WebViewBackHandlerScope extends InheritedWidget {
  final VoidCallback closeRoute;

  const _WebViewBackHandlerScope({
    required this.closeRoute,
    required super.child,
  });

  @override
  bool updateShouldNotify(_WebViewBackHandlerScope oldWidget) =>
      closeRoute != oldWidget.closeRoute;
}

/// AppBar leading button that always closes the enclosing WebView route.
class WebViewCloseButton extends StatelessWidget {
  const WebViewCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_WebViewBackHandlerScope>();
    if (scope == null) return const SizedBox.shrink();
    return BackButton(onPressed: scope.closeRoute);
  }
}
