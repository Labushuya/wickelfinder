import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_init.dart';

/// Kapselt Admin-Login (echter E-Mail-Account) neben der anonymen Auth.
/// "Admin-Sein" wird serverseitig via RPC `is_admin` verifiziert — nie im
/// Client allein aus der E-Mail abgeleitet.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedInNonAnon =>
      currentUser != null && (currentUser!.isAnonymous == false);

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  Future<void> signInAdmin(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();

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
