import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/changing_place.dart';
import '../domain/map_filter.dart';
import '../domain/venue_context.dart';

/// Aktiver Karten-Filter (Sitzungszustand, keine Persistenz).
class MapFilterController extends Notifier<MapFilter> {
  @override
  MapFilter build() => const MapFilter();

  void toggleVenue(VenueContext v) {
    final next = {...state.venues};
    next.contains(v) ? next.remove(v) : next.add(v);
    state = state.copyWith(venues: next);
  }

  void toggleSource(PlaceSource s) {
    final next = {...state.sources};
    next.contains(s) ? next.remove(s) : next.add(s);
    state = state.copyWith(sources: next);
  }

  void setBarrierefrei(bool v) => state = state.copyWith(onlyBarrierefrei: v);
  void setFree(bool v) => state = state.copyWith(onlyFree: v);
  void setAccessible(bool v) => state = state.copyWith(onlyAccessible: v);
  void setOwnRoom(bool v) => state = state.copyWith(onlyOwnRoom: v);
  void setOpenNow(bool v) => state = state.copyWith(onlyOpenNow: v);

  void clear() => state = const MapFilter();

  /// Uebernimmt einen kompletten (im Sheet lokal bearbeiteten) Filter-Entwurf.
  void apply(MapFilter f) => state = f;
}

final mapFilterProvider = NotifierProvider<MapFilterController, MapFilter>(
  MapFilterController.new,
);
