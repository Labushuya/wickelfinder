/// Pruefungsbeduerftige Zaehler eines Platzes fuer die Admin-Ansicht
/// (Rueckgabe von `admin_moderation_counts`). Backt das Highlight in der
/// „Alle Pins [Admin]"-Liste.
class ModerationCounts {
  const ModerationCounts({
    required this.pendingPhotos,
    required this.openReports,
  });

  final int pendingPhotos;
  final int openReports;

  bool get needsReview => pendingPhotos > 0 || openReports > 0;

  static ModerationCounts fromRow(Map<String, dynamic> row) => ModerationCounts(
    pendingPhotos: (row['pending_photos'] as num?)?.toInt() ?? 0,
    openReports: (row['open_reports'] as num?)?.toInt() ?? 0,
  );

  static const empty = ModerationCounts(pendingPhotos: 0, openReports: 0);
}
