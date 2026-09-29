import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../persistent_summary_cache.dart';
import '../../services/auth_service.dart';
import '../../services/portal_route_service.dart';
import '../../apps/academic_affairs/academic_affairs_models.dart';
import 'academic_schedule_alerts.dart';
import 'academic_schedule_utils.dart';

class AcademicScheduleSemesterCatalog {
  final List<AcademicSemesterOption> semesters;
  final String selectedSemesterId;

  const AcademicScheduleSemesterCatalog({
    required this.semesters,
    required this.selectedSemesterId,
  });

  Map<String, dynamic> toJson() => {
    'selectedSemesterId': selectedSemesterId,
    'semesters': [
      for (final semester in semesters)
        {
          'id': semester.id,
          'label': semester.label,
          'selected': semester.id == selectedSemesterId,
        },
    ],
  };

  factory AcademicScheduleSemesterCatalog.fromJson(Map<String, dynamic> json) {
    final selectedSemesterId = '${json['selectedSemesterId'] ?? ''}'.trim();
    final semesters = <AcademicSemesterOption>[];
    final rawSemesters = json['semesters'];
    if (rawSemesters is List) {
      for (final rawSemester in rawSemesters) {
        if (rawSemester is! Map) continue;
        final semester = Map<String, dynamic>.from(rawSemester);
        final id = '${semester['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        semesters.add(
          AcademicSemesterOption(
            id: id,
            label: '${semester['label'] ?? ''}'.trim(),
            selected: id == selectedSemesterId,
          ),
        );
      }
    }
    return AcademicScheduleSemesterCatalog(
      semesters: semesters.toList(growable: false),
      selectedSemesterId: selectedSemesterId,
    );
  }
}

/// A user-owned replacement for one remote timetable entry.  [sourceKey]
/// always points at the original entry, so a later remote refresh can update
/// the raw snapshot without losing the local edit.
class AcademicScheduleEntryOverride {
  final String sourceKey;
  final AcademicPersonalScheduleEntry entry;

  const AcademicScheduleEntryOverride({
    required this.sourceKey,
    required this.entry,
  });

  Map<String, dynamic> toJson() => {
    'sourceKey': sourceKey,
    'entry': entry.toJson(),
  };

  factory AcademicScheduleEntryOverride.fromJson(Map<String, dynamic> json) {
    final rawEntry = json['entry'];
    return AcademicScheduleEntryOverride(
      sourceKey: '${json['sourceKey'] ?? ''}'.trim(),
      entry:
          rawEntry is Map
              ? AcademicPersonalScheduleEntry.fromJson(
                Map<String, dynamic>.from(rawEntry),
              )
              : const AcademicPersonalScheduleEntry(
                courseSequence: '',
                courseCode: '',
                courseName: '',
                teacher: '',
                location: '',
                weekday: 1,
                startPeriod: 1,
                endPeriod: 1,
                weeksText: '',
                weeks: [],
                practiceWeeks: [],
              ),
    );
  }
}

/// Account- and semester-scoped local timetable changes.
///
/// The remote snapshot remains the source of truth for entries not mentioned
/// here.  [overrides] replaces an original entry, [deletedEntryKeys] hides an
/// original or local entry, and [addedEntries] supplies courses that exist
/// only on this device.
class AcademicScheduleUserLayer {
  final String semesterId;
  final Map<String, AcademicScheduleEntryOverride> overrides;
  final Set<String> deletedEntryKeys;
  final List<AcademicPersonalScheduleEntry> addedEntries;

  const AcademicScheduleUserLayer({
    required this.semesterId,
    this.overrides = const {},
    this.deletedEntryKeys = const {},
    this.addedEntries = const [],
  });

  AcademicScheduleUserLayer copyWith({
    String? semesterId,
    Map<String, AcademicScheduleEntryOverride>? overrides,
    Set<String>? deletedEntryKeys,
    List<AcademicPersonalScheduleEntry>? addedEntries,
  }) {
    return AcademicScheduleUserLayer(
      semesterId: semesterId ?? this.semesterId,
      overrides: overrides ?? this.overrides,
      deletedEntryKeys: deletedEntryKeys ?? this.deletedEntryKeys,
      addedEntries: addedEntries ?? this.addedEntries,
    );
  }

  Map<String, dynamic> toJson() => {
    'semesterId': semesterId,
    'overrides': [for (final value in overrides.values) value.toJson()],
    'deletedEntryKeys': deletedEntryKeys.toList(growable: false),
    'addedEntries': [for (final entry in addedEntries) entry.toJson()],
  };

  factory AcademicScheduleUserLayer.fromJson(Map<String, dynamic> json) {
    final overrides = <String, AcademicScheduleEntryOverride>{};
    final rawOverrides = json['overrides'];
    if (rawOverrides is List) {
      for (final raw in rawOverrides) {
        if (raw is! Map) continue;
        final value = AcademicScheduleEntryOverride.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (value.sourceKey.isNotEmpty) overrides[value.sourceKey] = value;
      }
    }
    final deleted = <String>{};
    final rawDeleted = json['deletedEntryKeys'];
    if (rawDeleted is List) {
      for (final value in rawDeleted) {
        final key = '$value'.trim();
        if (key.isNotEmpty) deleted.add(key);
      }
    }
    final added = <AcademicPersonalScheduleEntry>[];
    final rawAdded = json['addedEntries'];
    if (rawAdded is List) {
      for (final raw in rawAdded) {
        if (raw is Map) {
          added.add(
            AcademicPersonalScheduleEntry.fromJson(
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      }
    }
    return AcademicScheduleUserLayer(
      semesterId: '${json['semesterId'] ?? ''}'.trim(),
      overrides: overrides,
      deletedEntryKeys: deleted,
      addedEntries: added.toList(growable: false),
    );
  }
}

/// Account-scoped persistence for personal timetables from multiple terms.
///
/// Opening the timetable only reads the last selected snapshot. Backend
/// adapters acquire remote data, and this store persists and materializes the
/// canonical result. Logout and account replacement clear every term through
/// [PersistentCacheRegistry].
class AcademicScheduleStore {
  /// Bumped whenever a timetable snapshot is saved or cleared so home cards
  /// and other cached views can refresh without re-reading a stale in-memory
  /// snapshot.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final _defaultScheduleCache =
      PersistentSummaryCache<AcademicPersonalSchedule>(
        // v2 invalidates snapshots created before the Supwisdom week bitmap
        // parser started treating bit 0 as a reserved placeholder.
        storageKey: 'academic.personal_schedule.v2',
        ttl: const Duration(minutes: 5),
        persistTtl: null,
        maxEntries: 32,
        fromJson: AcademicPersonalSchedule.fromJson,
        toJson: (value) => value.toJson(),
      );
  static final _defaultSemesterCache =
      PersistentSummaryCache<AcademicScheduleSemesterCatalog>(
        storageKey: 'academic.personal_schedule.semesters.v1',
        ttl: const Duration(minutes: 5),
        persistTtl: null,
        maxEntries: 4,
        fromJson: AcademicScheduleSemesterCatalog.fromJson,
        toJson: (value) => value.toJson(),
      );
  static final _defaultClassScheduleCache =
      PersistentSummaryCache<AcademicPersonalSchedule>(
        // Keep class schedules on the same corrected bitmap cache epoch.
        storageKey: 'academic.class_schedule.v2',
        ttl: const Duration(minutes: 5),
        persistTtl: const Duration(days: 30),
        maxEntries: 12,
        fromJson: AcademicPersonalSchedule.fromJson,
        toJson: (value) => value.toJson(),
      );
  static final _defaultClassSemesterCache =
      PersistentSummaryCache<AcademicScheduleSemesterCatalog>(
        storageKey: 'academic.class_schedule.semesters.v1',
        ttl: const Duration(minutes: 5),
        persistTtl: const Duration(days: 30),
        maxEntries: 4,
        fromJson: AcademicScheduleSemesterCatalog.fromJson,
        toJson: (value) => value.toJson(),
      );
  static final _defaultUserLayerCache =
      PersistentSummaryCache<AcademicScheduleUserLayer>(
        storageKey: 'academic.personal_schedule.user_layer.v1',
        ttl: const Duration(minutes: 5),
        persistTtl: null,
        maxEntries: 32,
        fromJson: AcademicScheduleUserLayer.fromJson,
        toJson: (value) => value.toJson(),
      );

  final PersistentSummaryCache<AcademicPersonalSchedule> _scheduleCache;
  final PersistentSummaryCache<AcademicScheduleSemesterCatalog> _semesterCache;
  final PersistentSummaryCache<AcademicPersonalSchedule> _classScheduleCache;
  final PersistentSummaryCache<AcademicScheduleSemesterCatalog>
  _classSemesterCache;
  final PersistentSummaryCache<AcademicScheduleUserLayer> _userLayerCache;

  AcademicScheduleStore({
    PersistentSummaryCache<AcademicPersonalSchedule>? scheduleCache,
    PersistentSummaryCache<AcademicScheduleSemesterCatalog>? semesterCache,
    PersistentSummaryCache<AcademicPersonalSchedule>? classScheduleCache,
    PersistentSummaryCache<AcademicScheduleSemesterCatalog>? classSemesterCache,
    PersistentSummaryCache<AcademicScheduleUserLayer>? userLayerCache,
  }) : _scheduleCache = scheduleCache ?? _defaultScheduleCache,
       _semesterCache = semesterCache ?? _defaultSemesterCache,
       _classScheduleCache = classScheduleCache ?? _defaultClassScheduleCache,
       _classSemesterCache = classSemesterCache ?? _defaultClassSemesterCache,
       _userLayerCache = userLayerCache ?? _defaultUserLayerCache;

  Future<AcademicPersonalSchedule?> readCachedSchedule(
    String accountKey,
    String? semesterId, {
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) async {
    final routeScope = await _routeScopeFor(accountKey);
    final resourceKey = _scheduleResourceKey(semesterId, routeScope);
    final cache = _scheduleCacheFor(scope);
    final resolved =
        cache.peek(accountKey, resourceKey) ??
        await cache.readFromDisk(accountKey, resourceKey);
    if (resolved != null) {
      return _materialize(accountKey, resolved, scope);
    }
    if (semesterId == null || semesterId.trim().isEmpty) {
      return null;
    }
    final current = await readCachedCurrentSchedule(accountKey, scope: scope);
    if (current?.semesterId == semesterId.trim()) return current;
    return null;
  }

  /// Reads the last selected timetable snapshot without starting a request.
  Future<AcademicPersonalSchedule?> readCachedCurrentSchedule(
    String accountKey, {
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) => readCachedSchedule(accountKey, null, scope: scope);

  Future<AcademicScheduleSemesterCatalog?> readCachedSemesterCatalog(
    String accountKey, {
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) async {
    final resourceKey = 'catalog.${await _routeScopeFor(accountKey)}';
    final cache = _semesterCacheFor(scope);
    return cache.peek(accountKey, resourceKey) ??
        await cache.readFromDisk(accountKey, resourceKey);
  }

  Future<AcademicScheduleUserLayer?> readUserLayer(
    String accountKey,
    String semesterId,
  ) async {
    final normalized = semesterId.trim();
    if (normalized.isEmpty) return null;
    final resourceKey = 'semester.$normalized';
    return _userLayerCache.peek(accountKey, resourceKey) ??
        await _userLayerCache.readFromDisk(accountKey, resourceKey);
  }

  Future<void> updateUserLayer(
    String accountKey,
    AcademicScheduleUserLayer layer,
  ) async {
    final semesterId = layer.semesterId.trim();
    if (semesterId.isEmpty) return;
    await _userLayerCache.load(
      accountKey,
      'semester.$semesterId',
      () async => layer.copyWith(semesterId: semesterId),
      force: true,
    );
    AcademicScheduleStore.revision.value++;
    final schedule = await readCachedSchedule(accountKey, semesterId);
    if (schedule != null) scheduleAcademicCourseAlerts(accountKey, schedule);
  }

  /// Saves a page editor result and returns the resulting materialized schedule.
  ///
  /// The page supplies the materialized schedule and the original entry only;
  /// source-key resolution and the distinction between local-added and
  /// remote-backed entries stay inside the store.
  Future<AcademicPersonalSchedule?> saveUserEntry(
    String accountKey,
    AcademicPersonalSchedule schedule, {
    AcademicPersonalScheduleEntry? original,
    required AcademicPersonalScheduleEntry edited,
  }) async {
    final semesterId = schedule.semesterId.trim();
    if (semesterId.isEmpty) return null;
    var layer =
        await readUserLayer(accountKey, semesterId) ??
        AcademicScheduleUserLayer(semesterId: semesterId);
    if (original == null) {
      layer = layer.copyWith(addedEntries: [...layer.addedEntries, edited]);
    } else {
      final originalKey = academicScheduleEntryKey(original);
      final addedIndex = layer.addedEntries.indexWhere(
        (candidate) =>
            identical(candidate, original) ||
            academicScheduleEntryKey(candidate) == originalKey,
      );
      if (addedIndex >= 0) {
        final added = [...layer.addedEntries];
        added[addedIndex] = edited;
        layer = layer.copyWith(addedEntries: added);
      } else {
        final sourceKey = _sourceKeyForMaterializedEntry(layer, original);
        final overrides = {
          ...layer.overrides,
          sourceKey: AcademicScheduleEntryOverride(
            sourceKey: sourceKey,
            entry: edited,
          ),
        };
        final deleted = {...layer.deletedEntryKeys}..remove(sourceKey);
        layer = layer.copyWith(overrides: overrides, deletedEntryKeys: deleted);
      }
    }
    await updateUserLayer(accountKey, layer);
    return readCachedSchedule(accountKey, semesterId);
  }

  /// Deletes a page editor entry and returns the resulting materialized schedule.
  Future<AcademicPersonalSchedule?> deleteUserEntry(
    String accountKey,
    AcademicPersonalSchedule schedule,
    AcademicPersonalScheduleEntry original,
  ) async {
    final semesterId = schedule.semesterId.trim();
    if (semesterId.isEmpty) return null;
    var layer =
        await readUserLayer(accountKey, semesterId) ??
        AcademicScheduleUserLayer(semesterId: semesterId);
    final originalKey = academicScheduleEntryKey(original);
    final added = [
      for (final candidate in layer.addedEntries)
        if (!identical(candidate, original) &&
            academicScheduleEntryKey(candidate) != originalKey)
          candidate,
    ];
    if (added.length != layer.addedEntries.length) {
      layer = layer.copyWith(addedEntries: added);
    } else {
      final sourceKey = _sourceKeyForMaterializedEntry(layer, original);
      final deleted = {...layer.deletedEntryKeys, sourceKey};
      final overrides = {...layer.overrides}..remove(sourceKey);
      layer = layer.copyWith(overrides: overrides, deletedEntryKeys: deleted);
    }
    await updateUserLayer(accountKey, layer);
    return readCachedSchedule(accountKey, semesterId);
  }

  Future<AcademicPersonalSchedule?> clearUserLayer(
    String accountKey, {
    String? semesterId,
  }) async {
    final normalizedSemesterId = semesterId?.trim();
    if (semesterId == null || semesterId.trim().isEmpty) {
      await _userLayerCache.clearAccount(accountKey);
    } else {
      await _userLayerCache.invalidate(
        accountKey,
        'semester.$normalizedSemesterId',
      );
    }
    AcademicScheduleStore.revision.value++;
    final schedule =
        normalizedSemesterId == null || normalizedSemesterId.isEmpty
            ? await readCachedCurrentSchedule(accountKey)
            : await readCachedSchedule(accountKey, normalizedSemesterId);
    if (schedule != null) scheduleAcademicCourseAlerts(accountKey, schedule);
    return schedule;
  }

  /// Makes an already cached semester the current snapshot without writing a
  /// materialized user edit back into the raw remote cache.
  Future<AcademicScheduleFetchResult?> activateCachedSchedule(
    String accountKey,
    String semesterId, {
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) async {
    final normalizedId = semesterId.trim();
    if (normalizedId.isEmpty) return null;
    final routeScope = await _routeScopeFor(accountKey);
    final cache = _scheduleCacheFor(scope);
    final resourceKey = _scheduleResourceKey(normalizedId, routeScope);
    final raw =
        cache.peek(accountKey, resourceKey) ??
        await cache.readFromDisk(accountKey, resourceKey);
    if (raw == null) return null;

    await _writeSchedule(
      accountKey,
      _scheduleResourceKey(null, routeScope),
      raw,
      cache,
    );
    final existingCatalog = await readCachedSemesterCatalog(
      accountKey,
      scope: scope,
    );
    final normalizedSemesters = mergeScheduleSemesterSelection([
      ...?existingCatalog?.semesters,
    ], raw);
    await _semesterCacheFor(scope).load(
      accountKey,
      'catalog.$routeScope',
      () async => AcademicScheduleSemesterCatalog(
        semesters: normalizedSemesters,
        selectedSemesterId: normalizedId,
      ),
      force: true,
    );
    final materialized = await _materialize(accountKey, raw, scope);
    if (scope == AcademicScheduleScope.personal) {
      AcademicScheduleStore.revision.value++;
      scheduleAcademicCourseAlerts(accountKey, materialized);
    }
    return AcademicScheduleFetchResult(
      schedule: materialized,
      semesters: normalizedSemesters,
    );
  }

  /// Persists an acquisition result and returns the canonical materialized
  /// result used by pages and home modules.
  Future<AcademicScheduleFetchResult> saveFetchedSchedule(
    String accountKey,
    AcademicScheduleFetchResult result, {
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) async {
    final schedule = result.schedule;
    final existingCatalog = await readCachedSemesterCatalog(
      accountKey,
      scope: scope,
    );
    final normalizedSemesters = mergeScheduleSemesterSelection([
      ...?existingCatalog?.semesters,
      ...result.semesters,
    ], schedule);
    final semesterId = schedule.semesterId.trim();
    final routeScope = await _routeScopeFor(accountKey);
    final scheduleCache = _scheduleCacheFor(scope);
    if (semesterId.isNotEmpty) {
      await _writeSchedule(
        accountKey,
        _scheduleResourceKey(semesterId, routeScope),
        schedule,
        scheduleCache,
      );
    }
    await _writeSchedule(
      accountKey,
      _scheduleResourceKey(null, routeScope),
      schedule,
      scheduleCache,
    );
    await _semesterCacheFor(scope).load(
      accountKey,
      'catalog.$routeScope',
      () async => AcademicScheduleSemesterCatalog(
        semesters: normalizedSemesters,
        selectedSemesterId: semesterId,
      ),
      force: true,
    );
    final materialized = await _materialize(accountKey, schedule, scope);
    if (scope == AcademicScheduleScope.personal) {
      AcademicScheduleStore.revision.value++;
      scheduleAcademicCourseAlerts(accountKey, materialized);
    }
    return AcademicScheduleFetchResult(
      schedule: materialized,
      semesters: normalizedSemesters,
    );
  }

  Future<void> _writeSchedule(
    String accountKey,
    String resourceKey,
    AcademicPersonalSchedule schedule,
    PersistentSummaryCache<AcademicPersonalSchedule> cache,
  ) async {
    await cache.load(
      accountKey,
      resourceKey,
      () async => schedule,
      force: true,
    );
  }

  Future<void> clearAccount(String accountKey) async {
    await _scheduleCache.clearAccount(accountKey);
    await _semesterCache.clearAccount(accountKey);
    await _classScheduleCache.clearAccount(accountKey);
    await _classSemesterCache.clearAccount(accountKey);
    await _userLayerCache.clearAccount(accountKey);
    AcademicScheduleStore.revision.value++;
  }

  PersistentSummaryCache<AcademicPersonalSchedule> _scheduleCacheFor(
    AcademicScheduleScope scope,
  ) => switch (scope) {
    AcademicScheduleScope.personal => _scheduleCache,
    AcademicScheduleScope.administrativeClass => _classScheduleCache,
  };

  PersistentSummaryCache<AcademicScheduleSemesterCatalog> _semesterCacheFor(
    AcademicScheduleScope scope,
  ) => switch (scope) {
    AcademicScheduleScope.personal => _semesterCache,
    AcademicScheduleScope.administrativeClass => _classSemesterCache,
  };

  static String _scheduleResourceKey(String? semesterId, String routeScope) {
    final value = semesterId?.trim() ?? '';
    final resource = value.isEmpty ? 'current' : 'semester.$value';
    return '$routeScope.$resource';
  }

  String _sourceKeyForMaterializedEntry(
    AcademicScheduleUserLayer layer,
    AcademicPersonalScheduleEntry entry,
  ) {
    final entryKey = academicScheduleEntryKey(entry);
    for (final item in layer.overrides.entries) {
      final overrideEntry = item.value.entry;
      if (identical(overrideEntry, entry) ||
          academicScheduleEntryKey(overrideEntry) == entryKey) {
        return item.key;
      }
    }
    return entryKey;
  }

  Future<AcademicPersonalSchedule> _materialize(
    String accountKey,
    AcademicPersonalSchedule schedule,
    AcademicScheduleScope scope,
  ) async {
    if (scope != AcademicScheduleScope.personal ||
        schedule.semesterId.trim().isEmpty) {
      return schedule;
    }
    final layer = await readUserLayer(accountKey, schedule.semesterId);
    if (layer == null) return schedule;
    final legacyKeyCounts = <String, int>{};
    for (final entry in schedule.entries) {
      final key = academicScheduleLegacyEntryKey(entry);
      legacyKeyCounts[key] = (legacyKeyCounts[key] ?? 0) + 1;
    }
    final entries = <AcademicPersonalScheduleEntry>[];
    for (final entry in schedule.entries) {
      final sourceKey = academicScheduleEntryKey(entry);
      final legacyKey = academicScheduleLegacyEntryKey(entry);
      final legacyKeyIsUnique = legacyKeyCounts[legacyKey] == 1;
      final override =
          layer.overrides[sourceKey] ??
          (legacyKeyIsUnique ? layer.overrides[legacyKey] : null);
      final deleted =
          layer.deletedEntryKeys.contains(sourceKey) ||
          (legacyKeyIsUnique && layer.deletedEntryKeys.contains(legacyKey));
      if (deleted) continue;
      entries.add(override?.entry ?? entry);
    }
    for (final entry in layer.addedEntries) {
      if (!layer.deletedEntryKeys.contains(academicScheduleEntryKey(entry))) {
        entries.add(entry);
      }
    }
    return schedule.copyWith(entries: entries.toList(growable: false));
  }

  /// Schedule snapshots are personal and also depend on the selected
  /// academic identity. Tests without an authenticated account use the
  /// stable `unknown` scope; production pages resolve identity before making
  /// a network request, so an unrecognised identity never aliases a student
  /// route.
  static Future<String> _routeScopeFor(String accountKey) async {
    try {
      final account = await AuthService.getCurrentAccount();
      if (account == null || account.accountKey != accountKey) return 'unknown';
      return PortalRoute.fromIdentity(account.identity)?.studentType.name ??
          'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}

/// 课表页的账号级显示偏好，与 `HomeLayoutService`/`NavigationLayoutService`
/// 同一套机制：`SharedPreferences` 键带 `accountKey` 后缀，退出登录不清除，
/// 登录替换账号后旧键成为无害的孤儿键（`accountKey` 每次登录随机生成）。
class AcademicScheduleDisplayPreferences {
  static const _showNonCurrentPrefix = 'academic_schedule.show_noncurrent.v1.';
  static const _hideWeekendPrefix = 'academic_schedule.hide_weekend.v1.';

  /// Bumped whenever a stored preference changes so pages can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Whether the week grid also shows dimmed non-current-week courses.
  /// Defaults to on.
  static Future<bool> readShowNonCurrent(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_showNonCurrentPrefix$accountKey') ?? true;
  }

  static Future<void> setShowNonCurrent(String accountKey, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_showNonCurrentPrefix$accountKey', value);
    revision.value++;
  }

  /// Whether Saturday and Sunday are hidden from the timetable grid.
  /// Defaults to off; hiding them never changes the stored schedule or export.
  static Future<bool> readHideWeekend(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_hideWeekendPrefix$accountKey') ?? false;
  }

  static Future<void> setHideWeekend(String accountKey, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_hideWeekendPrefix$accountKey', value);
    revision.value++;
  }
}
