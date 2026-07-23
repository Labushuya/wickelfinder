import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/domain/place_photo.dart';
import 'package:wickelfinder/features/community/domain/moderation_counts.dart';

void main() {
  group('PlacePhoto.fromRow', () {
    test('parst eine approved-Zeile', () {
      final p = PlacePhoto.fromRow({
        'photo_id': 'p1',
        'place_ref': 'node/1',
        'storage_path': 'uid/node_1/1.jpg',
        'moderation_state': 'approved',
        'is_mine': false,
      }, 'https://signed/url');
      expect(p.id, 'p1');
      expect(p.placeRef, 'node/1');
      expect(p.moderation, PhotoModeration.approved);
      expect(p.isApproved, isTrue);
      expect(p.isPending, isFalse);
      expect(p.isMine, isFalse);
      expect(p.signedUrl, 'https://signed/url');
    });

    test('pending + is_mine', () {
      final p = PlacePhoto.fromRow({
        'photo_id': 'p2',
        'place_ref': 'community/abc',
        'storage_path': 'uid/community_abc/2.jpg',
        'moderation_state': 'pending',
        'is_mine': true,
      }, '');
      expect(p.isPending, isTrue);
      expect(p.isMine, isTrue);
    });

    test('unbekannter Status -> pending (sicherer Default)', () {
      final p = PlacePhoto.fromRow({
        'photo_id': 'p3',
        'place_ref': 'node/9',
        'storage_path': 'x',
        'moderation_state': null,
      }, '');
      expect(p.moderation, PhotoModeration.pending);
      expect(p.isMine, isFalse);
    });
  });

  group('ModerationCounts', () {
    test('needsReview true bei offenen Punkten', () {
      const a = ModerationCounts(pendingPhotos: 2, openReports: 0);
      const b = ModerationCounts(pendingPhotos: 0, openReports: 1);
      expect(a.needsReview, isTrue);
      expect(b.needsReview, isTrue);
      expect(ModerationCounts.empty.needsReview, isFalse);
    });

    test('fromRow parst Zaehler', () {
      final c = ModerationCounts.fromRow({
        'pending_photos': 3,
        'open_reports': 5,
      });
      expect(c.pendingPhotos, 3);
      expect(c.openReports, 5);
    });
  });
}
