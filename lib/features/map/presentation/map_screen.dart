import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../community/presentation/accumulated_places.dart';
import '../../community/presentation/add_place_screen.dart';
import '../../community/presentation/community_providers.dart';
import '../../community/presentation/my_places_screen.dart';
import '../../search/presentation/address_search_bar.dart';
import '../../updater/presentation/update_sheet.dart';
import '../domain/changing_place.dart';
import 'hold_to_label_fab.dart';
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

  BBox _bbox = BBox.berlin;
  Timer? _bboxDebounce;
  double _zoom = 14;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    // Ladeergebnisse in den Akkumulator einspeisen (ergaenzt/rekonziliert),
    // ohne die bereits gezeigten Pins zu ersetzen.
    ref.listen<AsyncValue<List<ChangingPlace>>>(mergedPlacesProvider(_bbox), (
      _,
      next,
    ) {
      final data = next.valueOrNull;
      if (data == null) return;
      final notifier = ref.read(accumulatedPlacesProvider.notifier);
      notifier.addOsm(data.where((p) => p.source == PlaceSource.osm).toList());
      notifier.reconcileCommunity(
        data.where((p) => p.source == PlaceSource.community).toList(),
      );
    });

    final loading = ref.watch(mergedPlacesProvider(_bbox)).isLoading;
    final accumulated = ref.watch(accumulatedPlacesProvider);
    final hasBackend = ref.watch(communityRepositoryProvider) != null;
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _zoom,
              minZoom: 3,
              maxZoom: 19,
              onMapReady: _onMapReady,
              onPositionChanged: (pos, _) {
                _zoom = pos.zoom ?? _zoom;
                _scheduleBBoxUpdate();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.wickelfinder.app',
              ),
              MarkerLayer(markers: _buildMarkers(accumulated.all)),
            ],
          ),

          // Suchleiste oben: volle Breite, 3-Punkt-Menue integriert.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AddressSearchBar(
                onSelected: _goTo,
                trailing: _buildMenu(hasBackend),
              ),
            ),
          ),

          if (loading)
            const Positioned(
              top: 92,
              left: 0,
              right: 0,
              child: Center(child: _LoadingChip()),
            ),

          // Persistente, dezente OSM-Attribution fix am unteren Rand.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 3),
                alignment: Alignment.center,
                color: theme.colorScheme.surface.withValues(alpha: 0.7),
                child: Text(
                  '© OpenStreetMap-Mitwirkende',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // Buttons rechts, uebereinander, ueber der Attribution.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HoldToLabelFab(
              heroTag: 'loc',
              icon: Icons.my_location,
              label: 'Mein Standort',
              onPressed: () => _goToMyLocation(),
            ),
            if (hasBackend) ...[
              const SizedBox(height: 12),
              HoldToLabelFab(
                heroTag: 'add',
                icon: Icons.add_location_alt,
                label: 'Platz melden',
                onPressed: _addPlace,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(bool hasBackend) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        if (v == 'update') {
          UpdateSheet.checkAndShow(context, ref, manual: true);
        } else if (v == 'my_pins') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const MyPlacesScreen()));
        }
      },
      itemBuilder: (_) => [
        if (hasBackend)
          const PopupMenuItem(
            value: 'my_pins',
            child: Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 20),
                SizedBox(width: 10),
                Text('Meine Pins'),
              ],
            ),
          ),
        const PopupMenuItem(
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
    );
  }

  // --- Karten-/BBox-Logik ---------------------------------------------------

  void _onMapReady() {
    _updateBBox();
    _goToMyLocation(initial: true);
  }

  void _scheduleBBoxUpdate() {
    _bboxDebounce?.cancel();
    _bboxDebounce = Timer(const Duration(milliseconds: 800), _updateBBox);
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
    if (!_bboxChangedSignificantly(_bbox, next)) {
      setState(() {}); // Cluster nach Zoom/Pan neu rendern, ohne neu zu laden.
      return;
    }
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

  // --- Marker: Viewport-Culling + Grid-Clustering ---------------------------

  List<Marker> _buildMarkers(List<ChangingPlace> places) {
    LatLngBounds? bounds;
    try {
      bounds = _mapController.camera.visibleBounds;
    } catch (_) {
      bounds = null;
    }

    // Nur Pins im (leicht erweiterten) Viewport rendern.
    final visible = <ChangingPlace>[];
    for (final p in places) {
      if (bounds == null || _inBoundsPadded(bounds, p.location)) {
        visible.add(p);
      }
    }

    // Ab mittlerem Zoom einzeln zeigen; bei kleinem Zoom in ein Grid clustern.
    if (_zoom >= 13) {
      return [for (final p in visible) _pinMarker(p)];
    }
    return _clusterMarkers(visible);
  }

  bool _inBoundsPadded(LatLngBounds b, LatLng p) {
    final latPad = (b.north - b.south).abs() * 0.2;
    final lonPad = (b.east - b.west).abs() * 0.2;
    return p.latitude >= b.south - latPad &&
        p.latitude <= b.north + latPad &&
        p.longitude >= b.west - lonPad &&
        p.longitude <= b.east + lonPad;
  }

  /// Einfaches Grid-Clustering: Pins in Zellen bucketen, pro Zelle ein
  /// Cluster-Marker (bei >1) bzw. der Einzel-Pin.
  List<Marker> _clusterMarkers(List<ChangingPlace> places) {
    // Zellgroesse abhaengig vom Zoom (kleinerer Zoom -> groebere Zellen).
    final cell = 360 / math.pow(2, _zoom) * 2.5;
    final buckets = <String, List<ChangingPlace>>{};
    for (final p in places) {
      final key =
          '${(p.location.latitude / cell).floor()}:'
          '${(p.location.longitude / cell).floor()}';
      (buckets[key] ??= []).add(p);
    }

    final markers = <Marker>[];
    for (final group in buckets.values) {
      if (group.length == 1) {
        markers.add(_pinMarker(group.first));
      } else {
        // Cluster-Mittelpunkt = Durchschnitt.
        final lat =
            group.map((p) => p.location.latitude).reduce((a, b) => a + b) /
            group.length;
        final lon =
            group.map((p) => p.location.longitude).reduce((a, b) => a + b) /
            group.length;
        markers.add(_clusterMarker(LatLng(lat, lon), group.length));
      }
    }
    return markers;
  }

  Marker _pinMarker(ChangingPlace place) => Marker(
    point: place.location,
    width: 44,
    height: 44,
    child: GestureDetector(
      onTap: () => _showDetail(place),
      child: _PinIcon(source: place.source),
    ),
  );

  Marker _clusterMarker(LatLng point, int count) => Marker(
    point: point,
    width: 44,
    height: 44,
    child: GestureDetector(
      onTap: () => _goTo(point, zoom: math.min(_zoom + 3, 17)),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );

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
