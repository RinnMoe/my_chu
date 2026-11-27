import 'package:flutter/material.dart';

import '../../capabilities/accounts/account_provider.dart';
import '../../services/mail/mail_session.dart';
import 'mail_settings_page.dart';
import 'mail_setup_page.dart';

/// Feature account provider for campus mail registered via [AppDefinition.account].
class MailAccountProvider implements AccountProvider {
  MailAccountProvider({MailSession? session}) : _sessionOverride = session;

  static const String providerId = 'account.mail';
  static const String logoutConfirmationMessage = '退出后会清除本机保存的邮箱密码、配置和邮件缓存。';

  final MailSession? _sessionOverride;

  MailSession get _session => _sessionOverride ?? MailSession.instance;

  late final Listenable _changes = Listenable.merge([
    _session.revision,
    _session.state,
  ]);

  @override
  String get id => providerId;

  @override
  String get name => '校园邮箱';

  @override
  IconData get icon => Icons.mail_outline;

  @override
  bool get visible => true;

  @override
  String get logoutMessage => logoutConfirmationMessage;

  @override
  Listenable get changes => _changes;

  @override
  Future<AccountSummary> read() async {
    await _session.initialize();
    final state = _session.state.value;
    final config = state.config;
    if (state.isConfigured && config != null) {
      return AccountSummary(
        AccountStatus.available,
        displayName: config.email,
        hasIdentity: true,
      );
    }
    return const AccountSummary(AccountStatus.signedOut);
  }

  @override
  Future<void> restore() => _session.initialize();

  @override
  Future<void> open(BuildContext context) async {
    await _session.initialize();
    if (!context.mounted) return;
    final state = _session.state.value;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) =>
                state.isConfigured
                    ? MailSettingsPage(session: _session)
                    : MailSetupPage(
                      initialConfig: state.config,
                      session: _session,
                    ),
      ),
    );
  }

  @override
  Future<void> logout() => _session.signOut();
}
