import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/domain/open_report.dart';

void main() {
  group('OpenReport.fromRow', () {
    test('parst eine Foto-Meldung', () {
      final r = OpenReport.fromRow({
        'report_id': 'r1',
        'place_ref': 'node/1',
        'kind': 'pii',
        'photo_id': 'p1',
        'storage_path': 'uid/node_1/1.jpg',
      }, 'https://signed/url');
      expect(r.reportId, 'r1');
      expect(r.placeRef, 'node/1');
      expect(r.kind, 'pii');
      expect(r.photoId, 'p1');
      expect(r.storagePath, 'uid/node_1/1.jpg');
      expect(r.signedUrl, 'https://signed/url');
      expect(r.isPhoto, isTrue);
      expect(r.kindLabel, 'Personen / persönliche Daten');
    });

    test('Meldung ohne Foto (nur Platz)', () {
      final r = OpenReport.fromRow({
        'report_id': 'r2',
        'place_ref': 'community/abc',
        'kind': 'spam',
      }, null);
      expect(r.photoId, isNull);
      expect(r.storagePath, isNull);
      expect(r.signedUrl, isNull);
      expect(r.isPhoto, isFalse);
      expect(r.kindLabel, 'Spam / Werbung');
    });

    test('fehlender/unbekannter Grund -> Sonstiges', () {
      final r = OpenReport.fromRow({
        'report_id': 'r3',
        'place_ref': 'node/9',
        'kind': null,
      }, null);
      expect(r.kind, 'other');
      expect(r.kindLabel, 'Sonstiges');
    });

    test('kind abuse -> deutsches Label', () {
      final r = OpenReport.fromRow({
        'report_id': 'r4',
        'place_ref': 'node/9',
        'kind': 'abuse',
      }, null);
      expect(r.kindLabel, 'Anstößig / unangemessen');
    });
  });
}
