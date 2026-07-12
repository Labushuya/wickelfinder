import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../community/presentation/add_place_screen.dart';
import '../../community/presentation/community_providers.dart';
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
  final BBox _currentBBox = BBox.berlin;
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(mergedPlacesProvider(_currentBBox));
    final hasBackend = ref.watch(communityRepositoryProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wickelfinder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: () => ref.invalidate(mergedPlacesProvider(_currentBBox)),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
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
          // OSM-Lizenz-Attribution (ODbL-Pflicht). SafeArea(top:false) laesst die
          // Tiles randlos unter der Statusbar, schiebt aber die interaktive
          // Attribution ueber die System-NavBar (Gesten-Pill/3-Button-Nav).
          // SafeArea liest das reale Inset -> keine Magic Numbers.
          const SafeArea(
            top: false,
            minimum: EdgeInsets.only(right: 8, bottom: 8),
            child: RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap-Mitwirkende'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: hasBackend
          ? FloatingActionButton.extended(
              onPressed: placesAsync.isLoading ? null : _addPlace,
              icon: placesAsync.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_location_alt),
              label: const Text('Platz melden'),
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
            child: _PinIcon(source: place.source),
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

  Future<void> _addPlace() async {
    final center = _mapCenter();
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddPlaceScreen(initialCenter: center)),
    );
    if (added ?? false) {
      ref.invalidate(mergedPlacesProvider(_currentBBox));
    }
  }

  /// Ausgangspunkt fuer den Hinzufuegen-Screen: aktuelle Karten-Mitte,
  /// faellt auf den Initialwert zurueck.
  LatLng _mapCenter() {
    try {
      return _mapController.camera.center;
    } catch (_) {
      return _initialCenter;
    }
  }
}

class _PinIcon extends StatelessWidget {
  const _PinIcon({required this.source});

  final PlaceSource source;

  @override
  Widget build(BuildContext context) {
    // Community-Plaetze in Akzentfarbe, OSM-Plaetze in Primaerfarbe.
    final color = source == PlaceSource.community
        ? AppColors.accent
        : AppColors.primary;
    return Icon(Icons.location_on, color: color, size: 40);
  }
}
