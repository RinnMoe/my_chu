import 'package:flutter/foundation.dart';

import '../../apps/app.dart';
import '../../apps/app_registry.dart';
import '../../services/logging/logger.dart';
import '../../services/privacy_agreement_service.dart';
import '../../services/remote_feature_policy/feature_access_guard.dart';
import 'account_provider.dart';
import 'campus_account_provider.dart';
import 'channel_account_provider.dart';

class _FeatureAccountEntry {
  const _FeatureAccountEntry({required this.app, required this.provider});

  final AppDefinition app;
  final AccountProvider provider;
}

/// Central registry of host and built-in feature [AccountProvider] instances.
class AccountRegistry {
  AccountRegistry({
    required List<AccountProvider> hostProviders,
    required List<AppDefinition> apps,
    bool Function(AppDefinition)? isAppVisible,
  }) : _hostProviders = List<AccountProvider>.unmodifiable(hostProviders),
       _featureEntries = List<_FeatureAccountEntry>.unmodifiable([
         for (final app in apps)
           if (app.account != null)
             _FeatureAccountEntry(app: app, provider: app.account!),
       ]),
       _isAppVisible = isAppVisible ?? FeatureEntryVisibility.isVisible {
    _validateUniqueIds();
  }

  final List<AccountProvider> _hostProviders;
  final List<_FeatureAccountEntry> _featureEntries;
  final bool Function(AppDefinition) _isAppVisible;

  /// Host-owned account providers in fixed display order.
  static final List<AccountProvider> hostProviders =
      List<AccountProvider>.unmodifiable(<AccountProvider>[
        const CampusAccountProvider(),
        ChannelAccountProvider(),
      ]);

  static final AccountRegistry _defaultInstance = AccountRegistry(
    hostProviders: hostProviders,
    apps: AppRegistry.builtIns,
  );

  @visibleForTesting
  static AccountRegistry? debugOverride;

  static AccountRegistry get _active => debugOverride ?? _defaultInstance;

  /// Visible providers in registry order: host providers first, then visible
  /// built-in feature providers in [AppRegistry.builtIns] order.
  static List<AccountProvider> get providers => _active.visibleProviders;

  /// Concurrently restores every visible provider after verifying privacy
  /// agreement acceptance. Individual failures are logged and isolated.
  static Future<void> restoreAll() => _active.restoreVisible();

  List<AccountProvider> get visibleProviders =>
      List<AccountProvider>.unmodifiable([
        for (final provider in _hostProviders)
          if (provider.visible) provider,
        for (final entry in _featureEntries)
          if (_isAppVisible(entry.app) && entry.provider.visible)
            entry.provider,
      ]);

  Future<void> restoreVisible({
    Future<bool> Function()? isPrivacyAccepted,
  }) async {
    final accepted =
        await (isPrivacyAccepted ?? PrivacyAgreementService.isAccepted)();
    if (!accepted) return;
    final targets = visibleProviders;
    await Future.wait(
      targets.map((provider) async {
        try {
          await provider.restore();
        } catch (error, stackTrace) {
          AppLogger.error(
            error,
            stackTrace: stackTrace,
            context: '恢复账号状态失败 (${provider.id})',
          );
        }
      }),
    );
  }

  void _validateUniqueIds() {
    final seen = <String>{};
    for (final provider in _hostProviders) {
      if (provider.id.isEmpty || !seen.add(provider.id)) {
        throw StateError(
          'Duplicate or empty account provider id: ${provider.id}',
        );
      }
    }
    for (final entry in _featureEntries) {
      if (entry.provider.id.isEmpty || !seen.add(entry.provider.id)) {
        throw StateError(
          'Duplicate or empty account provider id: ${entry.provider.id}',
        );
      }
    }
  }
}
