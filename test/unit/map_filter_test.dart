import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';
import 'package:wickelfinder/features/map/domain/map_filter.dart';
import 'package:wickelfinder/features/map/domain/venue_context.dart';

ChangingPlace _p({
  bool? wheelchair,
  FeeMode? feeMode,
  bool? fee,
  String? hint,
  String? openingHours,
  VenueContext venue = VenueContext.unknown,
  PlaceSource source = PlaceSource.osm,
}) => ChangingPlace(
  id: source == PlaceSource.community ? 'x' : 'node/1',
  location: const LatLng(0, 0),
  wheelchairAccessible: wheelchair,
  feeMode: feeMode,
  fee: fee,
  locationHint: hint,
  openingHours: openingHours,
  venueContext: venue,
  source: source,
);

void main() {
  group('MapFilter — leer zeigt alles', () {
    test('leerer Filter matcht jeden Pin', () {
      expect(const MapFilter().isActive, isFalse);
      expect(const MapFilter().matches(_p()), isTrue);
      expect(const MapFilter().activeCount, 0);
    });
  });

  group('MapFilter — Barrierefrei (unbekannt einschließen)', () {
    const f = MapFilter(onlyBarrierefrei: true);
    test('yes besteht', () => expect(f.matches(_p(wheelchair: true)), isTrue));
    test(
      'no fällt raus',
      () => expect(f.matches(_p(wheelchair: false)), isFalse),
    );
    test('unbekannt (null) wird EINGESCHLOSSEN', () {
      expect(f.matches(_p(wheelchair: null)), isTrue);
    });
  });

  group('MapFilter — Kostenlos (unbekannt einschließen)', () {
    const f = MapFilter(onlyFree: true);
    test(
      'free besteht',
      () => expect(f.matches(_p(feeMode: FeeMode.free)), isTrue),
    );
    test(
      'paid fällt raus',
      () => expect(f.matches(_p(feeMode: FeeMode.paid)), isFalse),
    );
    test(
      'unbekannt wird eingeschlossen',
      () => expect(f.matches(_p()), isTrue),
    );
  });

  group('MapFilter — frei zugänglich', () {
    const f = MapFilter(onlyAccessible: true);
    test('Restaurant (accessRestricted) fällt raus', () {
      expect(f.matches(_p(venue: VenueContext.restaurant)), isFalse);
    });
    test('Supermarkt (frei) besteht', () {
      expect(f.matches(_p(venue: VenueContext.supermarket)), isTrue);
    });
  });

  group('MapFilter — Eigener Wickelraum (Multi-Value)', () {
    const f = MapFilter(onlyOwnRoom: true);
    test(
      'dedicated_room besteht',
      () => expect(f.matches(_p(hint: 'dedicated_room')), isTrue),
    );
    test('in Multi-Value-Liste besteht', () {
      expect(f.matches(_p(hint: 'female_toilet;baby_care_room')), isTrue);
    });
    test(
      'anderer Wert fällt raus',
      () => expect(f.matches(_p(hint: 'wheelchair_toilet')), isFalse),
    );
    test(
      'unbekannt (null) wird eingeschlossen',
      () => expect(f.matches(_p()), isTrue),
    );
  });

  group('MapFilter — Ortstyp & Quelle', () {
    test('Ortstyp-Menge', () {
      const f = MapFilter(venues: {VenueContext.supermarket});
      expect(f.matches(_p(venue: VenueContext.supermarket)), isTrue);
      expect(f.matches(_p(venue: VenueContext.restaurant)), isFalse);
    });
    test('Quelle', () {
      const f = MapFilter(sources: {PlaceSource.community});
      expect(f.matches(_p(source: PlaceSource.community)), isTrue);
      expect(f.matches(_p(source: PlaceSource.osm)), isFalse);
    });
  });

  group('activeCount — zählt einzelne Auswahlen', () {
    test('nur Schalter', () {
      const f = MapFilter(onlyFree: true, onlyBarrierefrei: true);
      expect(f.activeCount, 2);
      expect(f.isActive, isTrue);
    });
    test('Ortstypen zählen einzeln (nicht als 1 Kategorie)', () {
      const f = MapFilter(
        venues: {VenueContext.supermarket, VenueContext.restaurant},
      );
      expect(f.activeCount, 2);
    });
    test('kombiniert: Ortstypen + Quelle + Schalter', () {
      const f = MapFilter(
        venues: {VenueContext.supermarket, VenueContext.mall},
        sources: {PlaceSource.community},
        onlyFree: true,
      );
      // 2 Ortstypen + 1 Quelle + 1 Schalter
      expect(f.activeCount, 4);
    });
    test('leer -> 0', () {
      expect(const MapFilter().activeCount, 0);
    });
  });

  group('MapFilter — Nur jetzt geöffnet (Einschließen-Semantik)', () {
    const f = MapFilter(onlyOpenNow: true);
    final tue10 = DateTime(2026, 8, 4, 10, 0); // Dienstag
    final tue19 = DateTime(2026, 8, 4, 19, 0);

    test('aktuell offen -> drin', () {
      expect(
        f.matches(_p(openingHours: 'Mo-Fr 08:00-18:00'), now: tue10),
        isTrue,
      );
    });
    test('aktuell geschlossen -> raus', () {
      expect(
        f.matches(_p(openingHours: 'Mo-Fr 08:00-18:00'), now: tue19),
        isFalse,
      );
    });
    test('unbekannte Zeiten (komplex/Saison) -> drin', () {
      // Saison-Syntax bleibt unknown -> Einschließen-Semantik greift.
      expect(
        f.matches(_p(openingHours: 'Apr-Oct: Mo-Su 09:00-19:00'), now: tue19),
        isTrue,
      );
    });
    test('PH-Off-Klausel: Werktag abends geschlossen -> raus', () {
      // PH wird ignoriert, Werktag ist auswertbar -> Di 19:00 = geschlossen.
      expect(
        f.matches(_p(openingHours: 'Mo-Fr 08:00-18:00; PH off'), now: tue19),
        isFalse,
      );
    });
    test('keine Zeitangabe -> drin', () {
      expect(f.matches(_p(), now: tue19), isTrue);
    });
    test('ohne now-Parameter wirkungslos (schließt nichts aus)', () {
      expect(f.matches(_p(openingHours: 'Mo-Fr 08:00-18:00')), isTrue);
    });
  });
}
