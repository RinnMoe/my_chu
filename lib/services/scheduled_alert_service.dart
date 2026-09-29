import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../capabilities/scheduled_alert.dart';
import 'platform_compatibility_service.dart';

class ScheduledAlertService {
  static const _channel = MethodChannel('mychu/scheduled_alerts');

  @visibleForTesting
  static Future<Object?> Function(String method, Object? arguments)?
  debugInvoke;

  static bool get isSupported =>
      debugInvoke != null ||
      PlatformCompatibilityService.isAndroid ||
      PlatformCompatibilityService.isApple;

  static Future<Object?> _invoke(String method, [Object? arguments]) async {
    final override = debugInvoke;
    if (override == null &&
        !PlatformCompatibilityService.isAndroid &&
        !PlatformCompatibilityService.isApple) {
      return null;
    }
    try {
      return await (override?.call(method, arguments) ??
          _channel.invokeMethod<Object?>(method, arguments));
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> replace(
    String accountKey,
    String providerId,
    List<ScheduledAlertDraft> alerts,
  ) async {
    if (debugInvoke == null && PlatformCompatibilityService.isHarmony) {
      throw UnsupportedError(
        'Scheduled alerts are not supported on HarmonyOS.',
      );
    }
    await _invoke('replace', {
      'accountKey': accountKey,
      'providerId': providerId,
      'alerts': jsonEncode([
        for (final alert in alerts)
          alert.toJson(accountKey: accountKey, providerId: providerId),
      ]),
    });
  }

  static Future<void> clearProvider(String accountKey, String providerId) =>
      _invoke('clearProvider', {
        'accountKey': accountKey,
        'providerId': providerId,
      }).then((_) {});

  static Future<void> clearAll() => _invoke('clearAll').then((_) {});

  static Future<void> reschedule() => _invoke('reschedule').then((_) {});

  /// Reads and parses native delivery receipts. Provider ownership is resolved
  /// by AlertCenter, not by this platform adapter.
  static Future<List<ScheduledAlertReceipt>> consumeReceipts() async {
    final raw = await _invoke('consumeReceipts');
    if (raw is! List) return const [];
    final receipts = <ScheduledAlertReceipt>[];
    for (final item in raw) {
      final receipt = ScheduledAlertReceipt.tryParse(item);
      if (receipt != null) receipts.add(receipt);
    }
    return receipts;
  }
}
