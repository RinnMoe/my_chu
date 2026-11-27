import 'package:flutter/widgets.dart';

/// Availability status for a registered host or feature account provider.
enum AccountStatus { signedOut, available, unavailable }

/// Non-secret summary projected by an [AccountProvider] for management UI.
class AccountSummary {
  const AccountSummary(this.status, {this.displayName, bool? hasIdentity})
    : _hasIdentity = hasIdentity;

  final AccountStatus status;
  final String? displayName;
  final bool? _hasIdentity;

  /// Whether the provider currently holds an identity that can be signed out,
  /// even if its session is temporarily unavailable.
  bool get hasIdentity => _hasIdentity ?? status == AccountStatus.available;
}

/// Contract implemented by host and built-in feature account types.
abstract interface class AccountProvider {
  /// Stable identifier across releases, e.g. `account.campus`.
  String get id;

  String get name;
  IconData get icon;
  bool get visible;
  String get logoutMessage;
  Listenable get changes;

  Future<AccountSummary> read();
  Future<void> restore();
  Future<void> open(BuildContext context);
  Future<void> logout();
}
