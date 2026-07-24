import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/map/domain/opening_hours_format.dart';

void main() {
  group('formatOpeningHours — übersetzt gängige Muster', () {
    test('24/7', () {
      expect(formatOpeningHours('24/7'), 'Durchgehend geöffnet (24/7)');
    });

    test('Mo-Fr 08:00-18:00 -> deutscher Bereich, volle Stunden', () {
      expect(formatOpeningHours('Mo-Fr 08:00-18:00'), 'Mo–Fr 8–18 Uhr');
    });

    test('Mo-Su mit Minuten', () {
      expect(formatOpeningHours('Mo-Su 10:30-20:00'), 'Mo–So 10:30–20 Uhr');
    });

    test('Tagesliste Mo,We,Fr', () {
      expect(formatOpeningHours('Mo,We,Fr 09:00-17:00'), 'Mo, Mi, Fr 9–17 Uhr');
    });

    test('einzelner Tag Sa', () {
      expect(formatOpeningHours('Sa 10:00-14:00'), 'Sa 10–14 Uhr');
    });

    test('nur Zeitfenster ohne Tag', () {
      expect(formatOpeningHours('08:00-18:00'), 'Täglich 8–18 Uhr');
    });

    test('trimmt Whitespace', () {
      expect(formatOpeningHours('  Mo-Fr 08:00-18:00  '), 'Mo–Fr 8–18 Uhr');
    });
  });

  group('formatOpeningHours — Rohtext-Fallback bei Komplexem', () {
    test('mehrere Regeln mit Semikolon -> unverändert', () {
      const raw = 'Mo-Fr 08:00-12:00,13:00-18:00; Sa 09:00-14:00';
      expect(formatOpeningHours(raw), raw);
    });

    test('Feiertage PH off -> unverändert', () {
      const raw = 'Mo-Fr 08:00-18:00; PH off';
      expect(formatOpeningHours(raw), raw);
    });

    test('Saison/Monate -> unverändert', () {
      const raw = 'Apr-Oct: Mo-Su 09:00-19:00';
      expect(formatOpeningHours(raw), raw);
    });

    test('Kommentar in Anführungszeichen -> unverändert', () {
      const raw = 'Mo-Fr 08:00-18:00 "nur nach Absprache"';
      expect(formatOpeningHours(raw), raw);
    });

    test('unbekanntes Tageskürzel -> unverändert', () {
      const raw = 'Xy-Fr 08:00-18:00';
      expect(formatOpeningHours(raw), raw);
    });

    test('leerer String bleibt leer', () {
      expect(formatOpeningHours(''), '');
      expect(formatOpeningHours('   '), '');
    });
  });
}
