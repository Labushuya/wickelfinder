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
}

/// Lädt die Wickelplätze für die gegebene [BBox].
/// `family` erlaubt getrenntes Caching pro Kartenausschnitt.
final placesProvider =
    FutureProvider.family<List<ChangingPlace>, BBox>((ref, bbox) async {
  final repo = ref.watch(overpassRepositoryProvider);
  return repo.fetchInBoundingBox(
    south: bbox.south,
    west: bbox.west,
    north: bbox.north,
    east: bbox.east,
  );
});
