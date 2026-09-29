import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../apps/app_registry.dart';
import '../capabilities/academic_schedule/academic_schedule_capability.dart';
import '../apps/app_service.dart';
import '../capabilities/east8_time.dart';
import '../capabilities/live_update.dart';
import 'auth_service.dart';
import 'platform_compatibility_service.dart';

/// The only Dart-to-native boundary used by the current system live surface.
class LiveUpdatePlatform {
  static const MethodChannel _channel = MethodChannel('mychu/live_update');
  static const MethodChannel _appleChannel = MethodChannel(
    'mychu/system_live_activity',
  );

  @visibleForTesting
  static Future<Object?> Function(String method, Object? arguments)?
  debugInvoke;

  static Future<Object?> _invoke(String method, [Object? arguments]) {
    final override = debugInvoke;
    if (override != null) return override(method, arguments);
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  static Future<Object?> _invokeApple(String method, [Object? arguments]) {
    final override = debugInvoke;
    if (override != null) return override(method, arguments);
    return _appleChannel.invokeMethod<Object?>(method, arguments);
  }

  static Future<Object?> _invokeSystem(String method, [Object? arguments]) {
    return PlatformCompatibilityService.isApple
        ? _invokeApple(method, arguments)
        : _invoke(method, arguments);
  }

  static Future<void> upsert(LiveUpdateNotificationPackage package) =>
      _invokeSystem('upsert', {
        'package': jsonEncode(
          package.toJson(
            includeAccountKey: !PlatformCompatibilityService.isApple,
          ),
        ),
      }).then((_) {});

  static Future<void> cancel(String accountKey) =>
      _invokeSystem('cancel', {'accountKey': accountKey}).then((_) {});

  static Future<void> cancelDemo() => _invokeSystem('cancelDemo').then((_) {});

  static Future<void> clearAll() => _invokeSystem('clearAll').then((_) {});

  static Future<void> openChannelSettings() =>
      _invokeSystem('openChannelSettings').then((_) {});

  static Future<void> openPromotionSettings() =>
      _invokeSystem('openPromotionSettings').then((_) {});

  static Future<Map<String, Object?>> status() async {
    final raw = await _invokeSystem('getStatus');
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    return const {};
  }
}

/// Account-scoped user preferences for system live definitions.
class LiveUpdatePreferences {
  static const _legacyKeyPrefix = 'live_update.v1.enabled.';
  static const _definitionKeyPrefix = 'live_update.v2.enabled.';

  static String _legacyKey(String accountKey) => '$_legacyKeyPrefix$accountKey';

  static String _definitionKey(String accountKey, String definitionId) =>
      '$_definitionKeyPrefix$accountKey.$definitionId';

  static Future<bool> isEnabled(String accountKey, String definitionId) async {
    final prefs = await SharedPreferences.getInstance();
    final explicit = prefs.getBool(_definitionKey(accountKey, definitionId));
    if (explicit != null) return explicit;
    return prefs.getBool(_legacyKey(accountKey)) ?? true;
  }

  static Future<Set<String>> enabledDefinitionIds(
    String accountKey,
    Iterable<String> candidateIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = candidateIds.toSet();
    final legacy = prefs.getBool(_legacyKey(accountKey));
    return {
      for (final id in ids)
        if (prefs.getBool(_definitionKey(accountKey, id)) ?? legacy ?? true) id,
    };
  }

  static Future<void> setEnabled(
    String accountKey,
    String definitionId,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_definitionKey(accountKey, definitionId), enabled);
  }

  static Future<void> clearAccount(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith(_legacyKey(accountKey)) ||
                  key.startsWith('$_definitionKeyPrefix$accountKey.'),
            )
            .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith(_legacyKeyPrefix) ||
                  key.startsWith(_definitionKeyPrefix),
            )
            .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

/// Host coordinator for system live packages.
class LiveUpdateService {
  static const _promotionStartupPromptShownKey =
      'live_update.promotion_startup_prompt.v1';

  static bool get isSupported =>
      PlatformCompatibilityService.isAndroid ||
      PlatformCompatibilityService.isApple ||
      LiveUpdatePlatform.debugInvoke != null;

  static List<SystemLiveActivityDefinition> get definitions => [
    if (isSupported)
      ...academicScheduleCapability.systemLiveActivityDefinitions,
    if (isSupported)
      for (final app in AppRegistry.builtIns)
        if (AppService.isVisibleInCurrentMode(app))
          ...app.systemLiveActivityDefinitions,
  ];

  static SystemLiveActivityDefinition? definition(String id) {
    for (final item in definitions) {
      if (item.id == id) return item;
    }
    return null;
  }

  static Future<void> upsertDefinition(
    SystemLiveActivityDefinition definition, {
    required String accountKey,
    bool forceRefresh = false,
  }) async {
    if (!isSupported) return;
    final content = await definition.load(
      LiveUpdateLoadContext(
        accountKey: accountKey,
        now: east8Now(),
        forceRefresh: forceRefresh,
      ),
    );
    final package = LiveUpdateNotificationPackage.fromContent(
      accountKey: accountKey,
      definition: definition,
      content: content,
    );
    await LiveUpdatePlatform.upsert(package);
  }

  static Future<void> refreshDefinition(
    String definitionId, {
    bool forceRefresh = false,
  }) async {
    final definition = LiveUpdateService.definition(definitionId);
    if (definition == null) return;
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      await LiveUpdatePlatform.clearAll();
      return;
    }
    await upsertDefinition(
      definition,
      accountKey: account.accountKey,
      forceRefresh: forceRefresh,
    );
  }

  static Future<void> refreshIfEnabled({bool forceRefresh = false}) async {
    if (!isSupported) return;
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      await LiveUpdatePlatform.clearAll();
      return;
    }
    final enabled = await LiveUpdatePreferences.enabledDefinitionIds(
      account.accountKey,
      [for (final definition in definitions) definition.id],
    );
    if (enabled.isEmpty) {
      await LiveUpdatePlatform.cancel(account.accountKey);
      return;
    }
    for (final definition in definitions) {
      if (!enabled.contains(definition.id)) continue;
      await upsertDefinition(
        definition,
        accountKey: account.accountKey,
        forceRefresh: forceRefresh,
      );
    }
  }

  static Future<void> cancelForAccount(String accountKey) async {
    if (!isSupported) return;
    await LiveUpdatePlatform.cancel(accountKey);
  }

  static Future<void> clearAccountData() async {
    if (isSupported) await LiveUpdatePlatform.clearAll();
    await LiveUpdatePreferences.clearAll();
  }

  static Future<void> openChannelSettings() async {
    if (!isSupported) return;
    await LiveUpdatePlatform.openChannelSettings();
  }

  static Future<void> openPromotionSettings() async {
    if (!isSupported) return;
    await LiveUpdatePlatform.openPromotionSettings();
  }

  static Future<Map<String, Object?>> platformStatus() async {
    if (!isSupported) return const {};
    return LiveUpdatePlatform.status();
  }

  /// Whether the one-time startup guide should be shown on supported Android.
  ///
  /// Promotion permission is app/device scoped, so this preference is not
  /// account scoped. A user who dismisses the guide can still open it from
  /// the notification settings page later.
  static Future<bool> shouldPromptPromotionOnStartup() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promotionStartupPromptShownKey) == true) return false;

    Map<String, Object?> status;
    try {
      status = await platformStatus();
    } catch (_) {
      return false;
    }
    return status['promotedSupported'] == true &&
        status['canPostPromotedNotifications'] != true;
  }

  static Future<void> markPromotionStartupPromptShown() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promotionStartupPromptShownKey, true);
  }

  static Future<void> debugPostDemo(
    LiveUpdateContent content, {
    required String targetAppId,
  }) async {
    if (!isSupported) return;
    final definition = SystemLiveActivityDefinition(
      id: 'dev.live_update.demo',
      title: '系统实时动态 Demo',
      targetAppId: targetAppId,
      load: _demoLoader,
    );
    final package = LiveUpdateNotificationPackage.fromContent(
      accountKey: 'dev.demo',
      definition: definition,
      content: content,
      isDemo: true,
    );
    await LiveUpdatePlatform.upsert(package);
  }

  static Future<void> debugClearDemo() async {
    if (!isSupported) return;
    await LiveUpdatePlatform.cancelDemo();
  }

  static Future<LiveUpdateContent> _demoLoader(
    LiveUpdateLoadContext context,
  ) async {
    return LiveUpdateContent.inactive(now: context.now);
  }
}
