/// Ein wartendes Foto in der Admin-Freigabe (Rueckgabe von `admin_pending_photos`).
class PendingPhoto {
  const PendingPhoto({
    required this.photoId,
    required this.placeRef,
    required this.storagePath,
    required this.signedUrl,
  });

  final String photoId;
  final String placeRef;
  final String storagePath;

  /// Signierte Vorschau-URL (Admin darf pending Objekte lesen).
  final String signedUrl;

  static PendingPhoto fromRow(Map<String, dynamic> row, String signedUrl) =>
      PendingPhoto(
        photoId: row['photo_id'] as String,
        placeRef: row['place_ref'] as String,
        storagePath: row['storage_path'] as String,
        signedUrl: signedUrl,
      );
}
