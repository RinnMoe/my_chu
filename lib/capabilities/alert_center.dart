import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/in_app_notification_service.dart';
import '../services/logger_service.dart';
import '../services/scheduled_alert_service.dart';
import 'east8_time.dart';
import 'alert_models.dart';
import 'scheduled_alert.dart';

export 'scheduled_alert.dart';

/// 提醒参数类型（设置页据此渲染输入控件）。
enum AlertParamType {
  /// 数值参数（如余额阈值）。
  number,

  /// 小时数参数（如提前提醒量）。
  hours,

  /// 分钟数参数（如课前提醒）。
  minutes,
}

/// 提醒参数规格：由应用声明，宿主设置页统一渲染。
class AlertParamSpec {
  final String key;
  final String label;
  final AlertParamType type;
  final double defaultValue;
  final double min;
  final double max;
  final String unit;

  const AlertParamSpec({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    required this.min,
    required this.max,
    required this.unit,
  });
}

/// 一次评估产出的提醒草稿：由应用提供条件与文案，宿主负责发布与去重。
class AlertDraft {
  /// Provider 定义的业务指纹；事件型用于历史去重，状态型用于 occurrence 对账。
  final String fingerprintKey;

  final String title;
  final String? body;

  /// 点击提醒后要打开的应用 ID（宿主打开对应应用页）。
  final String? deeplinkAppId;

  /// 单条覆盖严重程度；缺省用提供者默认值。
  final AlertSeverity? severity;

  const AlertDraft({
    required this.fingerprintKey,
    required this.title,
    this.body,
    this.deeplinkAppId,
    this.severity,
  });
}

/// 应用声明的提醒提供者。
///
/// 应用只提供 ID、来源、类型、参数规格与评估函数；评估时机、默认开启、
/// 用户关闭、去重/生命周期、呈现通道全部由宿主 [AlertCenterService] 负责。
class AlertProvider {
  /// 稳定唯一 ID，跨版本不变。
  final String id;

  /// 通知中心分组（来源），例如“教务”“个人数据”。
  final String source;

  /// 设置页展示名称（也是缺省提醒标题）。
  final String title;

  final AlertKind kind;
  final AlertSeverity severity;

  /// 设置页可配置的参数（阈值、提前量等）。
  final List<AlertParamSpec> params;

  /// 评估函数：输入订阅参数与应用数据，输出提醒草稿；不满足条件时返回空。
  final List<AlertDraft> Function(Map<String, Object?> params, Object? data)
  evaluate;

  /// 事件型是否在首次评估时只记录基线而不提醒。
  ///
  /// 用于“新内容”语义（如新的待办）：订阅后第一次评估只建立基线，
  /// 之后出现不同指纹才提醒，避免订阅即对存量内容轰炸。
  final bool baselineOnFirstEvaluation;
  final bool defaultEnabled;

  /// Rebuilds this provider's future system schedule after a setting changes.
  /// The callback is optional because most providers only publish Focus
  /// notifications and have no scheduled projection.
  final Future<void> Function(String accountKey)? refreshScheduled;

  const AlertProvider({
    required this.id,
    required this.source,
    required this.title,
    required this.kind,
    required this.severity,
    required this.evaluate,
    this.params = const [],
    this.baselineOnFirstEvaluation = false,
    this.defaultEnabled = true,
    this.refreshScheduled,
  });

  /// The effective subscription for an account with no explicit preference.
  ///
  /// Defaults are intentionally not persisted: an explicit user choice is
  /// stored separately and takes precedence over this value.
  AlertSubscription defaultSubscription() {
    return AlertSubscription(
      providerId: id,
      enabled: defaultEnabled,
      params: {for (final spec in params) spec.key: spec.defaultValue},
      systemBanner: true,
    );
  }
}

/// 单账号的提醒订阅。
class AlertSubscription {
  final String providerId;
  final bool enabled;
  final Map<String, Object?> params;

  /// 是否允许宿主弹系统横幅；仅对非 info 级提醒生效。
  final bool systemBanner;

  const AlertSubscription({
    required this.providerId,
    required this.enabled,
    this.params = const {},
    this.systemBanner = true,
  });

  AlertSubscription copyWith({
    bool? enabled,
    Map<String, Object?>? params,
    bool? systemBanner,
  }) {
    return AlertSubscription(
      providerId: providerId,
      enabled: enabled ?? this.enabled,
      params: params ?? this.params,
      systemBanner: systemBanner ?? this.systemBanner,
    );
  }

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'enabled': enabled,
    'params': params,
    'systemBanner': systemBanner,
  };

  factory AlertSubscription.fromJson(Map<String, dynamic> json) {
    final providerId = json['providerId'];
    if (providerId is! String || providerId.isEmpty) {
      throw const FormatException('订阅字段缺失');
    }
    final rawParams = json['params'];
    return AlertSubscription(
      providerId: providerId,
      enabled: json['enabled'] == true,
      params:
          rawParams is Map ? Map<String, Object?>.from(rawParams) : const {},
      systemBanner: json['systemBanner'] != false,
    );
  }
}

/// 按账号持久化的提醒订阅存储（SharedPreferences，登出清理）。
class AlertSubscriptionStore {
  static const _keyPrefix = 'alerts.v1.subscriptions.';

  /// 订阅变化时 bump，供设置页刷新。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _key(String accountKey) => '$_keyPrefix$accountKey';

  static Future<List<AlertSubscription>> read(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(accountKey));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = <AlertSubscription>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          items.add(AlertSubscription.fromJson(entry));
        } catch (_) {
          // 跳过损坏条目，不破坏整份订阅。
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  static Future<AlertSubscription?> find(
    String accountKey,
    String providerId,
  ) async {
    final items = await read(accountKey);
    for (final item in items) {
      if (item.providerId == providerId) return item;
    }
    return null;
  }

  static Future<void> upsert(
    String accountKey,
    AlertSubscription subscription,
  ) async {
    final items = [...await read(accountKey)];
    final index = items.indexWhere(
      (item) => item.providerId == subscription.providerId,
    );
    if (index >= 0) {
      items[index] = subscription;
    } else {
      items.add(subscription);
    }
    await _write(accountKey, items);
  }

  static Future<void> _write(
    String accountKey,
    List<AlertSubscription> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(accountKey),
      jsonEncode([for (final item in items) item.toJson()]),
    );
    revision.value++;
  }

  /// 登出/换账号：清理指定账号订阅。
  static Future<void> clearAccount(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(accountKey));
    revision.value++;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((key) => key.startsWith(_keyPrefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    revision.value++;
  }
}

/// 统一提醒能力宿主：评估、订阅门控、去重与条件生命周期。
///
/// 应用只负责注册 [AlertProvider] 并在数据就绪后调用 [evaluate]；
/// 是否提醒、如何提醒、何时移出注意力均由本服务决定。
class AlertCenterService {
  static final Map<String, AlertProvider> _providers = {};
  static final Map<String, _ProviderState> _states = {};
  static final Map<String, Future<void>> _evaluationTails = {};
  static int _evaluationGeneration = 0;

  static void register(AlertProvider provider) {
    _providers[provider.id] = provider;
  }

  static AlertProvider? provider(String id) => _providers[id];

  /// Resolves the persisted subscription or this provider's default for an
  /// account. Subscription policy stays centralized here.
  static Future<AlertSubscription?> effectiveSubscription(
    String accountKey,
    String providerId,
  ) async {
    final provider = _providers[providerId];
    if (provider == null) return null;
    return await AlertSubscriptionStore.find(accountKey, providerId) ??
        provider.defaultSubscription();
  }

  /// 全部已注册提供者，按来源分组排序（供设置页展示）。
  static List<AlertProvider> get providers {
    final list =
        _providers.values.toList()..sort((a, b) {
          final bySource = a.source.compareTo(b.source);
          if (bySource != 0) return bySource;
          return a.id.compareTo(b.id);
        });
    return list;
  }

  /// 清空事件基线和失效旧评估；持久 condition/deadline 生命周期不受影响。
  static void resetState() {
    _evaluationGeneration++;
    _states.clear();
  }

  /// 评估指定提供者：默认开启，用户明确关闭后跳过；事件历史去重，
  /// condition/deadline 按持久 notification 对账。
  ///
  /// 评估是尽力而为的，任何失败都只记日志，绝不影响数据加载路径。
  static Future<void> evaluate(
    String accountKey,
    String providerId,
    Object? data,
  ) async {
    final generation = _evaluationGeneration;
    try {
      await _runSerial(
        _stateKey(accountKey, providerId),
        () => _evaluate(accountKey, providerId, data, generation),
      );
    } catch (error) {
      AppLogger.warn('提醒评估失败 $providerId (${error.runtimeType})');
    }
  }

  /// Rebuilds one provider's bounded future system-notification schedule.
  ///
  /// AlertCenter resolves the effective subscription once and owns delivery
  /// policy. A null builder result means the input was unavailable, so the
  /// existing native schedule is left untouched; an empty list replaces it.
  static Future<void> rebuildScheduled(
    String accountKey,
    String providerId,
    FutureOr<List<ScheduledAlertDraft>?> Function(Map<String, Object?> params)
    build,
  ) async {
    if (accountKey.isEmpty || !ScheduledAlertService.isSupported) return;
    final subscription = await effectiveSubscription(accountKey, providerId);
    if (subscription == null) return;
    if (!subscription.enabled || !subscription.systemBanner) {
      await ScheduledAlertService.clearProvider(accountKey, providerId);
      return;
    }
    final drafts = await build(subscription.params);
    if (drafts == null) return;
    final now = DateTime.now().toUtc();
    final horizon = now.add(const Duration(days: 14));
    final unique = <String, ScheduledAlertDraft>{};
    for (final draft in drafts) {
      if (!draft.triggerAt.isAfter(now) || draft.triggerAt.isAfter(horizon)) {
        continue;
      }
      if (draft.validUntil.isBefore(draft.triggerAt)) continue;
      final eventId = draft.eventId.trim();
      final title = draft.title.trim();
      if (eventId.isEmpty || title.isEmpty) continue;
      final key = '$eventId|${draft.triggerAt.millisecondsSinceEpoch}';
      unique[key] = draft;
    }
    final bounded =
        unique.values.toList()
          ..sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    await ScheduledAlertService.replace(
      accountKey,
      providerId,
      bounded.take(64).toList(growable: false),
    );
  }

  /// Imports native delivery receipts into durable history without another
  /// system banner. Receipt identity is the provider's eventId; provider
  /// presentation metadata comes only from the registered provider.
  static Future<void> importScheduledReceipts(String accountKey) async {
    if (accountKey.isEmpty || !ScheduledAlertService.isSupported) return;
    try {
      final receipts = await ScheduledAlertService.consumeReceipts();
      for (final receipt in receipts) {
        if (receipt.accountKey != accountKey) continue;
        final provider = _providers[receipt.providerId];
        if (provider == null) continue;
        final validUntil = receipt.validUntil;
        await InAppNotificationService.publish(
          accountKey,
          providerId: provider.id,
          source: provider.source,
          title: receipt.title,
          body: receipt.body,
          fingerprintKey: receipt.eventId,
          kind: provider.kind,
          severity: provider.severity,
          deeplinkAppId: receipt.deeplinkAppId,
          expiresAt: validUntil == null
              ? null
              : parseEast8(validUntil.toIso8601String()),
          system: false,
        );
      }
    } catch (error) {
      AppLogger.warn('定时提醒回执导入失败 (${error.runtimeType})');
    }
  }

  static Future<void> clearScheduled(String accountKey, String providerId) =>
      ScheduledAlertService.clearProvider(accountKey, providerId);

  /// Asks a provider to rebuild its bounded future schedule immediately after
  /// a user changes its switch or parameters.
  static Future<void> refreshScheduled(
    String accountKey,
    String providerId,
  ) async {
    final callback = _providers[providerId]?.refreshScheduled;
    if (callback == null) return;
    try {
      await callback(accountKey);
    } catch (error) {
      AppLogger.warn('提醒调度刷新失败 $providerId (${error.runtimeType})');
    }
  }

  static Future<void> _evaluate(
    String accountKey,
    String providerId,
    Object? data,
    int generation,
  ) async {
    if (!_isCurrentGeneration(generation) || accountKey.isEmpty) return;
    final provider = _providers[providerId];
    if (provider == null) return;

    final subscription = await effectiveSubscription(accountKey, providerId);
    if (!_isCurrentGeneration(generation)) return;
    if (subscription == null) return;
    if (!subscription.enabled) return;

    final drafts = provider.evaluate(subscription.params, data);
    if (!_isCurrentGeneration(generation)) return;

    if (provider.kind == AlertKind.event) {
      if (drafts.isEmpty) return;

      // 基线型事件：首次评估只建立内存基线，变化时才尝试发布。
      if (provider.baselineOnFirstEvaluation) {
        final state = _states.putIfAbsent(
          _stateKey(accountKey, providerId),
          _ProviderState.new,
        );
        final current = _combinedKey(drafts);
        final baseline = state.eventBaseline;
        if (baseline == null) {
          state.eventBaseline = current;
          return;
        }
        if (current == baseline) return;
        state.eventBaseline = current;
      }

      for (final draft in drafts) {
        if (!_isCurrentGeneration(generation)) return;
        await _publishDraft(accountKey, provider, subscription, draft);
        if (!_isCurrentGeneration(generation)) return;
      }
      return;
    }

    final currentByFingerprint = <String, AlertDraft>{
      for (final draft in drafts) draft.fingerprintKey: draft,
    };
    final currentFingerprints = currentByFingerprint.keys.toSet();
    final persisted = await InAppNotificationService.list(accountKey);
    if (!_isCurrentGeneration(generation)) return;

    final unresolvedForProvider = persisted
        .where(
          (item) =>
              item.providerId == provider.id &&
              item.kind == provider.kind &&
              !item.resolved,
        )
        .toList(growable: false);
    final staleIds = [
      for (final item in unresolvedForProvider)
        if (!currentFingerprints.contains(item.fingerprintKey)) item.id,
    ];
    if (staleIds.isNotEmpty) {
      if (!_isCurrentGeneration(generation)) return;
      await InAppNotificationService.markResolvedByIds(accountKey, staleIds);
      if (!_isCurrentGeneration(generation)) return;
    }

    final existingFingerprints = {
      for (final item in unresolvedForProvider)
        if (currentFingerprints.contains(item.fingerprintKey))
          item.fingerprintKey,
    };
    for (final draft in currentByFingerprint.values) {
      if (existingFingerprints.contains(draft.fingerprintKey)) continue;
      if (!_isCurrentGeneration(generation)) return;
      await _publishDraft(accountKey, provider, subscription, draft);
      if (!_isCurrentGeneration(generation)) return;
    }
  }

  static Future<void> _publishDraft(
    String accountKey,
    AlertProvider provider,
    AlertSubscription subscription,
    AlertDraft draft,
  ) async {
    final severity = draft.severity ?? provider.severity;
    await InAppNotificationService.publish(
      accountKey,
      source: provider.source,
      title: draft.title,
      body: draft.body,
      providerId: provider.id,
      fingerprintKey: draft.fingerprintKey,
      kind: provider.kind,
      severity: severity,
      deeplinkAppId: draft.deeplinkAppId,
      system: subscription.systemBanner && severity != AlertSeverity.info,
    );
  }

  static bool _isCurrentGeneration(int generation) =>
      generation == _evaluationGeneration;

  static String _stateKey(String accountKey, String providerId) =>
      '$accountKey|$providerId';

  /// Serializes evaluations for one account/provider while leaving unrelated
  /// providers and accounts free to proceed concurrently.
  static Future<T> _runSerial<T>(
    String key,
    Future<T> Function() operation,
  ) async {
    final previous = _evaluationTails[key];
    final release = Completer<void>();
    _evaluationTails[key] = release.future;
    if (previous != null) await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_evaluationTails[key], release.future)) {
        _evaluationTails.remove(key);
      }
    }
  }

  static String _combinedKey(List<AlertDraft> drafts) {
    final keys = [for (final draft in drafts) draft.fingerprintKey]..sort();
    return keys.join('|');
  }
}

class _ProviderState {
  /// 基线型事件最近一次评估的组合指纹。
  String? eventBaseline;
}
