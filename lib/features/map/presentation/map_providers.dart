import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/overpass_repository.dart';
import '../domain/changing_place.dart';

/// Stellt das [OverpassRepository] bereit. In Tests überschreibbar.
final overpassRepositoryProvider = Provider<OverpassRepository>((ref) {
  final repo = OverpassRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Bounding-Box, für die Wickelplätze geladen werden sollen.
class BBox {
  const BBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// Default: Zentrum Berlin, ~5 km Kantenlänge – sinnvoller erster View.
  static const berlin = BBox(
    south: 52.49,
    west: 13.36,
    north: 52.54,
    east: 13.43,
  );

  /// Auf Raster gerundete + generoes erweiterte Box. Das Runden sorgt dafuer,
  /// dass kleine Kartenbewegungen denselben Provider-Key (== / hashCode) treffen
  /// -> kein Dauer-Reload; die Erweiterung laedt Pins knapp ausserhalb des
  /// Sichtbereichs mit, sodass am Rand nichts fehlt.
  factory BBox.snappedFrom({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    const grid = 0.02; // ~2 km Raster
    double floorTo(double v) => (v / grid).floor() * grid;
    double ceilTo(double v) => (v / grid).ceil() * grid;
    return BBox(
      south: floorTo(south) - grid,
      west: floorTo(west) - grid,
      north: ceilTo(north) + grid,
      east: ceilTo(east) + grid,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BBox &&
      other.south == south &&
      other.west == west &&
      other.north == north &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);
}

/// Lädt die Wickelplätze für die gegebene [BBox].
/// `family` erlaubt getrenntes Caching pro Kartenausschnitt.
final placesProvider = FutureProvider.family<List<ChangingPlace>, BBox>((
  ref,
  bbox,
) async {
  final repo = ref.watch(overpassRepositoryProvider);
  return repo.fetchInBoundingBox(
    south: bbox.south,
    west: bbox.west,
    north: bbox.north,
    east: bbox.east,
  );
});
