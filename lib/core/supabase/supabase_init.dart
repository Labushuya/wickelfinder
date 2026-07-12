import 'package:supabase_flutter/supabase_flutter.dart';

/// Initialisiert den Supabase-Client aus Compile-Zeit-Umgebungsvariablen.
///
/// URL und anon-key werden per `--dart-define` beim Build injiziert (im CI aus
/// GitHub-Secrets). Der anon-key ist client-safe; die eigentliche Absicherung
/// leistet Row-Level-Security in der Datenbank.
///
/// Die anonyme Anmeldung erfolgt NICHT hier, sondern lazy beim ersten
/// Schreibversuch (siehe `anon_session.dart`) — reine Kartennutzung erzeugt so
/// keine Identitaet und keinen Monthly-Active-User.
abstract final class SupabaseInit {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True, wenn beide Werte gesetzt sind. Erlaubt es der App, ohne Backend
  /// (z. B. lokaler Debug-Build ohne Defines) nur die Karte anzuzeigen.
  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  static Future<void> ensureInitialized() async {
    if (!isConfigured) return;
    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }

  /// Zugriff auf den initialisierten Client. Wirft, wenn nicht konfiguriert —
  /// Aufrufer aus dem Community-Layer pruefen vorher [isConfigured].
  static SupabaseClient get client => Supabase.instance.client;
}
