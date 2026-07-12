import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../domain/place_stats.dart';
import 'community_repository.dart';

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
