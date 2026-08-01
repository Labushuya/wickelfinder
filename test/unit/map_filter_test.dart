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
  VenueContext venue = VenueContext.unknown,
  PlaceSource source = PlaceSource.osm,
}) => ChangingPlace(
  id: source == PlaceSource.community ? 'x' : 'node/1',
  location: const LatLng(0, 0),
  wheelchairAccessible: wheelchair,
  feeMode: feeMode,
  fee: fee,
  locationHint: hint,
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
      final f = MapFilter(venues: {VenueContext.supermarket});
      expect(f.matches(_p(venue: VenueContext.supermarket)), isTrue);
      expect(f.matches(_p(venue: VenueContext.restaurant)), isFalse);
    });
    test('Quelle', () {
      final f = MapFilter(sources: {PlaceSource.community});
      expect(f.matches(_p(source: PlaceSource.community)), isTrue);
      expect(f.matches(_p(source: PlaceSource.osm)), isFalse);
    });
  });

  test('activeCount zählt gesetzte Kriterien', () {
    const f = MapFilter(onlyFree: true, onlyBarrierefrei: true);
    expect(f.activeCount, 2);
    expect(f.isActive, isTrue);
  });
}
