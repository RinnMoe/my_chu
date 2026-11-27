import 'package:flutter/material.dart';

import '../../capabilities/accounts/account_provider.dart';
import '../../capabilities/chat_demo/chat_demo_brand.dart';
import '../../pages/deepseek_api_settings_page.dart';
import '../../services/deepseek_api_settings_service.dart';

/// 注册到统一账号管理页的 DeepSeek API 账号项。
class DeepSeekAccountProvider implements AccountProvider {
  DeepSeekAccountProvider({DeepSeekApiSettingsService? service})
    : _serviceOverride = service;

  static const String providerId = 'account.deepseek';
  static const String logoutConfirmationMessage =
      '退出后会删除本机保存的 DeepSeek API Key，需重新填写才能继续使用「$askYuiName」，对话记录不受影响。';

  final DeepSeekApiSettingsService? _serviceOverride;

  DeepSeekApiSettingsService get _service =>
      _serviceOverride ?? DeepSeekApiSettingsService.instance;

  @override
  String get id => providerId;

  @override
  String get name => 'DeepSeek API';

  @override
  IconData get icon => Icons.auto_awesome_outlined;

  @override
  bool get visible => true;

  @override
  String get logoutMessage => logoutConfirmationMessage;

  @override
  Listenable get changes => _service.revision;

  @override
  Future<AccountSummary> read() async {
    final key = await _service.read();
    if (key != null) {
      return AccountSummary(
        AccountStatus.available,
        displayName: DeepSeekApiSettingsService.mask(key),
        hasIdentity: true,
      );
    }
    return const AccountSummary(AccountStatus.signedOut);
  }

  @override
  Future<void> restore() => Future<void>.value();

  @override
  Future<void> open(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeepSeekApiSettingsPage(service: _service),
      ),
    );
  }

  @override
  Future<void> logout() => _service.clear();
}
