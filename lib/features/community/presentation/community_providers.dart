import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../../map/domain/changing_place.dart';
import '../../map/presentation/map_providers.dart';
import '../data/community_repository.dart';
import '../domain/place_merge.dart';
import '../domain/place_stats.dart';

/// Stellt das [CommunityRepository] bereit — aber nur, wenn Supabase
/// konfiguriert ist. Sonst null -> UI zeigt keine Community-Funktionen.
final communityRepositoryProvider = Provider<CommunityRepository?>((ref) {
  if (!SupabaseInit.isConfigured) return null;
  return CommunityRepository(SupabaseInit.client);
});

/// Laedt Aggregat-Statistik fuer EINEN place_ref. String-Key -> stabiles
/// Family-Caching und korrektes `ref.invalidate` (List-Keys vergleichen sich
/// nicht per Wert und wuerden bei jedem build neu erzeugt).
final statsProvider = FutureProvider.family<PlaceStats, String>((
  ref,
  placeRef,
) async {
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) return PlaceStats.empty(placeRef);
  final map = await repo.statsFor([placeRef]);
  return map[placeRef] ?? PlaceStats.empty(placeRef);
});

/// Merged OSM- + Community-Plaetze fuer die gegebene [BBox].
/// Ohne Backend faellt es auf reine OSM-Plaetze zurueck.
final mergedPlacesProvider = FutureProvider.family<List<ChangingPlace>, BBox>((
  ref,
  bbox,
) async {
  final osm = await ref.watch(placesProvider(bbox).future);
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) return osm;
  // Community-Plaetze laden; bei Fehler nicht die ganze Karte kippen.
  List<ChangingPlace> community;
  try {
    community = await repo.communityPlaces();
  } catch (_) {
    community = const [];
  }
  return mergePlaces(osm: osm, community: community);
});
