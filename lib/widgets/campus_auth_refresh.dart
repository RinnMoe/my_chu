import 'dart:async';
import 'package:flutter/material.dart';
import '../services/host_auth_state.dart';
import 'root_destination_active_scope.dart';

/// Retains page/filter state and defers authentication refresh until visible.
mixin CampusAuthRefresh<T extends StatefulWidget> on State<T> {
  late HostAuthSnapshot _authSeen;
  bool _authRefreshPending = false;
  bool _authRefreshScheduled = false;
  bool _authVisible = false;
  FutureOr<void> onCampusAuthChanged();
  bool get campusAuthPageActive => true;
  bool get campusAuthGuest =>
      HostAuthState.initialized &&
      (HostAuthState.snapshot.value.accountKey == null ||
          HostAuthState.snapshot.value.status == HostAuthStatus.storageError);

  @override
  void initState() {
    super.initState();
    _authSeen = HostAuthState.snapshot.value;
    HostAuthState.snapshot.addListener(_authChanged);
  }

  void _authChanged() {
    final next = HostAuthState.snapshot.value;
    if (next.contentRevision != _authSeen.contentRevision ||
        (_authSeen.blocksRequests ||
                _authSeen.status == HostAuthStatus.unavailable) &&
            next.status == HostAuthStatus.available) {
      _authRefreshPending = true;
    }
    _authSeen = next;
    _scheduleAuthRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authVisible =
        RootDestinationActiveScope.activeOf(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _scheduleAuthRefresh();
  }

  void _scheduleAuthRefresh() {
    if (!_authVisible ||
        !campusAuthPageActive ||
        !_authRefreshPending ||
        _authRefreshScheduled) {
      return;
    }
    _authRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRefreshScheduled = false;
      if (!mounted ||
          !_authVisible ||
          !campusAuthPageActive ||
          !_authRefreshPending) {
        return;
      }
      _authRefreshPending = false;
      unawaited(Future<void>.sync(onCampusAuthChanged));
    });
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleAuthRefresh();
  }

  @override
  void dispose() {
    HostAuthState.snapshot.removeListener(_authChanged);
    super.dispose();
  }
}
