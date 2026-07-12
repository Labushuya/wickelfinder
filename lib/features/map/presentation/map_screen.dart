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
import '../../updater/presentation/update_sheet.dart';
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

  /// Zuletzt erfolgreich geladene Plaetze. Bleiben sichtbar, waehrend eine neue
  /// BBox laedt -> kein Leerflackern der Pins beim Wischen.
  List<ChangingPlace> _lastPlaces = const [];

  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: einmalig versuchen, auf den Standort zu zentrieren.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goToMyLocation(initial: true);
      // Stiller Auto-Update-Check (zeigt nur bei neuer Version ein Sheet).
      UpdateSheet.checkAndShow(context, ref);
    });
  }

  @override
  void dispose() {
    _bboxDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(mergedPlacesProvider(_bbox));
    // Neue Daten uebernehmen, sobald da; sonst die letzten behalten.
    final places = placesAsync.valueOrNull;
    if (places != null) _lastPlaces = places;
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
              MarkerLayer(markers: _buildMarkers()),
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
          // Suchleiste oben, im sicheren Bereich, mit Menue.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: AddressSearchBar(onSelected: _goTo)),
                  const SizedBox(width: 8),
                  Material(
                    elevation: 3,
                    shape: const CircleBorder(),
                    color: Theme.of(context).colorScheme.surface,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) {
                        if (v == 'update') {
                          UpdateSheet.checkAndShow(context, ref, manual: true);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'update',
                          child: Row(
                            children: [
                              Icon(Icons.system_update, size: 20),
                              SizedBox(width: 10),
                              Text('Nach Updates suchen'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    // Laenger warten -> nicht bei jedem Mini-Wisch neu laden.
    _bboxDebounce = Timer(const Duration(milliseconds: 900), _updateBBox);
  }

  void _updateBBox() {
    if (!mounted) return;
    final bounds = _mapController.camera.visibleBounds;
    final next = BBox(
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
    );
    // Nur neu laden, wenn sich der Ausschnitt WESENTLICH verschoben hat
    // (Mitte > ~30% der aktuellen Breite/Hoehe). Verhindert Dauer-Reloads.
    if (!_bboxChangedSignificantly(_bbox, next)) return;
    setState(() => _bbox = next);
  }

  static bool _bboxChangedSignificantly(BBox a, BBox b) {
    final latSpan = (a.north - a.south).abs();
    final lonSpan = (a.east - a.west).abs();
    final centerLatMoved = (((a.north + a.south) - (b.north + b.south)) / 2)
        .abs();
    final centerLonMoved = (((a.east + a.west) - (b.east + b.west)) / 2).abs();
    final zoomChanged =
        ((latSpan - (b.north - b.south).abs()).abs() > latSpan * 0.25);
    return zoomChanged ||
        centerLatMoved > latSpan * 0.3 ||
        centerLonMoved > lonSpan * 0.3;
  }

  void _goTo(LatLng target, {double zoom = 15}) {
    // move() loest onPositionChanged aus -> _scheduleBBoxUpdate laedt nach.
    _mapController.move(target, zoom);
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

  List<Marker> _buildMarkers() {
    return [
      for (final place in _lastPlaces)
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
