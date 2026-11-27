import 'package:flutter/material.dart';

import '../../services/auth_lifecycle_service.dart';
import '../../services/auth_service.dart';
import '../../services/host_auth_state.dart';
import '../host_login.dart';
import 'account_provider.dart';

/// Host-owned campus identity provider registered in [AccountRegistry].
class CampusAccountProvider implements AccountProvider {
  const CampusAccountProvider();

  static const String providerId = 'account.campus';
  static const String logoutConfirmationMessage =
      '退出登录会清除本机保存的登录信息、课程提醒和桌面课表小组件。';

  @override
  String get id => providerId;

  @override
  String get name => '校园账号';

  @override
  IconData get icon => Icons.school_outlined;

  @override
  bool get visible => true;

  @override
  String get logoutMessage => logoutConfirmationMessage;

  @override
  Listenable get changes => HostAuthState.snapshot;

  @override
  Future<AccountSummary> read() async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      return const AccountSummary(AccountStatus.signedOut);
    }
    return AccountSummary(
      HostAuthState.snapshot.value.blocksRequests
          ? AccountStatus.unavailable
          : AccountStatus.available,
      displayName: account.name,
      hasIdentity: true,
    );
  }

  @override
  Future<void> restore() async {
    // Host startup and resume already own campus restore via HostAuthCoordinator.
  }

  @override
  Future<void> open(BuildContext context) async {
    final account = await AuthService.getCurrentAccount();
    if (account != null || !context.mounted) return;
    await HostLogin.open(context);
  }

  @override
  Future<void> logout() => AuthLifecycleService.signOut();
}
