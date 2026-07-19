import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/domain/admin_place_feedback.dart';

void main() {
  group('AdminPlaceFeedback.fromJson', () {
    test('parst alle Zaehler', () {
      final f = AdminPlaceFeedback.fromJson({
        'not_present_count': 3,
        'closed_count': 1,
        'wrong_location_count': 2,
        'other_count': 0,
        'confirm_count': 5,
        'rating_count': 8,
      });
      expect(f.notPresent, 3);
      expect(f.closed, 1);
      expect(f.wrongLocation, 2);
      expect(f.other, 0);
      expect(f.confirmed, 5);
      expect(f.rated, 8);
      expect(f.hasAny, isTrue);
    });

    test('fehlende Felder -> 0', () {
      final f = AdminPlaceFeedback.fromJson({});
      expect(f.notPresent, 0);
      expect(f.confirmed, 0);
      expect(f.rated, 0);
      expect(f.hasAny, isFalse);
    });

    test('empty hat keine Eintraege', () {
      expect(AdminPlaceFeedback.empty.hasAny, isFalse);
    });
  });
}
