import "package:flutter/material.dart";

import "../campus_places/campus_places.dart";
import "mapbox/mapbox_campus_map_page.dart";

export "campus_map_models.dart";
export "../campus_places/campus_places.dart"
    show UnifiedPlaceRequest, PlaceResolutionResult, PlaceCandidate;

/// Shared campus-map capability facade (SDK independent).
///
/// Business modules only depend on MyCHU place-domain types. The concrete
/// renderer is currently the official Mapbox Maps SDK for Flutter.
class CampusMapCapability {
  MapboxCampusMapPage createPage({
    Key? key,
    bool asRootTab = false,
    UnifiedPlaceRequest? destination,
  }) => MapboxCampusMapPage(
    key: key,
    asRootTab: asRootTab,
    destination: destination,
  );

  Future<void> openRequest(BuildContext context, UnifiedPlaceRequest request) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapboxCampusMapPage(destination: request),
      ),
    );
  }
}

final campusMapCapability = CampusMapCapability();
