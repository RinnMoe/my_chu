import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../capabilities/campus_places/campus_registry.dart';
import '../../services/privacy_agreement_service.dart';
import 'charging_pile_catalog_document.dart';
import 'charging_pile_catalog_source.dart';

/// 目录快照的编排层：内置 → 本机缓存 → 站点目录。
///
/// 站点新增桩位、改桩号、加分区时，**老版本 App 下一次启动就能跟上**，
/// 不需要重新发版。任何一层失败都退回上一层，页面始终有数据可渲染。
/// 用校区清单派生「站点分区前缀 → 本仓库校区 ID」的解析器。
///
/// 命中规则：前缀出现在某个校区的 display_name 或任一 alias 里。站点新增校区时，
/// 只要它对应的校区已经在 `assets/maps/campuses.json` 里，这里就自动生效。
ChargingPileCampusResolver chargingPileCampusResolverForRegistry(
  Iterable<CampusEntry> campuses,
) {
  final entries = campuses.toList(growable: false);
  return (String prefix) {
    if (prefix.isEmpty) return null;
    for (final campus in entries) {
      if (campus.displayName.contains(prefix)) return campus.campusId;
      for (final alias in campus.aliases) {
        if (alias.contains(prefix)) return campus.campusId;
      }
    }
    return null;
  };
}

class ChargingPileCatalogService extends ChangeNotifier {
  factory ChargingPileCatalogService.shared() =>
      _shared ??= ChargingPileCatalogService();

  static ChargingPileCatalogService? _shared;

  ChargingPileCatalogService({
    ChargingPileCatalogSource? bundledSource,
    ChargingPileCatalogSource? remoteSource,
    Future<SharedPreferences> Function()? preferences,
    Future<bool> Function()? consent,
    DateTime Function()? now,
    this.refreshInterval = const Duration(hours: 6),
    this.failureRetryInterval = const Duration(hours: 1),
    this.maxFailureRetryInterval = const Duration(hours: 24),
  }) : _bundled = bundledSource ?? BundledChargingPileCatalogSource(),
       _remote = remoteSource ?? RemoteChargingPileCatalogSource(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _consent = consent ?? PrivacyAgreementService.isAccepted,
       _now = now ?? DateTime.now;

  /// 本机缓存的键；存的是站点目录原文，读回时重新解析。
  static const String storageKey = 'charging_pile.catalog.v1';

  /// 两次成功拉取之间的最小间隔。
  final Duration refreshInterval;
  final Duration failureRetryInterval;
  final Duration maxFailureRetryInterval;

  final ChargingPileCatalogSource _bundled;
  final ChargingPileCatalogSource _remote;
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function() _consent;
  final DateTime Function() _now;

  ChargingPileCatalogDocument? _document;
  Future<ChargingPileCampusResolver>? _campusResolver;

  /// 用地图的校区清单派生「站点前缀 → 校区 ID」：只要分区前缀出现在某个校区的
  /// display_name 或 aliases 里就算命中。站点新增校区时不用改客户端代码。
  Future<ChargingPileCampusResolver> _resolver() {
    return _campusResolver ??= () async {
      try {
        final registry = await CampusRegistryLoader().load();
        return chargingPileCampusResolverForRegistry(registry.campuses);
      } catch (_) {
        // 清单读不出来时返回 null，交给内置表兜底。
        return (String prefix) => null;
      }
    }();
  }
  Future<ChargingPileCatalogDocument>? _loading;
  Future<void>? _refreshing;
  DateTime? _lastAttemptAt;
  int _failureCount = 0;
  bool _disposed = false;

  ChargingPileCatalogDocument? get document => _document;

  bool get isRefreshing => _refreshing != null;

  /// 至少返回一份可用快照：缓存优先，损坏或缺失时退回内置。
  Future<ChargingPileCatalogDocument> ensureLoaded() {
    final existing = _document;
    if (existing != null) return Future.value(existing);
    return _loading ??= _loadFirstSnapshot();
  }

  Future<ChargingPileCatalogDocument> _loadFirstSnapshot() async {
    final campusResolver = await _resolver();
    final cached = await _readCache(campusResolver);
    if (cached != null) {
      _publish(cached);
      unawaited(refresh());
      return cached;
    }
    final bundled = await _bundled.load(campusResolver: campusResolver);
    _publish(bundled.document);
    unawaited(refresh());
    return bundled.document;
  }

  /// 拉一次站点目录。默认按 [refreshInterval] 节流，[force] 跳过节流。
  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    final running = _refreshing;
    if (running != null) return running;
    if (!force && !_isDue()) return Future.value();
    return _refreshing = _runRefresh().whenComplete(() => _refreshing = null);
  }

  bool _isDue() {
    final attempted = _lastAttemptAt;
    if (attempted == null) return true;
    final wait = _failureCount == 0
        ? refreshInterval
        : _backoffFor(_failureCount);
    return _now().difference(attempted) >= wait;
  }

  Duration _backoffFor(int failures) {
    final factor = failures.clamp(1, 8);
    final scaled = failureRetryInterval * factor;
    return scaled > maxFailureRetryInterval
        ? maxFailureRetryInterval
        : scaled;
  }

  Future<void> _runRefresh() async {
    _lastAttemptAt = _now();
    try {
      if (!await _consent()) return;
      final loaded = await _remote.load(campusResolver: await _resolver());
      _failureCount = 0;
      // 指纹相同就不重写缓存、不触发重绘：绝大多数启动拉到的都是同一份。
      if (_document?.catalogVersion == loaded.document.catalogVersion) return;
      _publish(loaded.document);
      await _writeCache(loaded.rawText);
    } on ChargingPileCatalogException {
      _failureCount += 1;
    } on Object {
      _failureCount += 1;
    }
  }

  Future<ChargingPileCatalogDocument?> _readCache(
    ChargingPileCampusResolver campusResolver,
  ) async {
    try {
      final preferences = await _preferences();
      final raw = preferences.getString(storageKey);
      if (raw == null || raw.isEmpty) return null;
      return ChargingPileCatalogDocument.parse(
        raw,
        strictness: ChargingPileCatalogStrictness.tolerant,
        campusResolver: campusResolver,
      );
    } on Object {
      // 缓存损坏或结构超前：丢弃并退回内置，下一次成功拉取会重写。
      await _clearCacheQuietly();
      return null;
    }
  }

  Future<void> _writeCache(String rawText) async {
    try {
      final preferences = await _preferences();
      await preferences.setString(storageKey, rawText);
    } on Object {
      // 缓存是加速手段，写失败只意味着下次冷启动要重新拉。
    }
  }

  Future<void> _clearCacheQuietly() async {
    try {
      final preferences = await _preferences();
      await preferences.remove(storageKey);
    } on Object {
      // 忽略。
    }
  }

  void _publish(ChargingPileCatalogDocument document) {
    if (_disposed) return;
    _document = document;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _remote.close();
    _bundled.close();
    if (identical(_shared, this)) _shared = null;
    super.dispose();
  }
}
