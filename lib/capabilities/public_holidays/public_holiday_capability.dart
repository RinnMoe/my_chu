import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/public_http_client.dart';
import 'public_holiday_models.dart';

class PublicHolidayParseException implements Exception {
  final String message;

  const PublicHolidayParseException(this.message);

  @override
  String toString() => message;
}

/// Decodes the strict JSON contract published by holiday-cn.
class PublicHolidayParser {
  static PublicHolidayYear parse(
    String body, {
    required int expectedSourceYear,
    PublicHolidaySourceType sourceType = PublicHolidaySourceType.remote,
    String? sourceUrl,
    DateTime? fetchedAt,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const PublicHolidayParseException('公共节假日数据不是 JSON 对象');
      }
      final json = Map<String, dynamic>.from(decoded);
      final year = json['year'];
      if (year is! int || year != expectedSourceYear) {
        throw const PublicHolidayParseException('公共节假日公告年份无效');
      }

      final rawPapers = json['papers'];
      if (rawPapers is! List || rawPapers.any((item) => item is! String)) {
        throw const PublicHolidayParseException('公共节假日公告来源格式无效');
      }
      final papers = [for (final paper in rawPapers) paper as String];

      final rawDays = json['days'];
      if (rawDays is! List) {
        throw const PublicHolidayParseException('公共节假日日期列表格式无效');
      }
      final days = <PublicHolidayDay>[];
      for (final rawDay in rawDays) {
        if (rawDay is! Map) {
          throw const PublicHolidayParseException('公共节假日日期条目格式无效');
        }
        final day = Map<String, dynamic>.from(rawDay);
        final name = day['name'];
        final dateText = day['date'];
        final isOffDay = day['isOffDay'];
        if (name is! String || name.trim().isEmpty) {
          throw const PublicHolidayParseException('公共节假日名称无效');
        }
        if (dateText is! String) {
          throw const PublicHolidayParseException('公共节假日日期格式无效');
        }
        if (isOffDay is! bool) {
          throw const PublicHolidayParseException('公共节假日休息状态无效');
        }
        days.add(
          PublicHolidayDay(
            date: _parseDate(dateText),
            name: name.trim(),
            isOffDay: isOffDay,
            sourceYear: expectedSourceYear,
          ),
        );
      }

      return PublicHolidayYear(
        sourceYear: expectedSourceYear,
        papers: papers,
        days: days,
        status:
            days.isEmpty
                ? PublicHolidayYearStatus.empty
                : PublicHolidayYearStatus.available,
        sourceType: sourceType,
        sourceUrl: sourceUrl,
        fetchedAt: fetchedAt,
      );
    } on PublicHolidayParseException {
      rethrow;
    } on FormatException {
      throw const PublicHolidayParseException('公共节假日数据不是有效 JSON');
    } catch (_) {
      throw const PublicHolidayParseException('公共节假日数据格式无效');
    }
  }

  static DateTime _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const PublicHolidayParseException('公共节假日日期格式无效');
    }
    final parts = value.split('-');
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    if (date.year != int.parse(parts[0]) ||
        date.month != int.parse(parts[1]) ||
        date.day != int.parse(parts[2])) {
      throw const PublicHolidayParseException('公共节假日日期不存在');
    }
    return date;
  }
}

typedef PublicHolidayRemoteLoader = Future<String> Function(Uri uri);

/// Reads bundled snapshots, refreshes them from the fixed upstream endpoints,
/// and falls back to a validated stale cache when the network is unavailable.
class PublicHolidayRepository {
  static const assetDirectory = 'assets/data/public_holidays';
  static const cachePrefix = 'public.holidays.v1';
  static const cacheTtl = Duration(hours: 24);

  /// Update this timestamp whenever the bundled JSON snapshots are updated.
  /// Cached responses fetched after this point remain preferred because they
  /// may contain a newer upstream arrangement than the app bundle.
  static final bundledSnapshotAt = DateTime.utc(2026, 9, 4);

  final Future<String> Function(String path) loadAsset;
  final Future<SharedPreferences> Function() preferences;
  final PublicHolidayRemoteLoader? _remoteLoaderOverride;
  final DateTime Function() clock;
  final Duration cacheLifetime;
  final PublicHttpClient _httpClient;
  final bool _ownsHttpClient;
  final Map<int, Future<PublicHolidayYear>> _inFlight = {};
  final Map<int, Future<void>> _refreshInFlight = {};
  final Map<int, PublicHolidayYear> _memory = {};
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _closed = false;

  PublicHolidayRepository({
    Future<String> Function(String path)? loadAsset,
    Future<SharedPreferences> Function()? preferences,
    PublicHolidayRemoteLoader? remoteLoader,
    DateTime Function()? clock,
    this.cacheLifetime = cacheTtl,
    PublicHttpClient? httpClient,
  }) : loadAsset = loadAsset ?? rootBundle.loadString,
       preferences = preferences ?? SharedPreferences.getInstance,
       _remoteLoaderOverride = remoteLoader,
       clock = clock ?? DateTime.now,
       _httpClient = httpClient ?? PublicHttpClient(),
       _ownsHttpClient = httpClient == null;

  static Uri primaryUri(int sourceYear) => Uri.parse(
    'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/'
    '$sourceYear.json',
  );

  static Uri fallbackUri(int sourceYear) => Uri.parse(
    'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/'
    '$sourceYear.json',
  );

  Future<PublicHolidayYear> loadYear(int sourceYear, {bool force = false}) {
    final running = _inFlight[sourceYear];
    if (running != null) return running;

    late final Future<PublicHolidayYear> future;
    future = _loadYear(sourceYear, force: force).whenComplete(() {
      if (identical(_inFlight[sourceYear], future)) {
        _inFlight.remove(sourceYear);
      }
    });
    _inFlight[sourceYear] = future;
    return future;
  }

  Future<PublicHolidayYear> _loadYear(
    int sourceYear, {
    required bool force,
  }) async {
    final inMemory = _memory[sourceYear];
    if (inMemory != null && !force && _isFresh(inMemory)) {
      return inMemory;
    }

    if (!force) {
      final cached = await _loadCached(sourceYear, freshOnly: true);
      if (cached != null) {
        final bundled = await _loadBundled(sourceYear);
        final local = _selectLocalFallback(cached, bundled);
        if (!identical(local, cached)) {
          final remembered = _remember(sourceYear, local!);
          _refreshInBackground(sourceYear);
          return remembered;
        }
        return _remember(sourceYear, cached);
      }

      final local = await _loadLocalFallback(sourceYear);
      if (local != null) {
        final remembered = _remember(sourceYear, local);
        _refreshInBackground(sourceYear);
        return remembered;
      }
    } else {
      final refresh = _refreshInFlight[sourceYear];
      if (refresh != null) {
        await refresh;
        final refreshed = _memory[sourceYear];
        if (refreshed?.sourceType == PublicHolidaySourceType.remote) {
          return refreshed!;
        }
      }
    }

    final remote = await _loadRemote(sourceYear);
    if (remote != null) return _remember(sourceYear, remote);

    final local = await _loadLocalFallback(sourceYear);
    if (local != null) return _remember(sourceYear, local);

    final unavailable = PublicHolidayYear(
      sourceYear: sourceYear,
      papers: const [],
      days: const [],
      status: PublicHolidayYearStatus.unavailable,
      sourceType: PublicHolidaySourceType.unavailable,
    );
    return _remember(sourceYear, unavailable);
  }

  Future<PublicHolidayYear?> _loadLocalFallback(int sourceYear) async {
    final local = await Future.wait<PublicHolidayYear?>([
      _loadCached(sourceYear, freshOnly: false),
      _loadBundled(sourceYear),
    ]);
    return _selectLocalFallback(local[0], local[1]);
  }

  PublicHolidayYear? _selectLocalFallback(
    PublicHolidayYear? staleCache,
    PublicHolidayYear? bundled,
  ) {
    if (staleCache == null) return bundled;
    if (bundled == null) return staleCache;

    // A previous app may have cached an empty placeholder before the current
    // bundle published an arrangement. More generally, compare the cache's
    // fetch time with the bundle snapshot timestamp so a newer cached response
    // is not replaced by an older APK snapshot.
    if (bundled.status == PublicHolidayYearStatus.available &&
        (staleCache.status == PublicHolidayYearStatus.empty ||
            staleCache.fetchedAt == null ||
            staleCache.fetchedAt!.toUtc().isBefore(bundledSnapshotAt))) {
      return bundled;
    }
    return staleCache;
  }

  void _refreshInBackground(int sourceYear) {
    if (_refreshInFlight.containsKey(sourceYear)) return;
    final refresh = _refreshRemoteInBackground(sourceYear);
    _refreshInFlight[sourceYear] = refresh;
    unawaited(
      refresh.whenComplete(() {
        if (identical(_refreshInFlight[sourceYear], refresh)) {
          _refreshInFlight.remove(sourceYear);
        }
      }),
    );
  }

  Future<void> _refreshRemoteInBackground(int sourceYear) async {
    try {
      final remote = await _loadRemote(sourceYear);
      if (remote != null) _remember(sourceYear, remote);
    } catch (_) {
      // Background refresh must never replace usable local data with an error.
    }
  }

  Future<PublicHolidayYear?> _loadRemote(int sourceYear) async {
    for (final uri in [primaryUri(sourceYear), fallbackUri(sourceYear)]) {
      try {
        final body = await _loadRemoteText(uri);
        final fetchedAt = clock().toUtc();
        final parsed = PublicHolidayParser.parse(
          body,
          expectedSourceYear: sourceYear,
          sourceType: PublicHolidaySourceType.remote,
          sourceUrl: uri.toString(),
          fetchedAt: fetchedAt,
        );
        await _saveCache(sourceYear, uri, body, fetchedAt);
        return parsed;
      } catch (_) {
        // A parse failure is also isolated to this endpoint so the CDN can be
        // tried before falling back to local data.
      }
    }
    return null;
  }

  Future<String> _loadRemoteText(Uri uri) async {
    final override = _remoteLoaderOverride;
    if (override != null) return override(uri);
    final response = await _httpClient.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PublicHttpException(
        '公共节假日服务返回异常状态。',
        statusCode: response.statusCode,
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<PublicHolidayYear?> _loadBundled(int sourceYear) async {
    try {
      return PublicHolidayParser.parse(
        await loadAsset('$assetDirectory/$sourceYear.json'),
        expectedSourceYear: sourceYear,
        sourceType: PublicHolidaySourceType.bundled,
      );
    } catch (_) {
      return null;
    }
  }

  Future<PublicHolidayYear?> _loadCached(
    int sourceYear, {
    required bool freshOnly,
  }) async {
    try {
      final store = await preferences();
      final candidates = <PublicHolidayYear>[];
      for (final uri in [primaryUri(sourceYear), fallbackUri(sourceYear)]) {
        final raw = store.getString(_cacheKey(sourceYear, uri));
        if (raw == null) continue;
        final candidate = _decodeCache(sourceYear, uri, raw);
        if (candidate == null) continue;
        if (freshOnly && !_isFresh(candidate)) continue;
        candidates.add(candidate);
      }
      if (candidates.isEmpty) return null;
      candidates.sort((left, right) {
        final leftTime =
            left.fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightTime =
            right.fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
      });
      return candidates.first;
    } catch (_) {
      return null;
    }
  }

  PublicHolidayYear? _decodeCache(int sourceYear, Uri expectedUri, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['body'] is! String) return null;
      if (decoded['url'] != expectedUri.toString() ||
          decoded['fetchedAt'] is! String) {
        return null;
      }
      final fetchedAt = DateTime.tryParse(decoded['fetchedAt'] as String);
      if (fetchedAt == null) return null;
      return PublicHolidayParser.parse(
        decoded['body'] as String,
        expectedSourceYear: sourceYear,
        sourceType: PublicHolidaySourceType.cached,
        sourceUrl: expectedUri.toString(),
        fetchedAt: fetchedAt.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(
    int sourceYear,
    Uri uri,
    String body,
    DateTime fetchedAt,
  ) async {
    try {
      final store = await preferences();
      await store.setString(
        _cacheKey(sourceYear, uri),
        jsonEncode(<String, Object>{
          'url': uri.toString(),
          'fetchedAt': fetchedAt.toUtc().toIso8601String(),
          'body': body,
        }),
      );
    } catch (_) {
      // Caching is optional; a valid response is still usable in memory.
    }
  }

  String _cacheKey(int sourceYear, Uri uri) {
    final variant =
        uri.host == 'raw.githubusercontent.com' ? 'raw' : 'jsdelivr';
    return '$cachePrefix.$sourceYear.$variant';
  }

  bool _isFresh(PublicHolidayYear value) {
    final fetchedAt = value.fetchedAt;
    if (fetchedAt == null) return false;
    final age = clock().toUtc().difference(fetchedAt.toUtc());
    return age >= Duration.zero && age < cacheLifetime;
  }

  PublicHolidayYear _remember(int sourceYear, PublicHolidayYear value) {
    final previous = _memory[sourceYear];
    _memory[sourceYear] = value;
    if (!_closed &&
        value.sourceType == PublicHolidaySourceType.remote &&
        !identical(previous, value)) {
      revision.value++;
    }
    return value;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    revision.dispose();
    if (_ownsHttpClient) _httpClient.close();
  }
}

class PublicHolidayCapability
    implements PublicHolidayProvider, PublicHolidayRevisionSource {
  final PublicHolidayRepository repository;
  final int maxConcurrent;

  PublicHolidayCapability({
    PublicHolidayRepository? repository,
    this.maxConcurrent = 3,
  }) : repository = repository ?? PublicHolidayRepository() {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent');
    }
  }

  @override
  ValueListenable<int> get revision => repository.revision;

  @override
  Future<PublicHolidaySnapshot> loadRange(
    DateTime startDate,
    DateTime endDate, {
    bool force = false,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (start.isAfter(end)) {
      throw ArgumentError.value(endDate, 'endDate', '不能早于 startDate');
    }

    final sourceYears = _sourceYears(start, end);
    final loaded = List<PublicHolidayYear?>.filled(sourceYears.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= sourceYears.length) return;
        try {
          loaded[index] = await repository.loadYear(
            sourceYears[index],
            force: force,
          );
        } catch (_) {
          loaded[index] = _unavailable(sourceYears[index]);
        }
      }
    }

    final workerCount =
        sourceYears.length < maxConcurrent ? sourceYears.length : maxConcurrent;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);

    final years = [
      for (var index = 0; index < loaded.length; index++)
        loaded[index] ?? _unavailable(sourceYears[index]),
    ];
    final merged = _mergeDays(years, start, end);
    final fetchedTimes = [
      for (final year in years)
        if (year.fetchedAt != null) year.fetchedAt!,
    ];
    fetchedTimes.sort();

    return PublicHolidaySnapshot(
      startDate: start,
      endDate: end,
      days: merged,
      years: years,
      origin: _origin(years),
      latestFetchedAt: fetchedTimes.isEmpty ? null : fetchedTimes.last,
    );
  }

  static List<int> _sourceYears(DateTime start, DateTime end) {
    final years = <int>{};
    for (var year = start.year; year <= end.year; year++) {
      years.add(year);
      final decemberStart = DateTime(year, 12, 1);
      final decemberEnd = DateTime(year, 12, 31);
      if (!end.isBefore(decemberStart) && !start.isAfter(decemberEnd)) {
        years.add(year + 1);
      }
    }
    return years.toList()..sort();
  }

  static List<PublicHolidayDay> _mergeDays(
    List<PublicHolidayYear> years,
    DateTime start,
    DateTime end,
  ) {
    final byDateAndName = <String, PublicHolidayDay>{};
    for (final year in years) {
      for (final day in year.days) {
        if (day.date.isBefore(start) || day.date.isAfter(end)) continue;
        final key =
            '${day.date.year}-${day.date.month}-${day.date.day}|${day.name}';
        final current = byDateAndName[key];
        if (current == null || day.sourceYear > current.sourceYear) {
          byDateAndName[key] = day;
        }
      }
    }
    final result = byDateAndName.values.toList();
    result.sort((left, right) {
      final date = left.date.compareTo(right.date);
      if (date != 0) return date;
      final name = left.name.compareTo(right.name);
      if (name != 0) return name;
      return left.isOffDay == right.isOffDay
          ? 0
          : left.isOffDay
          ? -1
          : 1;
    });
    return result;
  }

  static PublicHolidayDataOrigin _origin(List<PublicHolidayYear> years) {
    final sourceTypes = {
      for (final year in years)
        if (year.sourceType != PublicHolidaySourceType.unavailable)
          year.sourceType,
    };
    if (sourceTypes.isEmpty) return PublicHolidayDataOrigin.unavailable;
    if (sourceTypes.length > 1) return PublicHolidayDataOrigin.mixed;
    return switch (sourceTypes.single) {
      PublicHolidaySourceType.remote => PublicHolidayDataOrigin.remote,
      PublicHolidaySourceType.cached => PublicHolidayDataOrigin.cached,
      PublicHolidaySourceType.bundled => PublicHolidayDataOrigin.bundled,
      PublicHolidaySourceType.unavailable =>
        PublicHolidayDataOrigin.unavailable,
    };
  }

  static PublicHolidayYear _unavailable(int sourceYear) => PublicHolidayYear(
    sourceYear: sourceYear,
    papers: const [],
    days: const [],
    status: PublicHolidayYearStatus.unavailable,
    sourceType: PublicHolidaySourceType.unavailable,
  );

  void close() => repository.close();
}
