import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/map/domain/opening_hours_status.dart';

void main() {
  // Feste Bezugstage (2026): 08-02 So, 08-04 Di, 08-05 Mi.
  final tue10 = DateTime(2026, 8, 4, 10, 0);
  final tue19 = DateTime(2026, 8, 4, 19, 0);
  final wed12 = DateTime(2026, 8, 5, 12, 0);
  final sun12 = DateTime(2026, 8, 2, 12, 0);

  group('openStateAt', () {
    test('24/7 immer offen', () {
      expect(openStateAt('24/7', tue10), OpenState.open);
      expect(openStateAt('24/7', sun12), OpenState.open);
    });

    test('Mo-Fr 08:00-18:00 innerhalb -> open', () {
      expect(openStateAt('Mo-Fr 08:00-18:00', tue10), OpenState.open);
    });

    test('Mo-Fr 08:00-18:00 nach Feierabend -> closed', () {
      expect(openStateAt('Mo-Fr 08:00-18:00', tue19), OpenState.closed);
    });

    test('Mo-Fr an einem Sonntag -> closed (Tag nicht enthalten)', () {
      expect(openStateAt('Mo-Fr 08:00-18:00', sun12), OpenState.closed);
    });

    test('Mo-Sa 10:00-18:00; Su off — Sonntag closed, Mi offen', () {
      expect(openStateAt('Mo-Sa 10:00-18:00; Su off', sun12), OpenState.closed);
      expect(openStateAt('Mo-Sa 10:00-18:00; Su off', wed12), OpenState.open);
    });

    test('PH/SH-Off-Klausel wird toleriert (Werktag bleibt auswertbar)', () {
      // 'PH off' darf den klaren Werktags-Status nicht auf unknown ziehen.
      expect(openStateAt('Mo-Fr 08:00-18:00; PH off', tue10), OpenState.open);
      expect(openStateAt('Mo-Fr 08:00-18:00; PH off', tue19), OpenState.closed);
      // Kombiniert Su + PH: Sonntag geschlossen, PH ignoriert.
      expect(
        openStateAt('Mo-Sa 10:00-18:00; Su,PH off', sun12),
        OpenState.closed,
      );
    });

    test('reines Zeitfenster gilt täglich', () {
      expect(openStateAt('08:00-18:00', sun12), OpenState.open);
      expect(openStateAt('08:00-18:00', tue19), OpenState.closed);
    });

    group('unknown (ehrlich, nie falsch offen/zu)', () {
      test('Saison/Monate -> unknown', () {
        expect(
          openStateAt('Apr-Oct: Mo-Su 09:00-19:00', tue10),
          OpenState.unknown,
        );
      });
      test('Über-Nacht-Intervall -> unknown', () {
        expect(openStateAt('22:00-02:00', tue19), OpenState.unknown);
      });
      test('unbekanntes Tageskürzel -> unknown', () {
        expect(openStateAt('Xy 08:00-18:00', tue10), OpenState.unknown);
      });
      test('leerer String -> unknown', () {
        expect(openStateAt('', tue10), OpenState.unknown);
        expect(openStateAt('   ', tue10), OpenState.unknown);
      });
    });
  });
}
