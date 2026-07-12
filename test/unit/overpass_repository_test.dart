import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/map/data/overpass_repository.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';

void main() {
  group('OverpassRepository.buildQuery', () {
    test('setzt Bounding-Box in korrekter Overpass-Reihenfolge (S,W,N,O)', () {
      final q = OverpassRepository.buildQuery(
        south: 52.49,
        west: 13.36,
        north: 52.54,
        east: 13.43,
      );
      expect(q, contains('(52.49,13.36,52.54,13.43)'));
      expect(q, contains('"changing_table"="yes"'));
      expect(q, contains('out center;'));
    });
  });

  group('OverpassRepository.parseResponse', () {
    test('parst node mit lat/lon und tags', () {
      const body = '''
      {"elements":[
        {"type":"node","id":1,"lat":52.5,"lon":13.4,
         "tags":{"name":"Café Klein","changing_table":"yes",
                 "wheelchair":"yes","fee":"no",
                 "changing_table:location":"wheelchair_toilet"}}
      ]}''';
      final places = OverpassRepository.parseResponse(body);

      expect(places, hasLength(1));
      final p = places.single;
      expect(p.id, 'node/1');
      expect(p.name, 'Café Klein');
      expect(p.location.latitude, 52.5);
      expect(p.location.longitude, 13.4);
      expect(p.wheelchairAccessible, isTrue);
      expect(p.fee, isFalse);
      expect(p.locationHint, 'wheelchair_toilet');
      expect(p.source, PlaceSource.osm);
    });

    test('parst way/relation über center-Koordinaten', () {
      const body = '''
      {"elements":[
        {"type":"way","id":42,"center":{"lat":48.1,"lon":11.5},
         "tags":{"changing_table":"yes"}}
      ]}''';
      final places = OverpassRepository.parseResponse(body);

      expect(places.single.id, 'way/42');
      expect(places.single.location.latitude, 48.1);
    });

    test('überspringt Elemente ohne Koordinaten, ohne zu werfen', () {
      const body = '''
      {"elements":[
        {"type":"node","id":1,"tags":{"changing_table":"yes"}},
        {"type":"node","id":2,"lat":52.5,"lon":13.4,"tags":{}}
      ]}''';
      final places = OverpassRepository.parseResponse(body);

      // Nur das zweite Element hat Koordinaten.
      expect(places, hasLength(1));
      expect(places.single.id, 'node/2');
    });

    test('unbekannte wheelchair/fee-Werte werden zu null', () {
      const body = '''
      {"elements":[
        {"type":"node","id":1,"lat":1,"lon":2,
         "tags":{"changing_table":"yes","wheelchair":"limited"}}
      ]}''';
      final p = OverpassRepository.parseResponse(body).single;
      expect(p.wheelchairAccessible, isNull);
      expect(p.fee, isNull);
    });

    test('wirft OverpassException bei unerwartetem Format', () {
      expect(
        () => OverpassRepository.parseResponse('{"foo":"bar"}'),
        throwsA(isA<OverpassException>()),
      );
    });

    test('leere elements-Liste ergibt leere Platz-Liste', () {
      final places = OverpassRepository.parseResponse('{"elements":[]}');
      expect(places, isEmpty);
    });
  });
}
