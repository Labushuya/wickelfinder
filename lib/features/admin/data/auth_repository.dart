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
  static const _kAutoLogin = 'admin_auto_login';

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedInNonAnon =>
      currentUser != null && (currentUser!.isAnonymous == false);

  /// True, wenn gerade nur eine anonyme (lazy) Session besteht.
  bool get isAnonymous => currentUser?.isAnonymous ?? false;

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  // --- Login (Admin wie normales Konto — identischer Passwort-Login) --------
  Future<void> signInAdmin(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  /// Alias fuer normale Konten (semantisch klarer; gleiche Wirkung).
  Future<void> signIn(String email, String password) =>
      signInAdmin(email, password);

  // --- Registrierung + Identity-Linking + Passwort-Reset --------------------

  /// Registrierung eines NEUEN Kontos (E-Mail-Bestaetigung aktiv ->
  /// res.session bleibt null bis zur Bestaetigung).
  Future<AuthResponse> signUp(String email, String password) =>
      _client.auth.signUp(email: email, password: password);

  /// Bestaetigungs-Code fuer eine unbestaetigte Registrierung erneut senden
  /// (z.B. wenn der urspruengliche Code verloren ging / der Flow abbrach).
  Future<void> resendSignupOtp(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email);

  /// Identity-Linking Schritt 1: an eine bestehende ANONYME Session eine
  /// E-Mail haengen (loest Bestaetigungs-/OTP-Mail aus). user_id bleibt gleich.
  Future<void> addEmailToAnonymous(String email) =>
      _client.auth.updateUser(UserAttributes(email: email));

  /// OTP-Bestaetigung (Code aus der Mail). type=emailChange beim
  /// Anonymous-Upgrade, type=signup bei Neu-Registrierung, type=recovery bei
  /// Passwort-Reset.
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
    required OtpType type,
  }) async {
    await _client.auth.verifyOTP(email: email, token: token, type: type);
  }

  /// Identity-Linking Schritt 3 bzw. Reset-Abschluss: Passwort setzen
  /// (erst NACH verifizierter E-Mail moeglich).
  Future<void> setPassword(String password) =>
      _client.auth.updateUser(UserAttributes(password: password));

  /// Passwort-Reset anfordern (Mail mit OTP/Link).
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email);

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
        await _storage.write(key: _kAutoLogin, value: 'true');
      } else {
        await clearSavedCredentials();
      }
    } catch (_) {
      // Secure-Storage kann auf manchen Android-OEM-Builds werfen -> Login
      // bleibt trotzdem gueltig, nur die Persistenz entfaellt (kein Crash).
    }
  }

  /// Gespeicherte Zugangsdaten (fuer Vorbefuellung des Login-Felds).
  /// Bleiben auch nach einem Logout erhalten.
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
      await _storage.delete(key: _kAutoLogin);
    } catch (_) {
      // Ignorieren (siehe signInAdminRemember).
    }
  }

  /// Beim Start: nur automatisch anmelden, wenn Auto-Login aktiv ist (der
  /// Nutzer hat sich nicht zwischenzeitlich abgemeldet) und gespeicherte
  /// Zugangsdaten existieren.
  Future<void> tryAutoLogin() async {
    if (isSignedInNonAnon) return;
    try {
      if (await _storage.read(key: _kAutoLogin) != 'true') return;
    } catch (_) {
      return;
    }
    final creds = await savedCredentials();
    if (creds == null) return;
    try {
      await signInAdmin(creds.email, creds.password);
    } catch (_) {
      // Ungueltig/geaendert -> Auto-Login abschalten, Felder bleiben aber.
      try {
        await _storage.delete(key: _kAutoLogin);
      } catch (_) {}
    }
  }

  /// Abmelden — beendet die Session und schaltet Auto-Login ab, LAESST aber
  /// E-Mail+Passwort gespeichert, damit die Login-Felder beim naechsten Mal
  /// vorbefuellt sind (schnelles erneutes Anmelden).
  Future<void> signOut() async {
    try {
      await _storage.delete(key: _kAutoLogin);
    } catch (_) {}
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

/// True, wenn ein ECHTES Konto (nicht nur anonym) eingeloggt ist. Zentrales
/// Gate fuer konto-pflichtige Aktionen (Pin erstellen/verwalten, Meine Pins).
final isLoggedInProvider = Provider<bool>((ref) {
  ref.watch(authChangesProvider);
  final repo = ref.watch(authRepositoryProvider);
  return repo?.isSignedInNonAnon ?? false;
});

/// Die aktuelle E-Mail des eingeloggten Kontos (null wenn anonym/kein Konto).
final currentAccountEmailProvider = Provider<String?>((ref) {
  ref.watch(authChangesProvider);
  final repo = ref.watch(authRepositoryProvider);
  final u = repo?.currentUser;
  if (u == null || u.isAnonymous) return null;
  return u.email;
});
