import 'package:flutter/foundation.dart';

enum HostAuthStatus {
  guest,
  checking,
  available,
  unavailable,
  loginRequired,
  storageError,
}

class HostAuthSnapshot {
  const HostAuthSnapshot(
    this.status, {
    this.accountKey,
    this.contentRevision = 0,
  });
  final HostAuthStatus status;
  final String? accountKey;

  /// Changes only after committed login/logout, rather than every cookie refresh.
  final int contentRevision;
  bool get blocksRequests =>
      status == HostAuthStatus.guest ||
      status == HostAuthStatus.storageError ||
      status == HostAuthStatus.loginRequired ||
      status == HostAuthStatus.unavailable;
}

class CampusAuthenticationRequired implements Exception {
  const CampusAuthenticationRequired(this.status);
  final HostAuthStatus status;
  @override
  String toString() => 'CampusAuthenticationRequired(${status.name})';
}

/// UI readiness is advisory; CampusSession still owns request authentication.
class HostAuthState {
  static final snapshot = ValueNotifier(
    const HostAuthSnapshot(HostAuthStatus.guest),
  );
  static bool initialized = false;
  static void update(
    HostAuthStatus status, {
    String? accountKey,
    bool contentChanged = false,
  }) {
    initialized = true;
    final old = snapshot.value;
    snapshot.value = HostAuthSnapshot(
      status,
      accountKey: accountKey,
      contentRevision: old.contentRevision + (contentChanged ? 1 : 0),
    );
  }

  static void requireRequestsAllowed() {
    if (initialized && snapshot.value.blocksRequests) {
      throw CampusAuthenticationRequired(snapshot.value.status);
    }
  }

  @visibleForTesting
  static void reset() {
    initialized = false;
    snapshot.value = const HostAuthSnapshot(HostAuthStatus.guest);
  }
}
