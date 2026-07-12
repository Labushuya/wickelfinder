/// Die anklickbaren Attribut-Tags einer Bewertung.
/// Spiegelt exakt das Postgres-Enum `place_tag` (siehe Migration 0004).
enum PlaceTag {
  clean('clean', 'Sauber'),
  largeSurface('large_surface', 'Große Wickelfläche'),
  padding('padding', 'Unterlage vorhanden'),
  freeOfCharge('free_of_charge', 'Kostenlos'),
  paid('paid', 'Kostenpflichtig'),
  disposal('disposal', 'Windeleimer / Entsorgung'),
  noDisposal('no_disposal', 'Keine Entsorgung'),
  cramped('cramped', 'Eng / wenig Platz'),
  separateRoom('separate_room', 'Separater Raum'),
  sink('sink', 'Waschbecken vorhanden');

  const PlaceTag(this.wire, this.label);

  /// Wert wie im Postgres-Enum (fuer den RPC-Aufruf).
  final String wire;

  /// Anzeige-Label (Deutsch).
  final String label;
}
