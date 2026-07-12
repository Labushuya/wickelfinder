import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/changing_place.dart';
import 'map_providers.dart';
import 'place_detail_sheet.dart';

/// Hauptscreen: Karte mit Wickelplatz-Pins.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _initialCenter = LatLng(52.515, 13.395); // Berlin
  BBox _currentBBox = BBox.berlin;

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(placesProvider(_currentBBox));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wickelfinder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: () => ref.invalidate(placesProvider(_currentBBox)),
          ),
        ],
      ),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: _initialCenter,
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'de.wickelfinder.app',
          ),
          MarkerLayer(markers: _buildMarkers(placesAsync)),
          // OSM-Lizenz-Attribution (ODbL-Pflicht)
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap-Mitwirkende'),
            ],
          ),
        ],
      ),
      floatingActionButton:
          placesAsync.isLoading
              ? const FloatingActionButton(
                onPressed: null,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
              : null,
    );
  }

  List<Marker> _buildMarkers(AsyncValue<List<ChangingPlace>> async) {
    final places = async.valueOrNull ?? const [];
    return [
      for (final place in places)
        Marker(
          point: place.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showDetail(place),
            child: const _PinIcon(),
          ),
        ),
    ];
  }

  void _showDetail(ChangingPlace place) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => PlaceDetailSheet(place: place),
      ),
    );
  }
}

class _PinIcon extends StatelessWidget {
  const _PinIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.location_on, color: AppColors.primary, size: 40);
  }
}
