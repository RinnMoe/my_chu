import "../campus_places/campus_places_models.dart";
import "external_navigation.dart";

/// 从地点解析结果选择外部导航目标。
///
/// 规则：
/// - 建筑/分区/教室只允许使用人工核验入口，绝不回退到 displayCoordinate、几何中心或 (0,0)。
/// - 普通独立 POI 只有在自身 Point 坐标有效且数据核验后才可作为导航目标。
class NavigationTargetResolver {
  const NavigationTargetResolver();

  ExternalNavigationTarget? resolve({
    required CampusPlace? place,
    required CampusClassroom? classroom,
    CampusPlacesData? places,
  }) {
    if (place == null) return null;

    if (classroom != null) {
      final entrance = _verifiedEntranceForSelection(place, classroom, places);
      if (entrance == null) return null;
      return ExternalNavigationTarget(
        name: place.name,
        wgs84: NavCoordinate(
          longitude: entrance.coordinate.longitude,
          latitude: entrance.coordinate.latitude,
        ),
        entranceLabel: entrance.label.isEmpty ? null : entrance.label,
      );
    }

    if (!_isEligibleOwner(place)) return null;
    if (_requiresVerifiedEntrance(place)) {
      final entrance =
          _verifiedEntrance(place) ?? _verifiedParentEntrance(place, places);
      if (entrance == null) return null;
      return ExternalNavigationTarget(
        name: place.name,
        wgs84: NavCoordinate(
          longitude: entrance.coordinate.longitude,
          latitude: entrance.coordinate.latitude,
        ),
        entranceLabel: entrance.label.isEmpty ? null : entrance.label,
      );
    }

    final point = _ownPoint(place);
    if (point == null) return null;
    return ExternalNavigationTarget(
      name: place.name,
      wgs84: NavCoordinate(
        longitude: point.longitude,
        latitude: point.latitude,
      ),
    );
  }

  bool _requiresVerifiedEntrance(CampusPlace place) =>
      place.layerCategory == "building" ||
      place.type == CampusPlaceType.building ||
      place.type == CampusPlaceType.buildingZone;

  CampusEntrance? _verifiedEntranceForSelection(
    CampusPlace place,
    CampusClassroom? classroom,
    CampusPlacesData? places,
  ) {
    final candidates = <CampusPlace?>[];
    if (places != null && classroom != null) {
      if (classroom.zonePlaceId != null) {
        candidates.add(places.placeById(classroom.zonePlaceId!));
      }
      if (classroom.buildingPlaceId.isNotEmpty) {
        candidates.add(places.placeById(classroom.buildingPlaceId));
      }
    }
    candidates.add(place);
    if (places != null && place.parentPlaceId != null) {
      candidates.add(places.placeById(place.parentPlaceId!));
    }
    for (final candidate in candidates) {
      if (candidate == null) continue;
      final entrance = _verifiedEntrance(candidate);
      if (entrance != null) return entrance;
    }
    return null;
  }

  CampusEntrance? _verifiedParentEntrance(
    CampusPlace place,
    CampusPlacesData? places,
  ) {
    final parentId = place.parentPlaceId;
    if (parentId == null || places == null) return null;
    final parent = places.placeById(parentId);
    return parent == null ? null : _verifiedEntrance(parent);
  }

  bool _isEligibleOwner(CampusPlace place) =>
      place.navEnabled && place.verified;

  CampusEntrance? _verifiedEntrance(CampusPlace place) {
    if (!_isEligibleOwner(place)) return null;
    for (final entrance in place.entrances) {
      if (!entrance.verified) continue;
      if (!entrance.coordinate.isValidWgs84 || entrance.coordinate.isOrigin) {
        continue;
      }
      return entrance;
    }
    return null;
  }

  CampusCoordinate? _ownPoint(CampusPlace place) {
    if (place.geometryType != CampusGeometryType.point) return null;
    if (place.geometry.isEmpty) return null;
    final point = place.geometry.first;
    if (!point.isValidWgs84 || point.isOrigin) return null;
    return point;
  }
}
