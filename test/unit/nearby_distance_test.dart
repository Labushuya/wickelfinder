import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/presentation/nearby_places_screen.dart';

void main() {
  group('formatDistance', () {
    test('unter 1 km in Metern, auf 10 gerundet', () {
      expect(formatDistance(0), '0 m');
      expect(formatDistance(12), '10 m');
      expect(formatDistance(15), '20 m');
      expect(formatDistance(994), '990 m');
    });

    test('ab 1 km in Kilometern mit einer Nachkommastelle (Komma)', () {
      expect(formatDistance(1000), '1,0 km');
      expect(formatDistance(1234), '1,2 km');
      expect(formatDistance(15900), '15,9 km');
    });
  });
}
