/// Moderationsstatus eines Fotos (spiegelt das Postgres-CHECK).
enum PhotoModeration { pending, approved, rejected }

/// Ein Foto zu einem Platz (Rueckgabe von `photos_for`). Der Client haelt die
/// frisch signierte Anzeige-URL; roher [storagePath] wird fuer Loeschen/Signieren
/// gebraucht.
class PlacePhoto {
  const PlacePhoto({
    required this.id,
    required this.placeRef,
    required this.storagePath,
    required this.moderation,
    required this.isMine,
    required this.signedUrl,
  });

  final String id;
  final String placeRef;
  final String storagePath;
  final PhotoModeration moderation;

  /// True, wenn das Foto dem aktuellen Nutzer gehoert.
  final bool isMine;

  /// Signierte, zeitlich begrenzte Anzeige-URL (leer, falls Signieren scheiterte).
  final String signedUrl;

  bool get isApproved => moderation == PhotoModeration.approved;
  bool get isPending => moderation == PhotoModeration.pending;

  static PhotoModeration _moderationFromWire(String? wire) => switch (wire) {
    'approved' => PhotoModeration.approved,
    'rejected' => PhotoModeration.rejected,
    _ => PhotoModeration.pending,
  };

  /// Baut aus einer `photos_for`-Zeile + signierter URL ein [PlacePhoto].
  static PlacePhoto fromRow(Map<String, dynamic> row, String signedUrl) =>
      PlacePhoto(
        id: row['photo_id'] as String,
        placeRef: row['place_ref'] as String,
        storagePath: row['storage_path'] as String,
        moderation: _moderationFromWire(row['moderation_state'] as String?),
        isMine: row['is_mine'] as bool? ?? false,
        signedUrl: signedUrl,
      );
}
