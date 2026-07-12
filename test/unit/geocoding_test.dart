import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/search/data/geocoding_repository.dart';

void main() {
  group('GeocodingRepository.parseResults', () {
    test('parst Nominatim jsonv2-Treffer', () {
      const body = '''
      [
        {"lat":"52.5219","lon":"13.4132","display_name":"Alexanderplatz, Mitte, Berlin"},
        {"lat":"48.1372","lon":"11.5755","display_name":"Marienplatz, München"}
      ]''';
      final results = GeocodingRepository.parseResults(body);
      expect(results, hasLength(2));
      expect(results.first.label, contains('Alexanderplatz'));
      expect(results.first.location.latitude, closeTo(52.5219, 0.0001));
      expect(results[1].location.longitude, closeTo(11.5755, 0.0001));
    });

    test('ueberspringt Treffer ohne Koordinaten', () {
      const body = '''
      [
        {"display_name":"Kein Koordinaten-Treffer"},
        {"lat":"52.5","lon":"13.4","display_name":"Gültig"}
      ]''';
      final results = GeocodingRepository.parseResults(body);
      expect(results, hasLength(1));
      expect(results.single.label, 'Gültig');
    });

    test('leere/ungueltige Antwort ergibt leere Liste', () {
      expect(GeocodingRepository.parseResults('[]'), isEmpty);
      expect(GeocodingRepository.parseResults('{"foo":"bar"}'), isEmpty);
    });
  });
}
