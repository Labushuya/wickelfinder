/// Rohe Melde-/Bestaetigungs-Zaehler eines Platzes fuer die Admin-Ansicht
/// (Rueckgabe von `admin_place_feedback`). Enthaelt ALLE Meldungen, auch von
/// Accounts juenger als 48h — anders als die oeffentliche `place_stats`-Sicht.
class AdminPlaceFeedback {
  const AdminPlaceFeedback({
    required this.notPresent,
    required this.closed,
    required this.wrongLocation,
    required this.other,
    required this.confirmed,
    required this.rated,
  });

  final int notPresent;
  final int closed;
  final int wrongLocation;
  final int other;
  final int confirmed;
  final int rated;

  /// True, wenn ueberhaupt Feedback vorliegt (sonst Block ausblenden).
  bool get hasAny =>
      notPresent > 0 ||
      closed > 0 ||
      wrongLocation > 0 ||
      other > 0 ||
      confirmed > 0 ||
      rated > 0;

  static AdminPlaceFeedback fromJson(Map<String, dynamic> j) =>
      AdminPlaceFeedback(
        notPresent: (j['not_present_count'] as num?)?.toInt() ?? 0,
        closed: (j['closed_count'] as num?)?.toInt() ?? 0,
        wrongLocation: (j['wrong_location_count'] as num?)?.toInt() ?? 0,
        other: (j['other_count'] as num?)?.toInt() ?? 0,
        confirmed: (j['confirm_count'] as num?)?.toInt() ?? 0,
        rated: (j['rating_count'] as num?)?.toInt() ?? 0,
      );

  static const empty = AdminPlaceFeedback(
    notPresent: 0,
    closed: 0,
    wrongLocation: 0,
    other: 0,
    confirmed: 0,
    rated: 0,
  );
}
