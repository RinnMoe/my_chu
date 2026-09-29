import "dart:convert";
import "dart:math" as math;

import "package:crypto/crypto.dart";
import "package:mapbox_maps_flutter/mapbox_maps_flutter.dart";

import "../../campus_places/campus_places.dart";
import "../map_engine.dart";
import "mapbox_map_config.dart";

enum MapboxOfflineCacheStatus { unavailable, missing, partial, ready }

class MapboxOfflineRegionBudget {
  final int minZoom;
  final int maxZoom;
  final int estimatedTileCount;

  const MapboxOfflineRegionBudget({
    required this.minZoom,
    required this.maxZoom,
    required this.estimatedTileCount,
  });
}

/// Validates untrusted campus viewport data before it reaches Mapbox's native
/// offline loader. This keeps a malformed release from turning into an
/// unbounded tile download while leaving the online map available.
class MapboxOfflineCachePolicy {
  static const double maxLongitudeSpanDegrees = 0.25;
  static const double maxLatitudeSpanDegrees = 0.25;
  static const double maxAreaSquareKilometers = 100;
  static const int maxEstimatedTileCount = 50000;
  static const int maxSupportedZoom = 19;
  static const int defaultMinZoom = 12;
  static const int defaultMaxZoom = 19;

  const MapboxOfflineCachePolicy._();

  static MapboxOfflineRegionBudget? forCampus(CampusEntry campus) {
    final bounds = campus.bounds;
    if (bounds == null || !bounds.isValidWgs84) return null;
    if (bounds.longitudeSpan > maxLongitudeSpanDegrees ||
        bounds.latitudeSpan > maxLatitudeSpanDegrees) {
      return null;
    }

    final meanLatitude = (bounds.south + bounds.north) * 0.5;
    final area =
        bounds.longitudeSpan *
        111.32 *
        math.cos(meanLatitude * math.pi / 180) *
        bounds.latitudeSpan *
        110.54;
    if (!area.isFinite || area > maxAreaSquareKilometers) return null;

    final minZoom = _zoom(campus.minZoom, defaultMinZoom);
    final maxZoom = _zoom(campus.maxZoom, defaultMaxZoom);
    if (minZoom == null || maxZoom == null || minZoom > maxZoom) return null;

    final estimated = estimateTileCount(
      bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    if (estimated > maxEstimatedTileCount) return null;
    return MapboxOfflineRegionBudget(
      minZoom: minZoom,
      maxZoom: maxZoom,
      estimatedTileCount: estimated,
    );
  }

  static int? _zoom(double? value, int fallback) {
    final raw = value ?? fallback.toDouble();
    if (!raw.isFinite) return null;
    final rounded = raw.round();
    if (rounded < 0 || rounded > maxSupportedZoom) return null;
    return rounded;
  }

  static int estimateTileCount(
    CampusBounds bounds, {
    required int minZoom,
    required int maxZoom,
  }) {
    if (!bounds.isValidWgs84 || minZoom < 0 || maxZoom < minZoom) return 0;
    var total = 0;
    for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
      final tiles = 1 << zoom;
      final minX = _tileX(bounds.west, tiles);
      final maxX = _tileX(bounds.east, tiles);
      final minY = _tileY(bounds.north, tiles);
      final maxY = _tileY(bounds.south, tiles);
      final count = (maxX - minX + 1) * (maxY - minY + 1);
      total += count;
      if (total > maxEstimatedTileCount) return total;
    }
    return total;
  }

  static int _tileX(double longitude, int tiles) {
    final normalized = ((longitude + 180) / 360 * tiles).floor();
    return normalized.clamp(0, tiles - 1);
  }

  static int _tileY(double latitude, int tiles) {
    final clamped = latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final radians = clamped * math.pi / 180;
    final projected =
        (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2;
    return (projected * tiles).floor().clamp(0, tiles - 1);
  }
}

class MapboxOfflineTileRegionInfo {
  final int requiredResourceCount;
  final int completedResourceCount;
  final int completedResourceSize;
  final int? expires;

  const MapboxOfflineTileRegionInfo({
    required this.requiredResourceCount,
    required this.completedResourceCount,
    required this.completedResourceSize,
    this.expires,
  });

  bool get isComplete =>
      requiredResourceCount > 0 &&
      completedResourceCount >= requiredResourceCount;
}

class MapboxOfflineCacheInfo {
  final String campusId;
  final String regionId;
  final String styleUri;
  final String cacheVersion;
  final MapboxOfflineCacheStatus status;
  final bool stylePackReady;
  final MapboxOfflineTileRegionInfo? tileRegion;

  const MapboxOfflineCacheInfo({
    required this.campusId,
    required this.regionId,
    required this.styleUri,
    required this.cacheVersion,
    required this.status,
    required this.stylePackReady,
    this.tileRegion,
  });

  bool get isUsable =>
      stylePackReady &&
      tileRegion != null &&
      tileRegion!.completedResourceCount > 0;
}

/// Narrow adapter around the Mapbox native offline APIs.
///
/// Keeping this interface separate lets unit tests exercise cache identity,
/// status and refresh policy without instantiating a native MapView.
abstract interface class MapboxOfflineCacheStore {
  Future<bool> hasCompleteStylePack(String styleUri);

  Future<List<String>> tileRegionIds();

  Future<MapboxOfflineTileRegionInfo?> tileRegion(String regionId);

  Future<void> loadStylePack(String styleUri, Map<String, Object?> metadata);

  Future<void> loadTileRegion(
    String regionId, {
    required Map<String, Object?> geometry,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
    required Map<String, Object?> metadata,
  });

  Future<void> removeTileRegion(String regionId);
}

typedef MapboxOfflineCacheStoreFactory =
    Future<MapboxOfflineCacheStore> Function();

class _OfflinePreparation {
  final int generation;
  final Future<MapboxOfflineCacheInfo> future;

  const _OfflinePreparation({required this.generation, required this.future});
}

/// Account-independent, versioned offline cache for the four campus regions.
///
/// The cache owns only Mapbox style packs and hosted tiles. MyCHU semantic
/// places remain in the semantic release repository and are not mixed into a
/// Mapbox tile region.
class MapboxOfflineCache {
  /// Increment only when MyCHU changes the visual offline-cache schema/strategy.
  static const String defaultCacheVersion = "semantic-map-v2";

  final MapboxMapConfig config;
  final String cacheVersion;
  final MapboxOfflineCacheStoreFactory _storeFactory;
  final Map<String, _OfflinePreparation> _inFlight = {};
  final Set<String> _preparedIdentities = {};
  final Map<String, String> _latestIdentityByCampus = {};
  final Map<String, int> _campusGeneration = {};
  MapboxOfflineCacheStore? _store;

  MapboxOfflineCache({
    this.config = const MapboxMapConfig(),
    this.cacheVersion = defaultCacheVersion,
    MapboxOfflineCacheStoreFactory? storeFactory,
  }) : _storeFactory = storeFactory ?? _defaultStoreFactory;

  String cacheIdentity(CampusEntry campus) => _regionId(campus);

  Future<MapboxOfflineCacheInfo> getStatus(CampusEntry campus) async {
    if (!config.isConfigured) {
      throw const CampusMapConfigurationException(
        "Mapbox access token is not configured.",
      );
    }
    final styleUri = config.resolvedStyleUri;
    final regionId = _regionId(campus);
    if (MapboxOfflineCachePolicy.forCampus(campus) == null) {
      return MapboxOfflineCacheInfo(
        campusId: campus.campusId,
        regionId: regionId,
        styleUri: styleUri,
        cacheVersion: cacheVersion,
        status: MapboxOfflineCacheStatus.unavailable,
        stylePackReady: false,
      );
    }

    final store = await _getStore();
    final styleReady = await store.hasCompleteStylePack(styleUri);
    final region = await store.tileRegion(regionId);
    return _info(
      campus: campus,
      regionId: regionId,
      styleUri: styleUri,
      styleReady: styleReady,
      region: region,
    );
  }

  /// Ensures a style pack and one bounded campus tile region exist.
  ///
  /// An existing region is refreshed at most once per cache instance. The
  /// native SDK updates missing/expired resources for the same identity rather
  /// than downloading the whole region again. If refresh fails but an older
  /// usable region exists, its status is returned so weak networks can still
  /// display the cached map.
  Future<MapboxOfflineCacheInfo> prepareCampus(CampusEntry campus) async {
    final identity = cacheIdentity(campus);
    final generation = _activateVisualIdentity(campus.campusId, identity);
    final active = _inFlight[identity];
    if (active != null && active.generation == generation) {
      return active.future;
    }

    final future = _prepareCampus(campus, identity, generation);
    final preparation = _OfflinePreparation(
      generation: generation,
      future: future,
    );
    _inFlight[identity] = preparation;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[identity], preparation)) {
        _inFlight.remove(identity);
      }
    }
  }

  int _activateVisualIdentity(String campusId, String identity) {
    if (_latestIdentityByCampus[campusId] == identity) {
      return _campusGeneration[campusId] ?? 0;
    }
    final generation = (_campusGeneration[campusId] ?? 0) + 1;
    _campusGeneration[campusId] = generation;
    _latestIdentityByCampus[campusId] = identity;
    _preparedIdentities.removeWhere(
      (prepared) => _belongsToCampusRegion(prepared, campusId),
    );
    return generation;
  }

  int _invalidateCampus(String campusId) {
    final generation = (_campusGeneration[campusId] ?? 0) + 1;
    _campusGeneration[campusId] = generation;
    _latestIdentityByCampus.remove(campusId);
    _preparedIdentities.removeWhere(
      (prepared) => _belongsToCampusRegion(prepared, campusId),
    );
    return generation;
  }

  Future<void> clearCampus(String campusId) async {
    final generation = _invalidateCampus(campusId);
    if (!config.isConfigured) return;
    final store = await _getStore();
    final ids = await store.tileRegionIds();
    if (!_isCurrentClear(campusId, generation)) return;
    for (final id in ids) {
      if (!_isCurrentClear(campusId, generation)) return;
      if (_belongsToCampusRegion(id, campusId)) {
        await store.removeTileRegion(id);
      }
    }
  }

  Future<MapboxOfflineCacheInfo> _prepareCampus(
    CampusEntry campus,
    String identity,
    int generation,
  ) async {
    final before = await getStatus(campus);
    if (!_isCurrentVisualPreparation(campus.campusId, identity, generation)) {
      return before;
    }
    if (before.status == MapboxOfflineCacheStatus.unavailable) return before;

    final budget = MapboxOfflineCachePolicy.forCampus(campus);
    if (budget == null) return before;

    final store = await _getStore();
    if (!_isCurrentVisualPreparation(campus.campusId, identity, generation)) {
      return before;
    }
    try {
      if (_preparedIdentities.contains(identity)) {
        await _pruneCampusRegions(
          store,
          campus.campusId,
          identity,
          generation: generation,
        );
        if (!_isCurrentVisualPreparation(
          campus.campusId,
          identity,
          generation,
        )) {
          return await _returnStalePreparation(store, campus, identity);
        }
        return before;
      }

      final metadata = <String, Object?>{
        "mychuCacheVersion": cacheVersion,
        "campusId": campus.campusId,
        "styleUri": config.resolvedStyleUri,
      };
      // Mapbox refreshes only missing/expired style resources for the same
      // style URI; this is the online update path after cold start.
      await store.loadStylePack(config.resolvedStyleUri, metadata);
      if (!_isCurrentVisualPreparation(campus.campusId, identity, generation)) {
        return before;
      }
      await store.loadTileRegion(
        identity,
        geometry: _geometry(campus.bounds!),
        styleUri: config.resolvedStyleUri,
        minZoom: budget.minZoom,
        maxZoom: budget.maxZoom,
        metadata: metadata,
      );
      if (!_isCurrentVisualPreparation(campus.campusId, identity, generation)) {
        return await _returnStalePreparation(store, campus, identity);
      }
      await _pruneCampusRegions(
        store,
        campus.campusId,
        identity,
        generation: generation,
      );
      if (!_isCurrentVisualPreparation(campus.campusId, identity, generation)) {
        return await _returnStalePreparation(store, campus, identity);
      }
      _preparedIdentities.add(identity);
    } catch (_) {
      if (!_isCurrentVisualPreparation(campus.campusId, identity, generation)) {
        return _returnStalePreparation(store, campus, identity);
      }
      if (before.isUsable) return before;
      rethrow;
    }
    return getStatus(campus);
  }

  Future<MapboxOfflineCacheInfo> _returnStalePreparation(
    MapboxOfflineCacheStore store,
    CampusEntry campus,
    String identity,
  ) async {
    await _cleanupStaleRegionIfSafe(store, campus.campusId, identity);
    return getStatus(campus);
  }

  Future<void> _cleanupStaleRegionIfSafe(
    MapboxOfflineCacheStore store,
    String campusId,
    String identity,
  ) async {
    if (_latestIdentityByCampus[campusId] == identity) return;
    try {
      final ids = await store.tileRegionIds();
      if (_latestIdentityByCampus[campusId] == identity) return;
      if (ids.contains(identity) &&
          _belongsToCampusRegion(identity, campusId)) {
        await store.removeTileRegion(identity);
      }
      _preparedIdentities.remove(identity);
    } catch (_) {
      // Stale cache cleanup is best-effort; the current identity will prune it.
    }
  }

  Future<MapboxOfflineCacheStore> _getStore() async {
    final current = _store;
    if (current != null) return current;
    final created = await _storeFactory();
    _store = created;
    return created;
  }

  MapboxOfflineCacheInfo _info({
    required CampusEntry campus,
    required String regionId,
    required String styleUri,
    required bool styleReady,
    required MapboxOfflineTileRegionInfo? region,
  }) {
    final status =
        !styleReady && region == null
            ? MapboxOfflineCacheStatus.missing
            : styleReady && region?.isComplete == true
            ? MapboxOfflineCacheStatus.ready
            : MapboxOfflineCacheStatus.partial;
    return MapboxOfflineCacheInfo(
      campusId: campus.campusId,
      regionId: regionId,
      styleUri: styleUri,
      cacheVersion: cacheVersion,
      status: status,
      stylePackReady: styleReady,
      tileRegion: region,
    );
  }

  String _regionId(CampusEntry campus) {
    final campusHash = sha256
        .convert(utf8.encode(campus.campusId))
        .toString()
        .substring(0, 12);
    final budget = MapboxOfflineCachePolicy.forCampus(campus);
    final material = jsonEncode({
      "campusId": campus.campusId,
      "cacheVersion": cacheVersion,
      "styleUri": config.resolvedStyleUri,
      "bounds":
          campus.bounds == null
              ? null
              : {
                "west": campus.bounds!.west,
                "south": campus.bounds!.south,
                "east": campus.bounds!.east,
                "north": campus.bounds!.north,
              },
      "minZoom": budget?.minZoom ?? campus.minZoom,
      "maxZoom": budget?.maxZoom ?? campus.maxZoom,
    });
    final identityHash = sha256
        .convert(utf8.encode(material))
        .toString()
        .substring(0, 32);
    return "mychu-v2-$campusHash-$identityHash";
  }

  Future<void> _pruneCampusRegions(
    MapboxOfflineCacheStore store,
    String campusId,
    String currentIdentity, {
    required int generation,
  }) async {
    if (!_isCurrentVisualPreparation(campusId, currentIdentity, generation)) {
      return;
    }
    final ids = await store.tileRegionIds();
    if (!_isCurrentVisualPreparation(campusId, currentIdentity, generation)) {
      return;
    }
    for (final id in ids) {
      if (!_isCurrentVisualPreparation(campusId, currentIdentity, generation)) {
        return;
      }
      if (_belongsToCampusRegion(id, campusId) && id != currentIdentity) {
        await store.removeTileRegion(id);
      }
    }
  }

  bool _belongsToCampusRegion(String regionId, String campusId) {
    final campusHash = sha256
        .convert(utf8.encode(campusId))
        .toString()
        .substring(0, 12);
    final safeCampus = campusId.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
    return regionId.startsWith("mychu-v2-$campusHash-") ||
        regionId.startsWith("mychu-$safeCampus-");
  }

  bool _isCurrentVisualPreparation(
    String campusId,
    String identity,
    int generation,
  ) =>
      _campusGeneration[campusId] == generation &&
      _latestIdentityByCampus[campusId] == identity;

  bool _isCurrentClear(String campusId, int generation) =>
      _campusGeneration[campusId] == generation &&
      !_latestIdentityByCampus.containsKey(campusId);

  Map<String, Object?> _geometry(CampusBounds bounds) => {
    "type": "Polygon",
    "coordinates": [
      [
        [bounds.west, bounds.south],
        [bounds.east, bounds.south],
        [bounds.east, bounds.north],
        [bounds.west, bounds.north],
        [bounds.west, bounds.south],
      ],
    ],
  };

  static Future<MapboxOfflineCacheStore> _defaultStoreFactory() async {
    final offlineManager = await OfflineManager.create();
    final tileStore = await TileStore.createDefault();
    return _MapboxSdkOfflineCacheStore(offlineManager, tileStore);
  }
}

class _MapboxSdkOfflineCacheStore implements MapboxOfflineCacheStore {
  final OfflineManager offlineManager;
  final TileStore tileStore;

  const _MapboxSdkOfflineCacheStore(this.offlineManager, this.tileStore);

  @override
  Future<bool> hasCompleteStylePack(String styleUri) async {
    final packs = await offlineManager.allStylePacks();
    for (final pack in packs) {
      if (pack.styleURI == styleUri &&
          pack.requiredResourceCount > 0 &&
          pack.completedResourceCount >= pack.requiredResourceCount) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<String>> tileRegionIds() async {
    final regions = await tileStore.allTileRegions();
    return regions.map((region) => region.id).toList(growable: false);
  }

  @override
  Future<MapboxOfflineTileRegionInfo?> tileRegion(String regionId) async {
    final regions = await tileStore.allTileRegions();
    for (final region in regions) {
      if (region.id == regionId) {
        return MapboxOfflineTileRegionInfo(
          requiredResourceCount: region.requiredResourceCount,
          completedResourceCount: region.completedResourceCount,
          completedResourceSize: region.completedResourceSize,
          expires: region.expires,
        );
      }
    }
    return null;
  }

  @override
  Future<void> loadStylePack(
    String styleUri,
    Map<String, Object?> metadata,
  ) async {
    await offlineManager.loadStylePack(
      styleUri,
      StylePackLoadOptions(metadata: metadata, acceptExpired: false),
      null,
    );
  }

  @override
  Future<void> loadTileRegion(
    String regionId, {
    required Map<String, Object?> geometry,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
    required Map<String, Object?> metadata,
  }) async {
    await tileStore.loadTileRegion(
      regionId,
      TileRegionLoadOptions(
        geometry: geometry,
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: styleUri,
            minZoom: minZoom,
            maxZoom: maxZoom,
          ),
        ],
        metadata: metadata,
        acceptExpired: false,
        networkRestriction: NetworkRestriction.NONE,
      ),
      null,
    );
  }

  @override
  Future<void> removeTileRegion(String regionId) async {
    await tileStore.removeRegion(regionId);
  }
}
