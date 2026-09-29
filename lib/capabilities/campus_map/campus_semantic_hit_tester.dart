import "dart:math" as math;

import "../campus_places/campus_places.dart";

/// Resolves a geographic tap against MyCHU's stable semantic place data.
///
/// This class intentionally knows nothing about a map renderer. In
/// particular, Mapbox feature IDs never enter the place identity path.
class CampusSemanticHitTester {
  static final Expando<_SemanticPlaceIndex> _indexCache =
      Expando<_SemanticPlaceIndex>();

  const CampusSemanticHitTester();

  CampusPlace? hitTest(CampusPlacesData data, CampusCoordinate point) {
    CampusPlace? best;
    var bestScore = double.infinity;

    for (final candidate in _indexFor(data).candidatesAt(point)) {
      if (!_couldHit(candidate, point)) continue;
      final place = candidate.place;
      if (!place.enabled) continue;
      final score = _score(place, point);
      if (score < bestScore) {
        bestScore = score;
        best = place;
      }
    }
    return bestScore.isFinite ? best : null;
  }

  static _SemanticPlaceIndex _indexFor(CampusPlacesData data) {
    final cached = _indexCache[data];
    if (cached != null) return cached;

    final bounds = <_SemanticPlaceBounds>[];
    for (final place in data.places) {
      if (!place.enabled) continue;
      final coordinates = <CampusCoordinate>[
        ...place.geometry,
        if (place.displayCoordinate != null) place.displayCoordinate!,
      ];
      if (coordinates.isEmpty) continue;
      var west = coordinates.first.longitude;
      var east = west;
      var south = coordinates.first.latitude;
      var north = south;
      for (final coordinate in coordinates.skip(1)) {
        if (coordinate.longitude < west) west = coordinate.longitude;
        if (coordinate.longitude > east) east = coordinate.longitude;
        if (coordinate.latitude < south) south = coordinate.latitude;
        if (coordinate.latitude > north) north = coordinate.latitude;
      }
      bounds.add(
        _SemanticPlaceBounds(
          place: place,
          west: west,
          east: east,
          south: south,
          north: north,
        ),
      );
    }
    final result = _SemanticPlaceIndex.build(bounds);
    _indexCache[data] = result;
    return result;
  }

  bool _couldHit(_SemanticPlaceBounds candidate, CampusCoordinate point) {
    // The largest semantic tolerance is 32 metres. A 0.001° margin is a
    // deliberately conservative pre-filter, after which the exact geometry
    // calculation remains authoritative.
    const margin = 0.001;
    return point.longitude >= candidate.west - margin &&
        point.longitude <= candidate.east + margin &&
        point.latitude >= candidate.south - margin &&
        point.latitude <= candidate.north + margin;
  }

  CampusPlaceId? hitTestPlaceId({
    required String campusId,
    required CampusPlacesData data,
    required CampusCoordinate point,
  }) {
    final place = hitTest(data, point);
    return place == null
        ? null
        : CampusPlaceId(campusId: campusId, placeId: place.placeId);
  }

  double _score(CampusPlace place, CampusCoordinate point) {
    switch (place.geometryType) {
      case CampusGeometryType.polygon:
        if (place.geometry.length >= 3 &&
            _pointInPolygon(point, place.geometry)) {
          return 0;
        }
        final center = place.displayCoordinate;
        if (center == null) return double.infinity;
        final distance = _distanceMeters(point, center);
        return distance <= 28 ? distance : double.infinity;
      case CampusGeometryType.lineString:
        if (place.geometry.length < 2) return double.infinity;
        final distance = _distanceToLineMeters(point, place.geometry);
        return distance <= 24 ? distance + 0.5 : double.infinity;
      case CampusGeometryType.point:
        final center =
            place.displayCoordinate ??
            (place.geometry.isNotEmpty ? place.geometry.first : null);
        if (center == null) return double.infinity;
        final distance = _distanceMeters(point, center);
        return distance <= 32 ? distance + 1 : double.infinity;
    }
  }

  bool _pointInPolygon(CampusCoordinate point, List<CampusCoordinate> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses =
          ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      ((b.latitude - a.latitude).abs() < 1e-12
                          ? 1e-12
                          : b.latitude - a.latitude) +
                  a.longitude);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  double _distanceToLineMeters(
    CampusCoordinate point,
    List<CampusCoordinate> line,
  ) {
    var best = double.infinity;
    for (var i = 1; i < line.length; i++) {
      final distance = _distanceToSegmentMeters(point, line[i - 1], line[i]);
      if (distance < best) best = distance;
    }
    return best;
  }

  double _distanceToSegmentMeters(
    CampusCoordinate point,
    CampusCoordinate a,
    CampusCoordinate b,
  ) {
    final originLat = point.latitude * math.pi / 180;
    const metersPerLat = 110540.0;
    final metersPerLon = 111320.0 * math.cos(originLat);

    double x(CampusCoordinate coordinate) =>
        (coordinate.longitude - point.longitude) * metersPerLon;
    double y(CampusCoordinate coordinate) =>
        (coordinate.latitude - point.latitude) * metersPerLat;

    final ax = x(a);
    final ay = y(a);
    final bx = x(b);
    final by = y(b);
    final dx = bx - ax;
    final dy = by - ay;
    final denominator = dx * dx + dy * dy;
    if (denominator <= 1e-9) return math.sqrt(ax * ax + ay * ay);
    final t = (-(ax * dx + ay * dy) / denominator).clamp(0.0, 1.0);
    final projectedX = ax + dx * t;
    final projectedY = ay + dy * t;
    return math.sqrt(projectedX * projectedX + projectedY * projectedY);
  }

  double _distanceMeters(CampusCoordinate a, CampusCoordinate b) {
    final meanLat = (a.latitude + b.latitude) * 0.5 * math.pi / 180;
    final dx = (a.longitude - b.longitude) * 111320.0 * math.cos(meanLat);
    final dy = (a.latitude - b.latitude) * 110540.0;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _SemanticPlaceBounds {
  final CampusPlace place;
  final double west;
  final double east;
  final double south;
  final double north;

  const _SemanticPlaceBounds({
    required this.place,
    required this.west,
    required this.east,
    required this.south,
    required this.north,
  });
}

class _SemanticPlaceIndex {
  static const double _cellSizeDegrees = 0.005;
  static const double _queryMarginDegrees = 0.001;
  static const int _maxIndexedCellsPerPlace = 256;

  final Map<String, List<_SemanticPlaceBounds>> _cells;
  final List<_SemanticPlaceBounds> _wideArea;

  const _SemanticPlaceIndex(this._cells, this._wideArea);

  factory _SemanticPlaceIndex.build(List<_SemanticPlaceBounds> bounds) {
    final cells = <String, List<_SemanticPlaceBounds>>{};
    final wideArea = <_SemanticPlaceBounds>[];
    for (final bound in bounds) {
      final minX = _cell(bound.west - _queryMarginDegrees);
      final maxX = _cell(bound.east + _queryMarginDegrees);
      final minY = _cell(bound.south - _queryMarginDegrees);
      final maxY = _cell(bound.north + _queryMarginDegrees);
      final cellCount = (maxX - minX + 1) * (maxY - minY + 1);
      if (cellCount > _maxIndexedCellsPerPlace) {
        wideArea.add(bound);
        continue;
      }
      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          cells.putIfAbsent(_key(x, y), () => []).add(bound);
        }
      }
    }
    return _SemanticPlaceIndex(
      cells.map(
        (key, value) =>
            MapEntry(key, List<_SemanticPlaceBounds>.unmodifiable(value)),
      ),
      List<_SemanticPlaceBounds>.unmodifiable(wideArea),
    );
  }

  Iterable<_SemanticPlaceBounds> candidatesAt(CampusCoordinate point) sync* {
    final key = _key(_cell(point.longitude), _cell(point.latitude));
    yield* _cells[key] ?? const <_SemanticPlaceBounds>[];
    yield* _wideArea;
  }

  static int _cell(double coordinate) =>
      (coordinate / _cellSizeDegrees).floor();

  static String _key(int x, int y) => "$x:$y";
}
