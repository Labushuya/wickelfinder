import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_init.dart';

/// Kapselt die DSGVO-Betroffenenrechte: Datenexport (Art. 15/20) und
/// vollstaendige Loeschung inkl. Auth-Konto (Art. 17).
class AccountRepository {
  AccountRepository(this._client);
  final SupabaseClient _client;

  /// True, sobald eine (anonyme oder Admin-)Session existiert — nur dann gibt
  /// es ueberhaupt eigene Daten. Steuert die Sichtbarkeit der "Meine Daten"-UI.
  bool get hasIdentity => _client.auth.currentUser != null;

  /// Exportiert alle eigenen Daten als JSON-Datei und oeffnet sie (Teilen/
  /// Ansehen ueber den System-Dialog). Gibt den Dateipfad zurueck.
  Future<String> exportMyDataToFile() async {
    final data = await _client.rpc<Map<String, dynamic>>('export_my_data');
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File('${dir.path}/wickelfinder-meine-daten-$stamp.json');
    await file.writeAsString(pretty);
    await OpenFilex.open(file.path);
    return file.path;
  }

  /// Loescht ALLE eigenen Daten UND das Auth-Konto (via Edge Function
  /// 'delete-account', die service_role-gesichert delete_my_data +
  /// auth.admin.deleteUser ausfuehrt). Danach lokale Session beenden.
  Future<void> deleteMyAccount() async {
    final res = await _client.functions.invoke('delete-account');
    final ok = (res.data is Map) && (res.data['ok'] == true);
    if (!ok) {
      throw StateError('Konto-Loeschung fehlgeschlagen (${res.status}).');
    }
    // Lokale Session verwerfen -> App faellt in den "nur Karte"-Zustand.
    await _client.auth.signOut();
  }
}

final accountRepositoryProvider = Provider<AccountRepository?>((ref) {
  if (!SupabaseInit.isConfigured) return null;
  return AccountRepository(SupabaseInit.client);
});
