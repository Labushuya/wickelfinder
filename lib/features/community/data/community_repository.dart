import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/place_stats.dart';
import '../domain/place_tag.dart';
import 'anon_session.dart';

/// Fehler aus einem Community-RPC, mit maschinenlesbarem [code]
/// (z. B. 'rate_limit', 'self_rating', 'auth_required').
class CommunityException implements Exception {
  const CommunityException(this.code, [this.message]);
  final String code;
  final String? message;

  /// Nutzerfreundliche deutsche Meldung fuer bekannte Fehlercodes.
  String get userMessage => switch (code) {
    'rate_limit' => 'Zu viele Bewertungen in kurzer Zeit. Bitte später erneut.',
    'self_rating' => 'Eigene Plätze können nicht bewertet werden.',
    'auth_required' => 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.',
    'bad_stars' => 'Ungültige Bewertung.',
    'bad_ref' => 'Ungültiger Platz.',
    _ => 'Aktion fehlgeschlagen. Bitte später erneut versuchen.',
  };

  @override
  String toString() => 'CommunityException($code): ${message ?? ''}';
}

/// Kapselt allen Community-Backend-Zugriff. Schreibt NIE direkt in Tabellen —
/// ausschliesslich ueber SECURITY-DEFINER-RPCs (submit_rating, stats_for).
class CommunityRepository {
  CommunityRepository(this._client) : _session = AnonSession(_client);

  final SupabaseClient _client;
  final AnonSession _session;

  /// Laedt Aggregat-Statistiken fuer die gegebenen place_refs (max 200).
  /// Lesen erfordert keine Anmeldung (anon darf stats_for ausfuehren).
  /// Refs ohne Feedback fehlen im Ergebnis -> Aufrufer faellt auf [PlaceStats.empty].
  Future<Map<String, PlaceStats>> statsFor(List<String> refs) async {
    if (refs.isEmpty) return const {};
    final capped = refs.length > 200 ? refs.sublist(0, 200) : refs;
    final rows = await _client.rpc<List<dynamic>>(
      'stats_for',
      params: {'refs': capped},
    );
    final result = <String, PlaceStats>{};
    for (final row in rows) {
      final stats = PlaceStats.fromJson((row as Map).cast<String, dynamic>());
      result[stats.placeRef] = stats;
    }
    return result;
  }

  /// Sendet eine Bewertung (1-5 Sterne + optionale Tags). Meldet lazy anonym an.
  Future<void> submitRating({
    required String placeRef,
    required int stars,
    Set<PlaceTag> tags = const {},
  }) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>(
        'submit_rating',
        params: {
          'p_ref': placeRef,
          'p_stars': stars,
          'p_tags': tags.map((t) => t.wire).toList(),
        },
      );
    } on PostgrestException catch (e) {
      // RPC-raise landet in message/code -> auf bekannte Codes mappen.
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Zieht den 'raise exception <code>'-Text aus der Postgres-Fehlermeldung.
  static String _extractCode(String message) {
    for (final code in [
      'rate_limit',
      'self_rating',
      'auth_required',
      'bad_stars',
      'bad_ref',
    ]) {
      if (message.contains(code)) return code;
    }
    return 'unknown';
  }
}
