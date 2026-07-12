import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/community/domain/place_merge.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';

ChangingPlace _osm(String id, double lat, double lon, {String? name}) =>
    ChangingPlace(id: id, location: LatLng(lat, lon), name: name);

ChangingPlace _community(String id, double lat, double lon, {String? name}) =>
    ChangingPlace(
      id: id,
      location: LatLng(lat, lon),
      name: name,
      source: PlaceSource.community,
    );

void main() {
  group('mergePlaces', () {
    test('OSM-Plaetze bleiben immer erhalten', () {
      final osm = [_osm('node/1', 52.5, 13.4)];
      final merged = mergePlaces(osm: osm, community: const []);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'node/1');
    });

    test('weit entfernter Community-Platz wird eigenstaendig angezeigt', () {
      final osm = [_osm('node/1', 52.5, 13.4, name: 'Café A')];
      final community = [_community('c1', 52.9, 13.9, name: 'Spielplatz B')];
      final merged = mergePlaces(osm: osm, community: community);
      expect(merged, hasLength(2));
    });

    test('naher Community-Platz mit gleichem Namen gilt als Duplikat', () {
      // ~10 m Versatz, gleicher Name -> Duplikat, nicht doppelt zeigen.
      final osm = [_osm('node/1', 52.50000, 13.40000, name: 'Rossmann')];
      final community = [
        _community('c1', 52.50008, 13.40000, name: 'Rossmann'),
      ];
      final merged = mergePlaces(osm: osm, community: community);
      expect(merged, hasLength(1));
      expect(merged.single.source, PlaceSource.osm); // OSM gewinnt Anzeige
    });

    test('naher Community-Platz mit ANDEREM Namen wird NICHT verschluckt', () {
      // Gleiche Naehe, aber klar anderer Name -> eigener Eintrag.
      final osm = [_osm('node/1', 52.50000, 13.40000, name: 'Rossmann')];
      final community = [
        _community('c1', 52.50008, 13.40000, name: 'Stadtbücherei'),
      ];
      final merged = mergePlaces(osm: osm, community: community);
      expect(merged, hasLength(2));
    });

    test('naher Community-Platz ohne Namen gilt als Duplikat', () {
      final osm = [_osm('node/1', 52.5, 13.4, name: 'Café')];
      final community = [_community('c1', 52.50005, 13.4)]; // kein Name
      final merged = mergePlaces(osm: osm, community: community);
      expect(merged, hasLength(1));
    });

    test('Community-Platz knapp ausserhalb des Radius bleibt eigenstaendig', () {
      // ~150 m entfernt (> 75 m Radius) -> eigener Eintrag trotz gleichem Namen.
      final osm = [_osm('node/1', 52.5000, 13.4000, name: 'Rossmann')];
      final community = [_community('c1', 52.50135, 13.4000, name: 'Rossmann')];
      final merged = mergePlaces(osm: osm, community: community);
      expect(merged, hasLength(2));
    });
  });
}
