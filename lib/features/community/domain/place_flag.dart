/// Melde-Grund fuer "Platz existiert nicht (mehr)". Spiegelt das Postgres-Enum
/// `flag_reason` — der Wert `other` wird bewusst NICHT angeboten.
///
/// Getrennte Wirkung (serverseitig in place_stats):
///  - [notPresent] + [closed] -> Soft-Hide ("Existenz fraglich").
///  - [wrongLocation]         -> eigener Hinweis "Standort ungenau", KEIN
///                               Ausblenden.
enum FlagReason {
  notPresent('not_present', 'Nicht vorhanden'),
  closed('closed', 'Dauerhaft geschlossen'),
  wrongLocation('wrong_location', 'Falscher Ort');

  const FlagReason(this.wire, this.label);

  /// Wire-Wert fuer das Postgres-Enum `flag_reason`.
  final String wire;

  /// Deutsches Label fuer die Auswahl.
  final String label;
}
