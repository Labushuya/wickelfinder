import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/community/presentation/accumulated_places.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';

ChangingPlace _osm(String id, {String? name}) => ChangingPlace(
  id: id, // z.B. 'node/1' -> placeRef == id
  location: const LatLng(0, 0),
  name: name,
);

ChangingPlace _community(String id, {String? name}) => ChangingPlace(
  id: id,
  location: const LatLng(0, 0),
  name: name,
  source: PlaceSource.community,
);

void main() {
  // OsmCache nutzt path_provider; ohne Binding wirft es -> intern gefangen
  // (load()->[], save()->no-op). Binding trotzdem initialisieren.
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  AccumulatedPlacesNotifier notifier(ProviderContainer c) =>
      c.read(accumulatedPlacesProvider.notifier);

  group('AccumulatedPlaces — addOsm', () {
    test('dedupliziert per placeRef; letzter gewinnt', () {
      final c = makeContainer();
      final n = notifier(c);
      n.addOsm([_osm('node/1', name: 'Alt')]);
      n.addOsm([_osm('node/1', name: 'Neu')]);
      final places = c.read(accumulatedPlacesProvider).all;
      expect(places.length, 1);
      expect(places.single.name, 'Neu');
    });

    test('ergänzt statt zu ersetzen (Pins verschwinden nicht)', () {
      final c = makeContainer();
      final n = notifier(c);
      n.addOsm([_osm('node/1')]);
      n.addOsm([_osm('node/2')]);
      expect(c.read(accumulatedPlacesProvider).length, 2);
    });

    test('kappt bei Überschuss auf 4000, ältester zuerst weg', () {
      final c = makeContainer();
      final n = notifier(c);
      // 4001 OSM-Pins einzeln einspeisen -> node/0 (ältester) fällt raus.
      for (var i = 0; i < 4001; i++) {
        n.addOsm([_osm('node/$i')]);
      }
      final byRef = c.read(accumulatedPlacesProvider).byRef;
      expect(byRef.length, 4000);
      expect(byRef.containsKey('node/0'), isFalse); // ältester verworfen
      expect(byRef.containsKey('node/4000'), isTrue); // neuester da
    });
  });

  group('AccumulatedPlaces — reconcileCommunity', () {
    test('ersetzt Community-Pins, lässt OSM-Pins unberührt', () {
      final c = makeContainer();
      final n = notifier(c);
      n.addOsm([_osm('node/1')]);
      n.reconcileCommunity([_community('a'), _community('b')]);
      var byRef = c.read(accumulatedPlacesProvider).byRef;
      expect(byRef.containsKey('node/1'), isTrue);
      expect(byRef.containsKey('community/a'), isTrue);

      // Zweiter Sync ohne 'a' -> 'a' verschwindet, OSM bleibt.
      n.reconcileCommunity([_community('b')]);
      byRef = c.read(accumulatedPlacesProvider).byRef;
      expect(byRef.containsKey('community/a'), isFalse);
      expect(byRef.containsKey('community/b'), isTrue);
      expect(byRef.containsKey('node/1'), isTrue);
    });

    test(
      'Regressions-Lock: Edit gleicher id (neue Instanz) landet im state',
      () {
        final c = makeContainer();
        final n = notifier(c);
        n.reconcileCommunity([_community('a', name: 'Alt')]);
        // Neue Instanz, gleiche id, geänderter Name -> muss übernommen werden
        // (früherer Bug: gleicher Key -> No-Op -> Edit verschluckt).
        n.reconcileCommunity([_community('a', name: 'Neu')]);
        final p = c.read(accumulatedPlacesProvider).byRef['community/a'];
        expect(p?.name, 'Neu');
      },
    );

    test('identische Instanzen -> kein neuer State (No-Op-Guard)', () {
      final c = makeContainer();
      final n = notifier(c);
      final shared = _community('a', name: 'X');
      n.reconcileCommunity([shared]);
      final before = c.read(accumulatedPlacesProvider);
      n.reconcileCommunity([shared]); // exakt dieselbe Instanz
      final after = c.read(accumulatedPlacesProvider);
      expect(identical(before, after), isTrue);
    });
  });
}
