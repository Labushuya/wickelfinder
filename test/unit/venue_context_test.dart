import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/map/domain/venue_context.dart';

void main() {
  group('VenueContext.fromTags', () {
    test('Schwimmbad aus leisure=swimming_pool', () {
      final c = VenueContext.fromTags({'leisure': 'swimming_pool'});
      expect(c, VenueContext.swimmingPool);
      expect(c.accessRestricted, isTrue);
    });

    test('Restaurant aus amenity=restaurant', () {
      expect(
        VenueContext.fromTags({'amenity': 'restaurant'}),
        VenueContext.restaurant,
      );
    });

    test('Café zaehlt als Restaurant-Kontext', () {
      expect(
        VenueContext.fromTags({'amenity': 'cafe'}),
        VenueContext.restaurant,
      );
    });

    test('Einkaufszentrum aus shop=mall ist NICHT zugangsbeschraenkt', () {
      final c = VenueContext.fromTags({'shop': 'mall'});
      expect(c, VenueContext.mall);
      expect(c.accessRestricted, isFalse);
    });

    test('oeffentliche Toilette aus amenity=toilets', () {
      expect(
        VenueContext.fromTags({'amenity': 'toilets'}),
        VenueContext.publicToilet,
      );
    });

    test('Raststaette aus highway=services', () {
      expect(
        VenueContext.fromTags({'highway': 'services'}),
        VenueContext.services,
      );
    });

    test('ohne passende Tags -> unknown', () {
      expect(
        VenueContext.fromTags({'name': 'Irgendwas'}),
        VenueContext.unknown,
      );
      expect(VenueContext.fromTags(const {}), VenueContext.unknown);
    });

    test('spezifischeres Tag gewinnt (swimming_pool vor sports_centre)', () {
      final c = VenueContext.fromTags({
        'leisure': 'swimming_pool',
        'sport': 'swimming',
      });
      expect(c, VenueContext.swimmingPool);
    });
  });
}
