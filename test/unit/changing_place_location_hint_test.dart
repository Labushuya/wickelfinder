import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';

ChangingPlace _place(String? hint) => ChangingPlace(
  id: 'node/1',
  location: const LatLng(0, 0),
  locationHint: hint,
);

void main() {
  group('ChangingPlace.displayLocationHint', () {
    test('übersetzt bekannte OSM-Enum-Werte', () {
      expect(
        _place('wheelchair_toilet').displayLocationHint,
        'Im barrierefreien WC',
      );
      expect(
        _place('dedicated_room').displayLocationHint,
        'Eigener Wickelraum',
      );
      expect(
        _place('baby_care_room').displayLocationHint,
        'Eigener Wickelraum',
      );
      expect(_place('female_toilet').displayLocationHint, 'Im Damen-WC');
      expect(_place('male_toilet').displayLocationHint, 'Im Herren-WC');
      expect(_place('unisex_toilet').displayLocationHint, 'Im Unisex-WC');
      expect(_place('bench').displayLocationHint, 'Wickelbank');
    });

    test('reicht unbekannten Wert / Community-Freitext unverändert durch', () {
      expect(
        _place('Neben der Kasse, 1. Stock').displayLocationHint,
        'Neben der Kasse, 1. Stock',
      );
      expect(
        _place('irgendein_neues_enum').displayLocationHint,
        'irgendein_neues_enum',
      );
    });

    test('zusammengesetzte Enum-Liste (; oder ,) wird je Teil übersetzt', () {
      expect(
        _place('female_toilet;male_toilet').displayLocationHint,
        'Im Damen-WC / Im Herren-WC',
      );
      expect(
        _place('female_toilet,male_toilet').displayLocationHint,
        'Im Damen-WC / Im Herren-WC',
      );
      // Unbekanntes Teil bleibt roh, bekanntes wird übersetzt.
      expect(
        _place('wheelchair_toilet;irgendwas').displayLocationHint,
        'Im barrierefreien WC / irgendwas',
      );
    });

    test('null bleibt null', () {
      expect(_place(null).displayLocationHint, isNull);
    });
  });
}
