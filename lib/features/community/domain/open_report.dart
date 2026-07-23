/// Eine offene Inhaltsmeldung fuer die Admin-Pruefung (Rueckgabe von
/// `admin_open_reports`). Kann sich auf ein Foto beziehen ([photoId] gesetzt)
/// oder auf den Platz allgemein.
class OpenReport {
  const OpenReport({
    required this.reportId,
    required this.placeRef,
    required this.kind,
    this.photoId,
    this.storagePath,
    this.signedUrl,
  });

  final String reportId;
  final String placeRef;

  /// Melde-Grund: pii | abuse | spam | other.
  final String kind;

  /// Foto-ID, falls die Meldung ein Foto betrifft (sonst null).
  final String? photoId;

  /// Storage-Pfad des gemeldeten Fotos (zum Loeschen des Objekts).
  final String? storagePath;

  /// Signierte Vorschau-URL des gemeldeten Fotos (falls vorhanden).
  final String? signedUrl;

  bool get isPhoto => photoId != null;

  /// Deutsches Label fuer den Grund.
  String get kindLabel => switch (kind) {
    'pii' => 'Personen / persönliche Daten',
    'abuse' => 'Anstößig / unangemessen',
    'spam' => 'Spam / Werbung',
    _ => 'Sonstiges',
  };

  static OpenReport fromRow(Map<String, dynamic> row, String? signedUrl) =>
      OpenReport(
        reportId: row['report_id'] as String,
        placeRef: row['place_ref'] as String,
        kind: row['kind'] as String? ?? 'other',
        photoId: row['photo_id'] as String?,
        storagePath: row['storage_path'] as String?,
        signedUrl: signedUrl,
      );
}
