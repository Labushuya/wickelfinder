import 'package:flutter_test/flutter_test.dart';
import 'package:wickelfinder/features/community/domain/pending_photo.dart';

void main() {
  group('PendingPhoto.fromRow', () {
    test('parst alle Felder + signierte URL', () {
      final p = PendingPhoto.fromRow({
        'photo_id': 'p1',
        'place_ref': 'node/1',
        'storage_path': 'uid/node_1/1.jpg',
      }, 'https://signed/url');
      expect(p.photoId, 'p1');
      expect(p.placeRef, 'node/1');
      expect(p.storagePath, 'uid/node_1/1.jpg');
      expect(p.signedUrl, 'https://signed/url');
    });

    test('community place_ref', () {
      final p = PendingPhoto.fromRow({
        'photo_id': 'p2',
        'place_ref': 'community/abc',
        'storage_path': 'uid/community_abc/2.jpg',
      }, '');
      expect(p.placeRef, 'community/abc');
      expect(p.signedUrl, '');
    });
  });
}
