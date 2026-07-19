import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/domain/place_flag.dart';

void main() {
  group('FlagReason', () {
    test('wire-Werte entsprechen dem Postgres-Enum flag_reason', () {
      expect(FlagReason.notPresent.wire, 'not_present');
      expect(FlagReason.closed.wire, 'closed');
      expect(FlagReason.wrongLocation.wire, 'wrong_location');
    });

    test('bietet genau drei Gruende an (kein "other")', () {
      expect(FlagReason.values.length, 3);
      expect(FlagReason.values.map((r) => r.wire), isNot(contains('other')));
    });

    test('jeder Grund hat ein nicht-leeres Label', () {
      for (final r in FlagReason.values) {
        expect(r.label, isNotEmpty);
      }
    });
  });
}
