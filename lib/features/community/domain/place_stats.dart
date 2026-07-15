import 'place_tag.dart';

/// Aggregierte Community-Statistik zu einem Platz (Rueckgabe von `stats_for`).
///
/// Enthaelt bewusst KEINE Rohdaten (keine user_id, keine Einzelbewertungen) —
/// nur die vom Server berechneten Aggregate.
class PlaceStats {
  const PlaceStats({
    required this.placeRef,
    required this.ratingCount,
    required this.avgStars,
    required this.flagCount,
    required this.confirmCount,
    required this.isQuestionable,
    this.tagCounts = const {},
  });

  final String placeRef;
  final int ratingCount;

  /// Bayesian-gewichteter Sternschnitt; null wenn noch keine Bewertung.
  final double? avgStars;
  final int flagCount;
  final int confirmCount;

  /// True, wenn genug unabhaengige "nicht vorhanden"-Meldungen vorliegen
  /// -> UI graut den Platz aus und sortiert ihn ans Ende (Soft-Hide).
  final bool isQuestionable;

  /// Wie oft jeder Tag von der Community vergeben wurde (Konsens-Basis).
  /// Leer, wenn noch keine getaggte Bewertung vorliegt.
  final Map<PlaceTag, int> tagCounts;

  static PlaceStats fromJson(Map<String, dynamic> j) {
    final avg = j['avg_stars'];
    return PlaceStats(
      placeRef: j['place_ref'] as String,
      ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      avgStars: avg == null ? null : (avg as num).toDouble(),
      flagCount: (j['flag_count'] as num?)?.toInt() ?? 0,
      confirmCount: (j['confirm_count'] as num?)?.toInt() ?? 0,
      isQuestionable: j['is_questionable'] as bool? ?? false,
      tagCounts: _parseTagCounts(j['tag_counts']),
    );
  }

  /// Wandelt das jsonb-Objekt {wire: count} in Map<PlaceTag,int>. Unbekannte
  /// wire-Keys (z. B. aus neueren Enum-Werten) werden ignoriert.
  static Map<PlaceTag, int> _parseTagCounts(Object? raw) {
    if (raw is! Map) return const {};
    final result = <PlaceTag, int>{};
    for (final entry in raw.entries) {
      final wire = entry.key as String?;
      final count = (entry.value as num?)?.toInt();
      if (wire == null || count == null) continue;
      for (final tag in PlaceTag.values) {
        if (tag.wire == wire) {
          result[tag] = count;
          break;
        }
      }
    }
    return result;
  }

  /// Leere Statistik fuer einen Platz ohne jegliches Community-Feedback.
  static PlaceStats empty(String placeRef) => PlaceStats(
    placeRef: placeRef,
    ratingCount: 0,
    avgStars: null,
    flagCount: 0,
    confirmCount: 0,
    isQuestionable: false,
    tagCounts: const {},
  );
}
