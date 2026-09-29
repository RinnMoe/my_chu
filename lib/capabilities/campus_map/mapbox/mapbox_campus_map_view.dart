import "dart:async";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:mapbox_maps_flutter/mapbox_maps_flutter.dart";

import "mapbox_map_engine.dart";

/// Lightweight Mapbox map host.
///
/// The basemap/style is fully managed by Mapbox. MyCHU only bridges lifecycle
/// and interaction events into [MapboxMapEngine].
class MapboxCampusMapView extends StatelessWidget {
  final MapboxMapEngine engine;

  const MapboxCampusMapView({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final instanceToken = engine.mapInstanceToken;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = ui.Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        engine.updateViewportSize(viewportSize, instanceToken: instanceToken);
        return MapWidget(
          key: ValueKey<String>("mychu-mapbox:$instanceToken"),
          styleUri: engine.styleUri,
          onMapCreated:
              (controller) => engine.attach(
                controller,
                instanceToken: instanceToken,
                viewportSize: viewportSize,
              ),
          onStyleLoadedListener:
              (_) => unawaited(engine.handleStyleLoaded(instanceToken)),
          onMapIdleListener:
              (_) =>
                  unawaited(engine.handleMapIdle(instanceToken: instanceToken)),
          onMapLoadErrorListener:
              (event) =>
                  unawaited(engine.handleMapLoadError(event, instanceToken)),
        );
      },
    );
  }
}
