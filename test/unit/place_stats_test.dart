import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/community/domain/place_stats.dart';
import 'package:wickelfinder/features/community/domain/place_tag.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';

void main() {
  group('PlaceStats.fromJson', () {
    test('parst vollstaendige Statistik', () {
      final s = PlaceStats.fromJson({
        'place_ref': 'node/1',
        'rating_count': 4,
        'avg_stars': 4.25,
        'flag_count': 1,
        'confirm_count': 2,
        'is_questionable': false,
        'wrong_loc_count': 3,
        'location_disputed': true,
      });
      expect(s.placeRef, 'node/1');
      expect(s.ratingCount, 4);
      expect(s.avgStars, 4.25);
      expect(s.flagCount, 1);
      expect(s.confirmCount, 2);
      expect(s.isQuestionable, isFalse);
      expect(s.wrongLocationCount, 3);
      expect(s.locationDisputed, isTrue);
    });

    test('fehlende wrong_loc-Felder -> 0/false (Abwaertskompatibel)', () {
      final s = PlaceStats.fromJson({
        'place_ref': 'node/9',
        'rating_count': 1,
        'avg_stars': 3.0,
        'flag_count': 0,
        'confirm_count': 0,
        'is_questionable': false,
      });
      expect(s.wrongLocationCount, 0);
      expect(s.locationDisputed, isFalse);
    });

    test('avg_stars null bleibt null (keine Bewertung)', () {
      final s = PlaceStats.fromJson({
        'place_ref': 'node/2',
        'rating_count': 0,
        'avg_stars': null,
        'flag_count': 0,
        'confirm_count': 0,
        'is_questionable': false,
      });
      expect(s.avgStars, isNull);
    });

    test('is_questionable=true wird uebernommen', () {
      final s = PlaceStats.fromJson({
        'place_ref': 'node/3',
        'rating_count': 0,
        'avg_stars': null,
        'flag_count': 6,
        'confirm_count': 0,
        'is_questionable': true,
      });
      expect(s.isQuestionable, isTrue);
    });

    test('empty() erzeugt neutrale Statistik', () {
      final s = PlaceStats.empty('community/abc');
      expect(s.placeRef, 'community/abc');
      expect(s.ratingCount, 0);
      expect(s.avgStars, isNull);
      expect(s.isQuestionable, isFalse);
      expect(s.wrongLocationCount, 0);
      expect(s.locationDisputed, isFalse);
    });
  });

  group('ChangingPlace.placeRef', () {
    test('OSM-Platz nutzt id direkt', () {
      const p = ChangingPlace(id: 'node/42', location: LatLng(1, 2));
      expect(p.placeRef, 'node/42');
    });

    test('Community-Platz bekommt community/-Praefix', () {
      const p = ChangingPlace(
        id: 'uuid-123',
        location: LatLng(1, 2),
        source: PlaceSource.community,
      );
      expect(p.placeRef, 'community/uuid-123');
    });
  });

  group('PlaceTag', () {
    test('wire-Werte entsprechen dem Postgres-Enum', () {
      expect(PlaceTag.clean.wire, 'clean');
      expect(PlaceTag.largeSurface.wire, 'large_surface');
      expect(PlaceTag.padding.wire, 'padding');
      expect(PlaceTag.freeOfCharge.wire, 'free_of_charge');
    });
  });
}
