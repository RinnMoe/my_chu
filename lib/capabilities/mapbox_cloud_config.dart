/// Shared Mapbox Cloud identity used by both the renderer and semantic data
/// transport. This file deliberately has no dependency on mapbox_maps_flutter
/// so SDK-independent capabilities can use the hosted semantic catalog without
/// importing renderer types.
class MapboxCloudConfig {
  static const String accessToken =
      "pk.eyJ1IjoicmlubnJpbm4iLCJhIjoiY210MTRybmtsMGE1NDJ5cXR1dWZ4cDF0aCJ9.QLf13ylMhUBqcKy-oKWA5w";
  static const String styleUri =
      "mapbox://styles/rinnrinn/cmt1es0c1001k01sk4p2g2uf4";

  /// Namespaced root Style metadata entry containing MyCHU semantic data.
  static const String semanticMetadataKey = "mychu:semantic";

  const MapboxCloudConfig._();

  static MapboxStyleIdentity get styleIdentity {
    final uri = Uri.tryParse(styleUri);
    if (uri == null ||
        uri.scheme != "mapbox" ||
        uri.host != "styles" ||
        uri.pathSegments.length < 2) {
      throw const FormatException("Invalid Mapbox Studio style URI");
    }
    return MapboxStyleIdentity(
      username: uri.pathSegments[0],
      styleId: uri.pathSegments[1],
    );
  }

  static Uri publishedStyleApiUri({String? token}) {
    final identity = styleIdentity;
    final resolvedToken = (token ?? accessToken).trim();
    if (!resolvedToken.startsWith("pk.")) {
      throw const FormatException("Mapbox semantic reads require a public pk.* token");
    }
    return Uri.https(
      "api.mapbox.com",
      "/styles/v1/${identity.username}/${identity.styleId}",
      <String, String>{"access_token": resolvedToken},
    );
  }
}

class MapboxStyleIdentity {
  final String username;
  final String styleId;

  const MapboxStyleIdentity({required this.username, required this.styleId});
}
