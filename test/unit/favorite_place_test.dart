import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/favorites/domain/favorite_place.dart';

void main() {
  group('FavoritePlace.toJson/fromJson', () {
    test('round-trip mit Namen', () {
      const f = FavoritePlace(
        placeRef: 'node/123',
        lat: 52.5,
        lon: 13.4,
        name: 'Café Klein',
      );
      final back = FavoritePlace.fromJson(f.toJson());
      expect(back, isNotNull);
      expect(back!.placeRef, 'node/123');
      expect(back.lat, 52.5);
      expect(back.lon, 13.4);
      expect(back.name, 'Café Klein');
    });

    test('round-trip ohne Namen (null)', () {
      const f = FavoritePlace(placeRef: 'community/abc', lat: 1.0, lon: 2.0);
      final back = FavoritePlace.fromJson(f.toJson());
      expect(back, isNotNull);
      expect(back!.name, isNull);
      expect(back.placeRef, 'community/abc');
    });

    test('fehlende Pflichtfelder -> null', () {
      expect(FavoritePlace.fromJson({'lat': 1.0, 'lon': 2.0}), isNull);
      expect(FavoritePlace.fromJson({'ref': 'node/1', 'lon': 2.0}), isNull);
      expect(FavoritePlace.fromJson({'ref': 'node/1', 'lat': 1.0}), isNull);
    });

    test('int-Koordinaten werden zu double', () {
      final back = FavoritePlace.fromJson({
        'ref': 'node/1',
        'lat': 5,
        'lon': 7,
      });
      expect(back, isNotNull);
      expect(back!.lat, 5.0);
      expect(back.lon, 7.0);
    });
  });
}
