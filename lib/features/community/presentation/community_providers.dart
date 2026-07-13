import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../../map/domain/changing_place.dart';
import '../../map/presentation/map_providers.dart';
import '../data/community_cache.dart';
import '../data/community_repository.dart';
import '../domain/place_merge.dart';
import '../domain/place_stats.dart';

/// Stellt das [CommunityRepository] bereit — aber nur, wenn Supabase
/// konfiguriert ist. Sonst null -> UI zeigt keine Community-Funktionen.
final communityRepositoryProvider = Provider<CommunityRepository?>((ref) {
  if (!SupabaseInit.isConfigured) return null;
  return CommunityRepository(SupabaseInit.client);
});

/// Persistenter Community-Cache (offline-faehig, Delta-Sync).
final communityCacheProvider = Provider<CommunityCache?>((ref) {
  if (!SupabaseInit.isConfigured) return null;
  return CommunityCache(SupabaseInit.client);
});

/// Liefert Community-Plaetze SOFORT aus dem Cache (auch offline) und stoesst im
/// Hintergrund einen Delta-Sync an. Nach dem Sync wird der Provider
/// invalidiert, sodass frische Daten ohne Karten-Wischen erscheinen.
final communityPlacesProvider = FutureProvider<List<ChangingPlace>>((
  ref,
) async {
  final cache = ref.watch(communityCacheProvider);
  if (cache == null) return const [];
  await cache.loadFromDisk();
  // Hintergrund-Delta-Sync; bei Aenderung Provider erneut ausspielen.
  unawaited(
    cache.sync().then((changed) {
      if (changed) ref.invalidateSelf();
    }),
  );
  return cache.places;
});

/// Laedt Aggregat-Statistik fuer EINEN place_ref.
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
/// Community kommt aus dem Cache (sofort + Delta-Sync), OSM per Overpass.
final mergedPlacesProvider = FutureProvider.family<List<ChangingPlace>, BBox>((
  ref,
  bbox,
) async {
  final osm = await ref.watch(placesProvider(bbox).future);
  final community = ref.watch(communityPlacesProvider).valueOrNull ?? const [];
  return mergePlaces(osm: osm, community: community);
});

/// Eigene Community-Plaetze fuer den "Meine Pins"-Screen (direkt vom Server,
/// da RLS-gefiltert auf die eigene Identitaet).
final myPlacesProvider = FutureProvider<List<ChangingPlace>>((ref) async {
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) return const [];
  return repo.myPlaces();
});

/// Nach einer Schreibaktion (Platz anlegen/aendern/loeschen) aufrufen:
/// synchronisiert den Cache sofort und aktualisiert alle abhaengigen Ansichten,
/// sodass die Aenderung ohne Karten-Wischen sichtbar wird.
Future<void> refreshCommunityData(Ref ref) async {
  final cache = ref.read(communityCacheProvider);
  await cache?.sync();
  ref.invalidate(communityPlacesProvider);
  ref.invalidate(myPlacesProvider);
}

/// WidgetRef-Variante fuer den Aufruf aus der UI.
Future<void> refreshCommunityDataFromWidget(WidgetRef ref) async {
  final cache = ref.read(communityCacheProvider);
  await cache?.sync();
  ref.invalidate(communityPlacesProvider);
  ref.invalidate(myPlacesProvider);
}
