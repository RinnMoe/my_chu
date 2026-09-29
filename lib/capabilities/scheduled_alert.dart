import 'package:flutter/foundation.dart';

/// Minimal future notification payload persisted by the platform host.
///
/// [triggerAt] and [validUntil] are absolute instants.  Feature code that
/// starts with East-8 wall-clock fields must convert them with
/// `east8WallClockToUtcInstant` before constructing this object.
@immutable
class ScheduledAlertDraft {
  final String eventId;
  final DateTime triggerAt;
  final String title;
  final String? body;
  final String? deeplinkAppId;
  final DateTime validUntil;

  const ScheduledAlertDraft({
    required this.eventId,
    required this.triggerAt,
    required this.title,
    this.body,
    this.deeplinkAppId,
    required this.validUntil,
  });

  Map<String, dynamic> toJson({
    required String accountKey,
    required String providerId,
  }) => {
    'accountKey': accountKey,
    'providerId': providerId,
    'eventId': eventId,
    'triggerAt': triggerAt.millisecondsSinceEpoch,
    'title': title,
    if (body != null && body!.isNotEmpty) 'body': body,
    if (deeplinkAppId != null && deeplinkAppId!.isNotEmpty)
      'targetAppId': deeplinkAppId,
    'validUntil': validUntil.millisecondsSinceEpoch,
  };
}

/// A typed description of a native scheduled notification that was delivered.
///
/// Receipt payloads contain transport and occurrence identity only. Alert
/// provider metadata is resolved by AlertCenter after parsing.
@immutable
class ScheduledAlertReceipt {
  final String key;
  final String accountKey;
  final String providerId;
  final String eventId;
  final String title;
  final String? body;
  final String? deeplinkAppId;
  final DateTime? validUntil;

  const ScheduledAlertReceipt({
    required this.key,
    required this.accountKey,
    required this.providerId,
    required this.eventId,
    required this.title,
    this.body,
    this.deeplinkAppId,
    this.validUntil,
  });

  static ScheduledAlertReceipt? tryParse(Object? value) {
    if (value is! Map) return null;
    try {
      String requiredString(String key) {
        final raw = value[key];
        if (raw is! String || raw.trim().isEmpty) {
          throw const FormatException('scheduled receipt field missing');
        }
        return raw;
      }

      String? optionalString(String key) {
        final raw = value[key];
        if (raw == null) return null;
        if (raw is! String) {
          throw const FormatException('invalid scheduled receipt field');
        }
        return raw.isEmpty ? null : raw;
      }

      final rawValidUntil = value['validUntil'];
      DateTime? validUntil;
      if (rawValidUntil != null) {
        if (rawValidUntil is! num ||
            !rawValidUntil.isFinite ||
            rawValidUntil <= 0 ||
            rawValidUntil != rawValidUntil.toInt()) {
          throw const FormatException('invalid scheduled receipt timestamp');
        }
        validUntil = DateTime.fromMillisecondsSinceEpoch(
          rawValidUntil.toInt(),
          isUtc: true,
        );
      }

      return ScheduledAlertReceipt(
        key: requiredString('key'),
        accountKey: requiredString('accountKey'),
        providerId: requiredString('providerId'),
        eventId: requiredString('eventId'),
        title: requiredString('title'),
        body: optionalString('body'),
        deeplinkAppId: optionalString('targetAppId'),
        validUntil: validUntil,
      );
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }
}
