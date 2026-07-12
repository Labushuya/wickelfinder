import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/domain/place_tag.dart';

void main() {
  group('PlaceTag.opposite', () {
    test('kostenlos <-> kostenpflichtig', () {
      expect(PlaceTag.freeOfCharge.opposite, PlaceTag.paid);
      expect(PlaceTag.paid.opposite, PlaceTag.freeOfCharge);
    });

    test('Entsorgung <-> keine Entsorgung', () {
      expect(PlaceTag.disposal.opposite, PlaceTag.noDisposal);
      expect(PlaceTag.noDisposal.opposite, PlaceTag.disposal);
    });

    test('große Fläche <-> eng', () {
      expect(PlaceTag.largeSurface.opposite, PlaceTag.cramped);
      expect(PlaceTag.cramped.opposite, PlaceTag.largeSurface);
    });

    test('Tags ohne Gegenteil geben null', () {
      expect(PlaceTag.clean.opposite, isNull);
      expect(PlaceTag.padding.opposite, isNull);
      expect(PlaceTag.separateRoom.opposite, isNull);
      expect(PlaceTag.sink.opposite, isNull);
    });

    test('Gegensatz ist symmetrisch fuer alle Tags', () {
      for (final t in PlaceTag.values) {
        final opp = t.opposite;
        if (opp != null) {
          expect(opp.opposite, t, reason: '$t <-> $opp muss symmetrisch sein');
        }
      }
    });
  });
}
