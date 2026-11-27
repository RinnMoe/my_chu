import 'package:flutter/material.dart';

import '../../pages/channel_account_page.dart';
import '../channel_account_capability.dart';
import 'account_provider.dart';

/// Host-owned channel resources account provider registered in [AccountRegistry].
class ChannelAccountProvider implements AccountProvider {
  ChannelAccountProvider({ChannelAccountCapability? capability})
    : _capability = capability;

  static const String providerId = 'account.channel';

  final ChannelAccountCapability? _capability;

  ChannelAccountCapability get _account =>
      _capability ?? ChannelAccountCapability.current;

  @override
  String get id => providerId;

  @override
  String get name => '频道账号';

  @override
  IconData get icon => Icons.forum_outlined;

  @override
  bool get visible => true;

  @override
  String get logoutMessage =>
      ChannelAccountCapability.logoutConfirmationMessage;

  @override
  Listenable get changes => _account.stateListenable;

  @override
  Future<AccountSummary> read() async {
    final state = _account.state;
    return AccountSummary(
      state.isAuthenticated
          ? AccountStatus.available
          : state.status == ChannelAccountStatus.unavailable
          ? AccountStatus.unavailable
          : AccountStatus.signedOut,
      displayName: _account.user?.nickname,
      hasIdentity: _account.hasIdentity,
    );
  }

  @override
  Future<void> restore() async {
    await _account.restore();
  }

  @override
  Future<void> open(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChannelAccountPage(capability: _account),
      ),
    );
  }

  @override
  Future<void> logout() => _account.logout();
}
