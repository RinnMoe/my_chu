import "campus_places_models.dart";
import "place_normalizer.dart";

/// Resolver 的单校区名称关键词索引。
class PlaceSearchIndex {
  final CampusPlacesData _data;
  final PlaceInputNormalizer _normalizer;

  PlaceSearchIndex({
    required CampusPlacesData data,
    PlaceInputNormalizer? normalizer,
  }) : _data = data,
       _normalizer = normalizer ?? const PlaceInputNormalizer();

  /// [normalizedQuery] 为已标准化查询。
  List<CampusPlace> keywordMatches(String normalizedQuery, {int limit = 20}) {
    if (normalizedQuery.isEmpty) return const [];
    final hits = <CampusPlace>[];
    for (final place in _data.places) {
      if (!place.enabled || !place.searchable) continue;
      final normalizedName = _normalizer.normalize(place.name);
      if (normalizedName.contains(normalizedQuery) ||
          place.aliases.any(
            (alias) => _normalizer.normalize(alias).contains(normalizedQuery),
          )) {
        hits.add(place);
      }
    }
    return hits.length <= limit ? hits : hits.sublist(0, limit);
  }
}
