import "dart:async";

import "campus_places_models.dart";
import "campus_registry.dart";
import "map_release_repository.dart";
import "place_code_rule_overrides.dart";
import "place_resolver.dart";
import "place_search_index.dart";

/// 统一地点服务门面：加载校区注册表与各校区地点数据，提供地点解析。
///
/// 业务模块通过本门面解析地点，不接触地图 SDK 与资产路径。
class CampusPlacesService {
  final PlaceResolver resolver;
  final MapReleaseCoordinator releaseCoordinator;

  CampusRegistry? _registry;
  final Map<String, CampusPlacesData> _placesByCampus = {};
  final Map<String, PlaceSearchIndex> _searchIndexesByCampus = {};
  List<PlaceCodeRuleOverride> _codeOverrides = const [];
  MapReleaseSnapshot? _releaseSnapshot;

  CampusPlacesService({
    PlaceResolver? resolver,
    MapReleaseCoordinator? releaseCoordinator,
  }) : releaseCoordinator = releaseCoordinator ?? MapReleaseCoordinator.shared,
       resolver = resolver ?? const PlaceResolver();

  bool get isLoaded => _registry != null;

  CampusRegistry? get registry => _registry;

  /// The immutable semantic snapshot used by this service.
  MapReleaseSnapshot? get releaseSnapshot => _releaseSnapshot;

  List<CampusEntry> get campuses => _registry?.enabledCampuses ?? const [];

  CampusEntry? campusById(String id) => _registry?.byId(id);

  CampusPlacesData? placesFor(String campusId) => _placesByCampus[campusId];

  List<PlaceCodeRuleOverride> get codeOverrides => _codeOverrides;

  /// Loads the active remote/cached release or the coordinator's bundled
  /// fallback; a missing places file only removes that campus from the map.
  Future<void> load({bool refreshRelease = true}) async {
    _applySnapshot(await releaseCoordinator.loadForStartup());
    if (refreshRelease) {
      unawaited(releaseCoordinator.refresh().catchError((_) => false));
    }
  }

  void _applySnapshot(MapReleaseSnapshot snapshot) {
    _releaseSnapshot = snapshot;
    _registry = snapshot.registry;
    _placesByCampus
      ..clear()
      ..addAll(snapshot.placesByCampus);
    _codeOverrides = snapshot.codeRules.rules;
    _rebuildSearchIndexes();
  }

  Future<PlaceResolutionResult> resolve(
    UnifiedPlaceRequest request, {
    String? currentCampusId,
  }) async {
    if (_registry == null) await load();
    return resolver.resolve(
      request: request,
      registry: _registry!,
      placesByCampus: _placesByCampus,
      currentCampusId: currentCampusId,
      codeOverrides: _codeOverrides,
      searchIndexesByCampus: _searchIndexesByCampus,
    );
  }

  void _rebuildSearchIndexes() {
    _searchIndexesByCampus
      ..clear()
      ..addEntries(
        (_registry?.enabledCampuses ?? const <CampusEntry>[])
            .where((campus) {
              return _placesByCampus.containsKey(campus.campusId);
            })
            .map((campus) {
              return MapEntry(
                campus.campusId,
                PlaceSearchIndex(
                  data: _placesByCampus[campus.campusId]!,
                  normalizer: resolver.normalizer,
                ),
              );
            }),
      );
  }
}
