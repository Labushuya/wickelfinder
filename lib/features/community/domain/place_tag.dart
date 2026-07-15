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
  sink('sink', 'Waschbecken vorhanden'),
  // Zugangs-Bedingungs-Tags (Migration 11).
  guestsOnly('guests_only', 'Nur für Gäste/Kunden'),
  entryFee('entry_fee', 'Eintritt nötig'),
  freeAccess('free_access', 'Frei zugänglich'),
  askStaff('ask_staff', 'Schlüssel/Personal fragen');

  const PlaceTag(this.wire, this.label);

  /// Wert wie im Postgres-Enum (fuer den RPC-Aufruf).
  final String wire;

  /// Anzeige-Label (Deutsch).
  final String label;

  /// Der sich gegenseitig ausschliessende Gegen-Tag, falls vorhanden.
  /// Wird beim Auswaehlen automatisch abgewaehlt (kein Widerspruch moeglich).
  PlaceTag? get opposite => switch (this) {
    freeOfCharge => paid,
    paid => freeOfCharge,
    disposal => noDisposal,
    noDisposal => disposal,
    largeSurface => cramped,
    cramped => largeSurface,
    freeAccess => entryFee,
    entryFee => freeAccess,
    _ => null,
  };

  /// Zugangs-Bedingungs-Tags (getrennter Block im Bewertungs-/Melde-UI).
  static const accessTags = [guestsOnly, entryFee, freeAccess, askStaff];

  /// Eigenschafts-Tags (Sauberkeit, Ausstattung …) ohne die Zugangs-Tags.
  static List<PlaceTag> get propertyTags =>
      values.where((t) => !accessTags.contains(t)).toList();
}
