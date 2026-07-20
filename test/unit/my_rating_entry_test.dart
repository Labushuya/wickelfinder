import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/data/community_repository.dart';

void main() {
  group('MyRatingEntry.hasCoords', () {
    const rating = MyRating(stars: 4, tags: {});

    test('true, wenn lat UND lon vorhanden', () {
      const e = MyRatingEntry(
        placeRef: 'node/1',
        rating: rating,
        lat: 49.4,
        lon: 8.6,
      );
      expect(e.hasCoords, isTrue);
    });

    test('false, wenn Koordinaten fehlen', () {
      const e = MyRatingEntry(placeRef: 'node/2', rating: rating);
      expect(e.hasCoords, isFalse);
    });

    test('false, wenn nur eine Koordinate vorliegt', () {
      const e = MyRatingEntry(placeRef: 'node/3', rating: rating, lat: 49.4);
      expect(e.hasCoords, isFalse);
    });
  });
}
