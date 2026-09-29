import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capabilities/east8_time.dart';
import '../capabilities/alert_models.dart';
import 'demo_data_service.dart';
import 'local_notification_bridge.dart';

/// 应用内提醒条目：由宿主聚合各应用/能力发布的变化提醒，按账号持久化。
///
/// 新提醒以 [providerId] 和 [fingerprintKey] 标识。事件型记录永久参与历史
/// 去重；condition/deadline 仅在 occurrence 未解决时阻止重复发布。
class InAppNotification {
  final String id;
  final String? providerId;
  final String source;
  final String title;
  final String? body;
  final String fingerprintKey;
  final DateTime createdAt;
  final bool read;
  final bool resolved;
  final AlertKind kind;
  final AlertSeverity severity;
  final String? deeplinkAppId;

  /// Optional absolute East-8 wall-clock expiry for deadline projections.
  /// Historical notifications without this field remain non-expiring.
  final DateTime? expiresAt;

  const InAppNotification({
    required this.id,
    required this.source,
    required this.title,
    required this.fingerprintKey,
    required this.createdAt,
    this.providerId,
    this.body,
    this.read = false,
    this.resolved = false,
    this.kind = AlertKind.event,
    this.severity = AlertSeverity.info,
    this.deeplinkAppId,
    this.expiresAt,
  });

  InAppNotification copyWith({bool? read, bool? resolved}) {
    return InAppNotification(
      id: id,
      providerId: providerId,
      source: source,
      title: title,
      body: body,
      fingerprintKey: fingerprintKey,
      createdAt: createdAt,
      read: read ?? this.read,
      resolved: resolved ?? this.resolved,
      kind: kind,
      severity: severity,
      deeplinkAppId: deeplinkAppId,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (providerId != null) 'providerId': providerId,
    'source': source,
    'title': title,
    'body': body,
    'fingerprintKey': fingerprintKey,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
    'resolved': resolved,
    'kind': kind.name,
    'severity': severity.name,
    if (deeplinkAppId != null) 'deeplinkAppId': deeplinkAppId,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };

  factory InAppNotification.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'];
    final createdAt = createdAtRaw is String ? parseEast8(createdAtRaw) : null;
    final id = json['id'];
    final source = json['source'];
    final title = json['title'];
    final fingerprintKey = json['fingerprintKey'];
    if (id is! String ||
        source is! String ||
        title is! String ||
        fingerprintKey is! String ||
        createdAt == null) {
      throw const FormatException('notification 字段缺失');
    }
    return InAppNotification(
      id: id,
      providerId:
          json['providerId'] is String ? json['providerId'] as String : null,
      source: source,
      title: title,
      body: json['body'] is String ? json['body'] as String : null,
      fingerprintKey: fingerprintKey,
      createdAt: createdAt,
      read: json['read'] == true,
      resolved: json['resolved'] == true,
      kind: AlertKind.values.asNameMap()[json['kind']] ?? AlertKind.event,
      severity:
          AlertSeverity.values.asNameMap()[json['severity']] ??
          AlertSeverity.info,
      deeplinkAppId:
          json['deeplinkAppId'] is String
              ? json['deeplinkAppId'] as String
              : null,
      expiresAt:
          json['expiresAt'] is String
              ? parseEast8(json['expiresAt'] as String)
              : null,
    );
  }
}

/// Account-scoped in-app notification center, keyed by `accountKey`.
///
/// Persists up to [maxEntries] notifications per account in
/// `SharedPreferences`; the list survives cold starts and is cleared on
/// sign-out through the same hooks as other account-scoped data.
class InAppNotificationService {
  static const maxEntries = 50;

  static const _keyPrefix = 'inapp.notifications.v2.';

  /// Bumped on every write so pages and the home bell can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static int _sequence = 0;
  static final Map<String, Future<void>> _accountMutationTails = {};
  static Future<void> _clearAllBarrier = Future<void>.value();

  static String _key(String accountKey) => '$_keyPrefix$accountKey';

  /// Newest first.
  static Future<List<InAppNotification>> list(String accountKey) async {
    final demo = DemoDataService.instance;
    if (demo.enabled) return _demoNotifications();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(accountKey));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = <InAppNotification>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          items.add(InAppNotification.fromJson(entry));
        } catch (_) {
          // Skip malformed entries instead of breaking the whole list.
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  static List<InAppNotification> _demoNotifications() {
    final demo = DemoDataService.instance;
    final config = demo.config;
    final now = demo.now;
    return [
      if (config.gradeNotification)
        InAppNotification(
          id: 'demo-grade',
          source: '教务',
          title: '成绩更新：高等数学',
          body: '成绩',
          fingerprintKey: 'demo-grade',
          createdAt: now,
          kind: AlertKind.event,
          severity: AlertSeverity.warning,
          deeplinkAppId: 'feature.academic.grades',
        ),
      if (config.balanceNotification)
        InAppNotification(
          id: 'demo-balance',
          source: '个人数据',
          title: '校园卡余额不足',
          body: '当前余额低于 10 元',
          fingerprintKey: 'demo-balance',
          createdAt: now,
          kind: AlertKind.condition,
          severity: AlertSeverity.warning,
          deeplinkAppId: 'feature.portal.personal',
        ),
      if (config.liveUpdateNotification)
        InAppNotification(
          id: 'demo-live-update',
          source: '我的课表',
          title: '课程实时动态',
          body: '下一节课 14:00 开始',
          fingerprintKey: 'demo-live-update',
          createdAt: now,
          kind: AlertKind.deadline,
          severity: AlertSeverity.info,
          deeplinkAppId: 'feature.academic.schedule',
        ),
    ];
  }

  static Future<int> unreadCount(String accountKey) async {
    final items = await list(accountKey);
    return items.where((item) => !item.read && !item.resolved).length;
  }

  /// 当前需要被注意的条目（未读且未解决），最新在前，最多 [limit] 条。
  static Future<List<InAppNotification>> activeList(
    String accountKey, {
    int limit = 3,
  }) async {
    final items = await list(accountKey);
    final now = east8Now();
    return items
        .where(
          (item) =>
              !item.read &&
              !item.resolved &&
              (item.expiresAt == null || item.expiresAt!.isAfter(now)),
        )
        .take(limit)
        .toList(growable: false);
  }

  /// Persists a notification unless its occurrence already exists. Events use
  /// historical provider/fingerprint dedupe; conditions and deadlines only
  /// dedupe against unresolved occurrences. Callers without a provider ID keep
  /// the legacy source/fingerprint behavior. System banners are best-effort.
  ///
  /// [system] 控制是否弹系统横幅（订阅制下由宿主决定）；默认不弹。
  static Future<InAppNotification?> publish(
    String accountKey, {
    required String source,
    required String title,
    required String fingerprintKey,
    String? providerId,
    String? body,
    AlertKind kind = AlertKind.event,
    AlertSeverity severity = AlertSeverity.info,
    String? deeplinkAppId,
    DateTime? expiresAt,
    bool system = false,
  }) async {
    return _runAccountSerial<InAppNotification?>(accountKey, () async {
      final items = await list(accountKey);
      final duplicate = items.any((item) {
        if (providerId == null) {
          if (item.providerId != null ||
              item.source != source ||
              item.fingerprintKey != fingerprintKey) {
            return false;
          }
        } else if (item.providerId != providerId ||
            item.fingerprintKey != fingerprintKey) {
          return false;
        }

        return switch (kind) {
          AlertKind.event => true,
          AlertKind.condition || AlertKind.deadline => !item.resolved,
        };
      });
      if (duplicate) return null;

      final notification = InAppNotification(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
        providerId: providerId,
        source: source,
        title: title,
        body: body,
        fingerprintKey: fingerprintKey,
        createdAt: east8Now(),
        kind: kind,
        severity: severity,
        deeplinkAppId: deeplinkAppId,
        expiresAt: expiresAt,
      );
      final updated = [notification, ...items];
      if (updated.length > maxEntries) {
        updated.removeRange(maxEntries, updated.length);
      }
      await _write(accountKey, updated);
      if (system) {
        await _publishSystem(notification);
      }
      return notification;
    });
  }

  static Future<void> markRead(String accountKey, String id) async {
    await _runAccountSerial(accountKey, () async {
      final items = await list(accountKey);
      final index = items.indexWhere((item) => item.id == id && !item.read);
      if (index < 0) return;
      items[index] = items[index].copyWith(read: true);
      await _write(accountKey, items);
    });
  }

  static Future<void> markAllRead(String accountKey) async {
    await _runAccountSerial(accountKey, () async {
      final items = await list(accountKey);
      if (items.isEmpty || items.every((item) => item.read)) return;
      await _write(accountKey, [
        for (final item in items) item.copyWith(read: true),
      ]);
    });
  }

  /// Marks the selected persisted occurrences resolved without changing read
  /// state. AlertCenter determines which IDs are stale for the current provider.
  static Future<void> markResolvedByIds(
    String accountKey,
    Iterable<String> ids,
  ) async {
    final targetIds = ids.toSet();
    if (targetIds.isEmpty) return;
    await _runAccountSerial(accountKey, () async {
      final items = await list(accountKey);
      var changed = false;
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (targetIds.contains(item.id) && !item.resolved) {
          items[i] = item.copyWith(resolved: true);
          changed = true;
        }
      }
      if (changed) await _write(accountKey, items);
    });
  }

  /// Drops every notification for one account (sign-out / account change).
  static Future<void> clearAccount(String accountKey) async {
    await _runAccountSerial(accountKey, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(accountKey));
      revision.value++;
    });
  }

  /// Drops every notification across all accounts.
  static Future<void> clearAll() async {
    final previousBarrier = _clearAllBarrier;
    final activeMutations = List<Future<void>>.of(_accountMutationTails.values);
    final release = Completer<void>();
    _clearAllBarrier = release.future;
    try {
      await previousBarrier;
      await Future.wait(activeMutations);
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs.getKeys().where((key) => key.startsWith(_keyPrefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      revision.value++;
    } finally {
      release.complete();
      if (identical(_clearAllBarrier, release.future)) {
        _clearAllBarrier = Future<void>.value();
      }
    }
  }

  static Future<void> _write(
    String accountKey,
    List<InAppNotification> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(accountKey),
      jsonEncode([for (final item in items) item.toJson()]),
    );
    revision.value++;
  }

  static Future<T> _runAccountSerial<T>(
    String accountKey,
    Future<T> Function() operation,
  ) async {
    final barrier = _clearAllBarrier;
    final previous = _accountMutationTails[accountKey];
    final release = Completer<void>();
    _accountMutationTails[accountKey] = release.future;
    if (previous != null) await previous;
    await barrier;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_accountMutationTails[accountKey], release.future)) {
        _accountMutationTails.remove(accountKey);
      }
    }
  }

  static Future<void> _publishSystem(InAppNotification notification) async {
    try {
      await LocalNotificationBridge.show(
        id: notification.id.hashCode & 0x7fffffff,
        title: notification.title,
        body: notification.body,
      );
    } catch (_) {
      // System banner failures never affect the in-app path.
    }
  }
}
