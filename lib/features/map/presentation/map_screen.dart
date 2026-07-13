import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/location_service.dart';
import '../../../core/map/tile_cache.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/settings_screen.dart';
import '../../../core/theme/theme_controller.dart';
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

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  static const _initialCenter = LatLng(52.515, 13.395); // Berlin (Fallback)
  final MapController _mapController = MapController();

  BBox _bbox = BBox.berlin;
  Timer? _bboxDebounce;
  double _zoom = 14;
  AnimationController? _moveAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybeShowThemeFirstRun(context, ref);
      UpdateSheet.checkAndShow(context, ref);
    });
  }

  @override
  void dispose() {
    _bboxDebounce?.cancel();
    _moveAnim?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // OSM-Ergebnisse (Netz, pro BBox) additiv in den Akkumulator einspeisen.
    ref.listen<AsyncValue<List<ChangingPlace>>>(placesProvider(_bbox), (
      _,
      next,
    ) {
      final data = next.valueOrNull;
      if (data != null) {
        ref.read(accumulatedPlacesProvider.notifier).addOsm(data);
      }
    });

    // Community-Pins (Cache/offline) UNABHAENGIG vom OSM-Call einspeisen.
    ref.listen<AsyncValue<List<ChangingPlace>>>(communityPlacesProvider, (
      _,
      next,
    ) {
      final data = next.valueOrNull;
      if (data != null) {
        ref.read(accumulatedPlacesProvider.notifier).reconcileCommunity(data);
      }
    });

    // Loading-Banner NUR fuer den echten OSM-Netzcall (togglet nicht dauernd).
    final loading = ref.watch(placesProvider(_bbox)).isLoading;
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
                final z = pos.zoom ?? _zoom;
                // Nur bei echtem Zoom-Stufen-Wechsel rebuilden (Cluster<->Einzel);
                // sonst kein setState -> kein Rebuild-Takt.
                if (z.floor() != _zoom.floor()) {
                  setState(() => _zoom = z);
                } else {
                  _zoom = z;
                }
                _scheduleBBoxUpdate();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.wickelfinder.app',
                tileProvider: TileCache.instanceOrNull()?.provider(),
              ),
              MarkerLayer(markers: _buildMarkers(accumulated.all)),
            ],
          ),

          // Suchleiste oben: volle Breite, 3-Punkt-Menue integriert,
          // daneben ein kleiner Hell-/Dunkel-Schnellumschalter.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AddressSearchBar(
                      onSelected: _goTo,
                      trailing: _buildMenu(hasBackend),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ThemeToggleButton(),
                ],
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
      // Buttons rechts, uebereinander, ueber der Attribution + Nav-Bar-Inset.
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: 18 + MediaQuery.viewPaddingOf(context).bottom,
        ),
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
        } else if (v == 'settings') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 20),
              SizedBox(width: 10),
              Text('Einstellungen'),
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
    // Nur bei WESENTLICHER Verschiebung neu laden -> genau ein Reload, kein Takt.
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

  /// Sanfte animierte Kamerafahrt zum Ziel (statt instantem Sprung).
  void _goTo(LatLng target, {double zoom = 15}) {
    final camera = _mapController.camera;
    final startCenter = camera.center;
    final startZoom = camera.zoom;

    _moveAnim?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _moveAnim = controller;
    final curved = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
    final latT = Tween<double>(
      begin: startCenter.latitude,
      end: target.latitude,
    );
    final lonT = Tween<double>(
      begin: startCenter.longitude,
      end: target.longitude,
    );
    final zoomT = Tween<double>(begin: startZoom, end: zoom);

    controller.addListener(() {
      _mapController.move(
        LatLng(latT.evaluate(curved), lonT.evaluate(curved)),
        zoomT.evaluate(curved),
      );
    });
    controller.forward();
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
    // Akkumulierte Pins bleiben sichtbar (kein Wegwerfen beim Wegscrollen).
    // Ab mittlerem Zoom einzeln; bei kleinem Zoom in ein Grid clustern, damit
    // die Karte bei sehr vielen Pins nicht ueberladen wird.
    if (_zoom >= 13) {
      return [for (final p in places) _pinMarker(p)];
    }
    return _clusterMarkers(places);
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
        // Cluster sitzt am Durchschnittspunkt, zoomt aber beim Tippen auf die
        // Bounding-Box ALLER enthaltenen Pins (nicht auf den Durchschnitt) —
        // so landet man nie "im Nirgendwo".
        final lat =
            group.map((p) => p.location.latitude).reduce((a, b) => a + b) /
            group.length;
        final lon =
            group.map((p) => p.location.longitude).reduce((a, b) => a + b) /
            group.length;
        markers.add(_clusterMarker(LatLng(lat, lon), group));
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

  Marker _clusterMarker(LatLng point, List<ChangingPlace> members) => Marker(
    point: point,
    width: 44,
    height: 44,
    child: GestureDetector(
      onTap: () => _zoomToCluster(members),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          members.length > 99 ? '99+' : '${members.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );

  /// Zoomt sanft auf die Bounding-Box aller Pins eines Clusters.
  void _zoomToCluster(List<ChangingPlace> members) {
    if (members.isEmpty) return;
    if (members.length == 1) {
      _mapController.move(members.first.location, math.min(_zoom + 3, 17));
      return;
    }
    var south = members.first.location.latitude;
    var north = south;
    var west = members.first.location.longitude;
    var east = west;
    for (final m in members) {
      south = math.min(south, m.location.latitude);
      north = math.max(north, m.location.latitude);
      west = math.min(west, m.location.longitude);
      east = math.max(east, m.location.longitude);
    }
    final bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(64),
        maxZoom: 17,
      ),
    );
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
    if (added ?? false) await refreshCommunityDataFromWidget(ref);
  }
}

/// Kleiner Hell-/Dunkel-Schnellumschalter (Sonne/Mond) neben der Suchleiste.
class _ThemeToggleButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    // Kompakter als die Suchleiste, oben ausgerichtet (Row = start).
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 50,
        height: 50,
        child: IconButton(
          iconSize: 24,
          padding: EdgeInsets.zero,
          tooltip: isDark ? 'Heller Modus' : 'Dunkler Modus',
          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          color: Theme.of(context).colorScheme.primary,
          // Aktuelle Anzeige-Helligkeit uebergeben -> erster Tap wirkt sofort.
          onPressed: () => ref.read(themeModeProvider.notifier).toggle(isDark),
        ),
      ),
    );
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
