import 'package:supabase_flutter/supabase_flutter.dart';

/// Verwaltet die anonyme Identitaet — bewusst LAZY.
///
/// Eine anonyme Anmeldung (und damit ein Monthly-Active-User in Supabase)
/// entsteht erst, wenn der Nutzer zum ersten Mal etwas beitraegt (bewerten,
/// Platz melden, hinzufuegen). Reine Kartennutzung erzeugt KEINE Identitaet.
/// Das ist gleichermassen MAU-schonend (Free-Tier) und DSGVO-schonend
/// (keine Datenverarbeitung ohne aktive Nutzerhandlung).
///
/// `supabase_flutter` persistiert die Session selbst; ein einmal angelegter
/// anonymer Account bleibt ueber App-Neustarts erhalten.
class AnonSession {
  AnonSession(this._client);

  final SupabaseClient _client;

  /// Aktuelle User-ID, falls bereits eine (anonyme) Session existiert.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Stellt sicher, dass eine Identitaet existiert, und gibt ihre ID zurueck.
  /// Meldet anonym an, falls noch keine Session besteht.
  ///
  /// Vor JEDEM Schreibzugriff aufrufen. Nie beim App-Start.
  Future<String> ensureSignedIn() async {
    final existing = _client.auth.currentUser;
    if (existing != null) return existing.id;

    final res = await _client.auth.signInAnonymously();
    final user = res.user;
    if (user == null) {
      throw StateError('Anonyme Anmeldung fehlgeschlagen: kein User zurueck.');
    }
    return user.id;
  }
}
