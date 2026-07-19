import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/updater/data/update_repository.dart';

void main() {
  group('UpdateRepository.isNewer - SemVer-Precedence', () {
    test('1. Prerelease-Bump im gleichen Core (der Original-Bug)', () {
      // "0.12.1-beta.1" wurde frueher als [0,12,0] gelesen -> false.
      expect(
        UpdateRepository.isNewer('0.12.1-beta.1', '0.12.0-beta.3'),
        isTrue,
      );
    });

    test('2. Beta-Zaehler hochzaehlen', () {
      expect(
        UpdateRepository.isNewer('0.12.0-beta.3', '0.12.0-beta.2'),
        isTrue,
      );
    });

    test('3. Beta-Zaehler numerisch, nicht lexikalisch (2 < 10)', () {
      expect(
        UpdateRepository.isNewer('0.12.0-beta.2', '0.12.0-beta.10'),
        isFalse,
      );
      expect(
        UpdateRepository.isNewer('0.12.0-beta.10', '0.12.0-beta.2'),
        isTrue,
      );
    });

    test('4. Minor-Bump schlaegt gleichen Prerelease', () {
      expect(
        UpdateRepository.isNewer('0.12.0-beta.1', '0.11.0-beta.1'),
        isTrue,
      );
    });

    test('5. Prerelease < Stable derselben Version', () {
      expect(UpdateRepository.isNewer('1.0.0-beta', '1.0.0'), isFalse);
    });

    test('6. Stable > Prerelease derselben Version', () {
      expect(UpdateRepository.isNewer('1.0.0', '1.0.0-beta'), isTrue);
    });

    test('7. Build-Metadaten werden ignoriert -> gleich -> false', () {
      expect(UpdateRepository.isNewer('0.12.1+30', '0.12.1+29'), isFalse);
      expect(UpdateRepository.isNewer('0.12.1+29', '0.12.1+30'), isFalse);
    });

    test('8. beta > alpha (lexikalisch)', () {
      expect(
        UpdateRepository.isNewer('0.12.0-beta.1', '0.12.0-alpha.5'),
        isTrue,
      );
    });

    // --- Adversarial / Robustheit ---

    test('gleiche Version -> false (kein Self-Update-Loop)', () {
      expect(
        UpdateRepository.isNewer('0.12.0-beta.3', '0.12.0-beta.3'),
        isFalse,
      );
      expect(UpdateRepository.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('kuerzere Prerelease-Kette < laengere bei gleichem Praefix', () {
      expect(UpdateRepository.isNewer('1.0.0-beta.1', '1.0.0-beta'), isTrue);
      expect(UpdateRepository.isNewer('1.0.0-beta', '1.0.0-beta.1'), isFalse);
    });

    test('numerisch < alphanumerisch innerhalb Prerelease (SemVer 9.4)', () {
      expect(UpdateRepository.isNewer('1.0.0-alpha', '1.0.0-1'), isTrue);
      expect(UpdateRepository.isNewer('1.0.0-1', '1.0.0-alpha'), isFalse);
    });

    test('fehlender Patch == explizite Null', () {
      expect(UpdateRepository.isNewer('0.12', '0.12.0'), isFalse);
      expect(UpdateRepository.isNewer('0.12.1', '0.12'), isTrue);
    });

    test('leerer String wirft nie und ist nie neuer', () {
      expect(UpdateRepository.isNewer('', ''), isFalse);
      expect(UpdateRepository.isNewer('1.0.0', ''), isTrue);
      expect(UpdateRepository.isNewer('', '1.0.0'), isFalse);
    });

    test('nicht-numerischer Muell wirft nie', () {
      expect(
        () => UpdateRepository.isNewer('garbage', '1.0.0'),
        returnsNormally,
      );
      expect(UpdateRepository.isNewer('garbage', '1.0.0'), isFalse);
      // Kaputtes Core-Segment ('x') wird zu 0 -> '1.x.2' == '1.0.2' == [1,0,2],
      // also NICHT neuer. Ein echt hoeheres intaktes Segment gewinnt dagegen.
      expect(UpdateRepository.isNewer('1.x.2', '1.0.2'), isFalse);
      expect(UpdateRepository.isNewer('1.9.0', '1.x.0'), isTrue);
    });

    test('fuehrendes v/V wird defensiv toleriert', () {
      expect(UpdateRepository.isNewer('v0.12.1', 'v0.12.0'), isTrue);
      expect(UpdateRepository.isNewer('0.12.1', 'v0.12.1'), isFalse);
    });

    test('compare-Helfer ist konsistent mit isNewer', () {
      expect(
        UpdateRepository.compare('0.12.1-beta.1', '0.12.0-beta.3') > 0,
        isTrue,
      );
      expect(UpdateRepository.compare('0.12.0-beta.3', '0.12.0-beta.3'), 0);
      expect(UpdateRepository.compare('0.11.0', '0.12.0') < 0, isTrue);
    });

    test('reale Tag-Historie ist strikt aufsteigend geordnet', () {
      // aelteste -> neueste
      const asc = [
        '0.10.0-beta.5',
        '0.10.0-beta.6',
        '0.10.0-beta.7',
        '0.10.1-beta.1',
        '0.10.1-beta.2',
        '0.11.0-beta.1',
        '0.12.0-beta.1',
        '0.12.0-beta.2',
        '0.12.0-beta.3',
        '0.12.1-beta.1',
      ];
      for (var i = 1; i < asc.length; i++) {
        expect(
          UpdateRepository.isNewer(asc[i], asc[i - 1]),
          isTrue,
          reason: '${asc[i]} muss neuer als ${asc[i - 1]} sein',
        );
        expect(
          UpdateRepository.isNewer(asc[i - 1], asc[i]),
          isFalse,
          reason: '${asc[i - 1]} darf nicht neuer als ${asc[i]} sein',
        );
      }
    });
  });
}
