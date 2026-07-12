import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../community/presentation/add_place_screen.dart';
import '../../community/presentation/community_providers.dart';
import '../../search/presentation/address_search_bar.dart';
import '../domain/changing_place.dart';
import 'map_providers.dart';
import 'place_detail_sheet.dart';

/// Hauptscreen: Karte mit Wickelplatz-Pins, Adresssuche und Standort.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _initialCenter = LatLng(52.515, 13.395); // Berlin (Fallback)
  final MapController _mapController = MapController();

  /// Aktuell sichtbare Bounding-Box; treibt das Laden der Plaetze.
  BBox _bbox = BBox.berlin;
  Timer? _bboxDebounce;

  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: einmalig versuchen, auf den Standort zu zentrieren.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _goToMyLocation(initial: true),
    );
  }

  @override
  void dispose() {
    _bboxDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(mergedPlacesProvider(_bbox));
    final hasBackend = ref.watch(communityRepositoryProvider) != null;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 14,
              onMapReady: _updateBBox,
              onPositionChanged: (_, __) => _scheduleBBoxUpdate(),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.wickelfinder.app',
              ),
              MarkerLayer(markers: _buildMarkers(placesAsync)),
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
          // Suchleiste oben, im sicheren Bereich.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AddressSearchBar(onSelected: _goTo),
            ),
          ),
          if (placesAsync.isLoading)
            const Positioned(
              top: 90,
              left: 0,
              right: 0,
              child: Center(child: _LoadingChip()),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'loc',
            tooltip: 'Mein Standort',
            onPressed: () => _goToMyLocation(),
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 12),
          if (hasBackend)
            FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: _addPlace,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Platz melden'),
            ),
        ],
      ),
    );
  }

  // --- Karten-/BBox-Logik ---------------------------------------------------

  void _scheduleBBoxUpdate() {
    _bboxDebounce?.cancel();
    _bboxDebounce = Timer(const Duration(milliseconds: 600), _updateBBox);
  }

  void _updateBBox() {
    final bounds = _mapController.camera.visibleBounds;
    final next = BBox(
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
    );
    if (mounted) setState(() => _bbox = next);
  }

  void _goTo(LatLng target, {double zoom = 15}) {
    _mapController.move(target, zoom);
    _updateBBox();
  }

  Future<void> _goToMyLocation({bool initial = false}) async {
    final pos = await LocationService.current();
    if (pos == null) {
      if (!initial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standort nicht verfügbar.')),
        );
      }
      return;
    }
    if (mounted) _goTo(pos, zoom: 15);
  }

  // --- Marker / Detail / Hinzufuegen ---------------------------------------

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
    final center = _mapController.camera.center;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddPlaceScreen(initialCenter: center)),
    );
    if (added ?? false) ref.invalidate(mergedPlacesProvider(_bbox));
  }
}

class _PinIcon extends StatelessWidget {
  const _PinIcon({required this.source});

  final PlaceSource source;

  @override
  Widget build(BuildContext context) {
    final color = source == PlaceSource.community
        ? AppColors.accent
        : AppColors.primary;
    return Icon(Icons.location_on, color: color, size: 40);
  }
}

class _LoadingChip extends StatelessWidget {
  const _LoadingChip();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Lädt …', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
