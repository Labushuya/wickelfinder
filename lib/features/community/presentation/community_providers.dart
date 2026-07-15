import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../../map/domain/changing_place.dart';
import '../data/community_cache.dart';
import '../data/community_repository.dart';
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

/// Community-Plaetze: SOFORT aus dem Disk-Cache (auch offline), dann EINMAL
/// Delta-Sync im Hintergrund. Der Sync schiebt das Ergebnis via `state =` nach
/// (KEIN invalidateSelf -> kein Reload-Loop, kein Loading-Toggle).
class CommunityPlacesNotifier extends AsyncNotifier<List<ChangingPlace>> {
  @override
  Future<List<ChangingPlace>> build() async {
    final cache = ref.watch(communityCacheProvider);
    if (cache == null) return const [];
    // Disposal-Guard: nach onDispose kein state= mehr setzen.
    var disposed = false;
    ref.onDispose(() => disposed = true);
    await cache.loadFromDisk();
    unawaited(
      cache.sync().then((changed) {
        if (changed && !disposed) state = AsyncData(cache.places);
      }),
    );
    return cache.places; // sofort verfuegbar (Disk / leer)
  }

  /// Nach Schreibaktionen: sync + State setzen (ohne Rebuild-Sturm).
  Future<void> refresh() async {
    final cache = ref.read(communityCacheProvider);
    if (cache == null) return;
    await cache.sync();
    state = AsyncData(cache.places);
  }
}

final communityPlacesProvider =
    AsyncNotifierProvider<CommunityPlacesNotifier, List<ChangingPlace>>(
      CommunityPlacesNotifier.new,
    );

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

/// Die EIGENE Bewertung fuer einen place_ref (null wenn noch nicht bewertet).
final myRatingProvider = FutureProvider.family<MyRating?, String>((
  ref,
  placeRef,
) async {
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) return null;
  return repo.myRating(placeRef);
});

/// Eigene Community-Plaetze fuer den "Meine Pins"-Screen (direkt vom Server,
/// da RLS-gefiltert auf die eigene Identitaet).
final myPlacesProvider = FutureProvider<List<ChangingPlace>>((ref) async {
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) return const [];
  return repo.myPlaces();
});

/// ALLE Community-Plaetze (nur Admin). Leere Liste ohne Adminrecht.
final adminAllPlacesProvider = FutureProvider<List<ChangingPlace>>((ref) async {
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) return const [];
  return repo.adminAllPlaces();
});

/// Nach einer Schreibaktion Cache + Ansichten aktualisieren (ohne Reload-Sturm).
Future<void> refreshCommunityData(Ref ref) async {
  await ref.read(communityPlacesProvider.notifier).refresh();
  ref.invalidate(myPlacesProvider);
}

Future<void> refreshCommunityDataFromWidget(WidgetRef ref) async {
  await ref.read(communityPlacesProvider.notifier).refresh();
  ref.invalidate(myPlacesProvider);
}
