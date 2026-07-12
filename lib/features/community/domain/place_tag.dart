/// Die vier Attribut-Tags, die ein Nutzer einer Bewertung mitgeben kann.
/// Spiegelt exakt das Postgres-Enum `place_tag`.
enum PlaceTag {
  clean('clean', 'Sauber'),
  largeSurface('large_surface', 'Große Wickelfläche'),
  padding('padding', 'Unterlage vorhanden'),
  freeOfCharge('free_of_charge', 'Kostenlos');

  const PlaceTag(this.wire, this.label);

  /// Wert wie im Postgres-Enum (fuer den RPC-Aufruf).
  final String wire;

  /// Anzeige-Label (Deutsch).
  final String label;
}
