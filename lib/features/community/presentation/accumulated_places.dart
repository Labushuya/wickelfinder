import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/changing_place.dart';

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
///   erreicht).
/// - Community-Pins werden per "Scope-Reconciliation" ersetzt: nach jedem
///   Community-Fetch wird die gesamte `community/*`-Teilmenge neu gesetzt, damit
///   geloeschte/ausgeblendete Community-Pins auch ohne Neustart verschwinden.
class AccumulatedPlacesNotifier extends Notifier<AccumulatedPlaces> {
  /// Weicher Speicher-Deckel: aeltester OSM-Ueberschuss wird verworfen.
  static const _maxOsmPins = 4000;

  // Einfuege-Reihenfolge der OSM-Refs (fuer LRU-artiges Kappen).
  final List<String> _osmOrder = [];

  @override
  AccumulatedPlaces build() => const AccumulatedPlaces({});

  /// OSM-Pins ergaenzen (Union). Bereits vorhandene aktualisieren.
  void addOsm(List<ChangingPlace> places) {
    if (places.isEmpty) return;
    final next = Map<String, ChangingPlace>.of(state.byRef);
    for (final p in places) {
      if (!next.containsKey(p.placeRef)) _osmOrder.add(p.placeRef);
      next[p.placeRef] = p;
    }
    _capOsm(next);
    state = AccumulatedPlaces(next);
  }

  /// Community-Pins vollstaendig ersetzen (Scope-Reconciliation) — so
  /// verschwinden geloeschte/ausgeblendete Community-Pins zuverlaessig.
  void reconcileCommunity(List<ChangingPlace> community) {
    final next = Map<String, ChangingPlace>.of(state.byRef)
      ..removeWhere((k, _) => k.startsWith('community/'));
    for (final p in community) {
      next[p.placeRef] = p;
    }
    state = AccumulatedPlaces(next);
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
