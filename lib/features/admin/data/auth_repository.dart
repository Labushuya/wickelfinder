import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_init.dart';

/// Kapselt Admin-Login (echter E-Mail-Account) neben der anonymen Auth.
/// "Admin-Sein" wird serverseitig via RPC `is_admin` verifiziert — nie im
/// Client allein aus der E-Mail abgeleitet.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  // Verschluesselter Speicher (Android Keystore / iOS Keychain) fuer die
  // Admin-Zugangsdaten (nur wenn der Nutzer "Angemeldet bleiben" waehlt).
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kEmail = 'admin_email';
  static const _kPassword = 'admin_password';

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedInNonAnon =>
      currentUser != null && (currentUser!.isAnonymous == false);

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  Future<void> signInAdmin(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  /// Login + optional Zugangsdaten verschluesselt speichern (Auto-Login).
  Future<void> signInAdminRemember(
    String email,
    String password, {
    required bool remember,
  }) async {
    await signInAdmin(email, password);
    try {
      if (remember) {
        await _storage.write(key: _kEmail, value: email);
        await _storage.write(key: _kPassword, value: password);
      } else {
        await clearSavedCredentials();
      }
    } catch (_) {
      // Secure-Storage kann auf manchen Android-OEM-Builds werfen -> Login
      // bleibt trotzdem gueltig, nur die Persistenz entfaellt (kein Crash).
    }
  }

  Future<({String email, String password})?> savedCredentials() async {
    try {
      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);
      if (email == null || password == null) return null;
      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSavedCredentials() async {
    try {
      await _storage.delete(key: _kEmail);
      await _storage.delete(key: _kPassword);
    } catch (_) {
      // Ignorieren (siehe signInAdminRemember).
    }
  }

  /// Beim Start: wenn keine gueltige (Nicht-Anon-)Session, aber gespeicherte
  /// Zugangsdaten vorhanden sind -> stillschweigend neu anmelden.
  Future<void> tryAutoLogin() async {
    if (isSignedInNonAnon) return;
    final creds = await savedCredentials();
    if (creds == null) return;
    try {
      await signInAdmin(creds.email, creds.password);
    } catch (_) {
      // Ungueltig/geaendert -> gespeicherte Daten verwerfen.
      await clearSavedCredentials();
    }
  }

  /// Abmelden + gespeicherte Zugangsdaten loeschen.
  Future<void> signOut() async {
    await clearSavedCredentials();
    await _client.auth.signOut();
  }

  /// Serverseitige Admin-Pruefung. Anonyme/keine Session -> sofort false.
  Future<bool> checkIsAdmin() async {
    final u = currentUser;
    if (u == null || u.isAnonymous) return false;
    try {
      final res = await _client.rpc<dynamic>('is_admin');
      return res == true;
    } catch (_) {
      return false;
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  if (!SupabaseInit.isConfigured) return null;
  return AuthRepository(SupabaseInit.client);
});

/// Emitted bei jedem Login/Logout -> abhaengige Provider aktualisieren sich.
final authChangesProvider = StreamProvider<AuthState?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.changes;
});

/// True, wenn der aktuelle Nutzer serverseitig als Admin bestaetigt ist.
final isAdminProvider = FutureProvider<bool>((ref) async {
  ref.watch(authChangesProvider); // bei Login/Logout neu auswerten
  final repo = ref.watch(authRepositoryProvider);
  if (repo == null) return false;
  return repo.checkIsAdmin();
});
