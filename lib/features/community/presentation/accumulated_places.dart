import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/changing_place.dart';
import '../data/osm_cache.dart';

/// Akkumulierte Pins, per placeRef dedupliziert. Die UI liest NUR hieraus,
/// damit Pins bei Kartenbewegung/Zoom nicht verschwinden (sie werden ergaenzt,
/// nicht ersetzt).
class AccumulatedPlaces {
  const AccumulatedPlaces(this.byRef);
  final Map<String, ChangingPlace> byRef;

  List<ChangingPlace> get all => byRef.values.toList(growable: false);
  int get length => byRef.length;
}

/// Haelt alle je geladenen Pins im Speicher und merged neue Ergebnisse hinein.
///
/// - OSM-Pins werden ergaenzt (nie entfernt, solange Speicher-Deckel nicht
///   erreicht) und persistent gecacht -> beim Start sofort sichtbar.
/// - Community-Pins werden per "Scope-Reconciliation" ersetzt.
class AccumulatedPlacesNotifier extends Notifier<AccumulatedPlaces> {
  /// Weicher Speicher-Deckel: aeltester OSM-Ueberschuss wird verworfen.
  static const _maxOsmPins = 4000;

  // Einfuege-Reihenfolge der OSM-Refs (fuer LRU-artiges Kappen).
  final List<String> _osmOrder = [];
  final OsmCache _osmCache = OsmCache();

  @override
  AccumulatedPlaces build() {
    // Gecachte OSM-Pins beim Start sofort einspeisen (nicht auf Netz warten).
    _preloadOsm();
    return const AccumulatedPlaces({});
  }

  Future<void> _preloadOsm() async {
    final cached = await _osmCache.load();
    if (cached.isEmpty) return;
    // Gegen den AKTUELLEN state mergen (nicht alten Snapshot ueberschreiben) —
    // sonst gehen zwischenzeitlich per addOsm/reconcileCommunity gesetzte Pins
    // verloren (Race). Nur fehlende Keys ergaenzen.
    final next = Map<String, ChangingPlace>.of(state.byRef);
    for (final p in cached) {
      if (!next.containsKey(p.placeRef)) {
        _osmOrder.add(p.placeRef);
        next[p.placeRef] = p;
      }
    }
    state = AccumulatedPlaces(next);
  }

  /// OSM-Pins ergaenzen (Union). Bereits vorhandene aktualisieren + persistieren.
  void addOsm(List<ChangingPlace> places) {
    if (places.isEmpty) return;
    final next = Map<String, ChangingPlace>.of(state.byRef);
    for (final p in places) {
      if (!next.containsKey(p.placeRef)) _osmOrder.add(p.placeRef);
      next[p.placeRef] = p;
    }
    _capOsm(next);
    state = AccumulatedPlaces(next);
    // In _osmOrder-Reihenfolge persistieren (konsistent mit In-Memory-Cap).
    unawaited(
      _osmCache.save([
        for (final ref in _osmOrder)
          if (next[ref] case final ChangingPlace p)
            if (p.source == PlaceSource.osm) p,
      ]),
    );
  }

  /// Community-Pins vollstaendig ersetzen (Scope-Reconciliation) — so
  /// verschwinden geloeschte/ausgeblendete Community-Pins zuverlaessig.
  /// No-Op-Guard: identische Menge -> kein Rebuild (verhindert Flackern).
  void reconcileCommunity(List<ChangingPlace> community) {
    final current = state.byRef;
    final next = Map<String, ChangingPlace>.of(current)
      ..removeWhere((k, _) => k.startsWith('community/'));
    for (final p in community) {
      next[p.placeRef] = p;
    }
    if (_sameKeys(current, next)) return;
    state = AccumulatedPlaces(next);
  }

  static bool _sameKeys(
    Map<String, ChangingPlace> a,
    Map<String, ChangingPlace> b,
  ) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
    }
    return true;
  }

  void _capOsm(Map<String, ChangingPlace> map) {
    final osmCount = _osmOrder.length;
    if (osmCount <= _maxOsmPins) return;
    final remove = osmCount - _maxOsmPins;
    for (var i = 0; i < remove; i++) {
      final ref = _osmOrder.removeAt(0);
      map.remove(ref);
    }
  }
}

final accumulatedPlacesProvider =
    NotifierProvider<AccumulatedPlacesNotifier, AccumulatedPlaces>(
      AccumulatedPlacesNotifier.new,
    );
