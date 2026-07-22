import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/domain/changing_place.dart';
import '../domain/admin_place_feedback.dart';
import '../domain/place_flag.dart';
import '../domain/place_stats.dart';
import '../domain/place_tag.dart';
import 'anon_session.dart';

/// Die eigene Bewertung eines Platzes (Sterne + gewaehlte Tags).
class MyRating {
  const MyRating({required this.stars, required this.tags});
  final int stars;
  final Set<PlaceTag> tags;
}

/// Eine eigene Bewertung MIT ihrem place_ref und (optional) gespeicherten
/// Koordinaten — Grundlage der "Meine Bewertungen"-Liste.
class MyRatingEntry {
  const MyRatingEntry({
    required this.placeRef,
    required this.rating,
    this.lat,
    this.lon,
  });
  final String placeRef;
  final MyRating rating;
  final double? lat;
  final double? lon;

  /// True, wenn Koordinaten gespeichert sind -> Karten-Sprung moeglich.
  bool get hasCoords => lat != null && lon != null;
}

/// Fehler aus einem Community-RPC, mit maschinenlesbarem [code]
/// (z. B. 'rate_limit', 'self_rating', 'auth_required').
class CommunityException implements Exception {
  const CommunityException(this.code, [this.message]);
  final String code;
  final String? message;

  /// Nutzerfreundliche deutsche Meldung fuer bekannte Fehlercodes.
  String get userMessage => switch (code) {
    'rate_limit' => 'Zu viele Beiträge in kurzer Zeit. Bitte später erneut.',
    'geo_rate_limit' => 'Hier hast du kürzlich schon einen Platz gemeldet.',
    'geo_cluster_cap' => 'In diesem Bereich gibt es bereits viele Einträge.',
    'self_rating' => 'Eigene Plätze können nicht bewertet werden.',
    'self_flag' => 'Eigene Plätze können nicht gemeldet werden.',
    'auth_required' => 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.',
    'bad_stars' => 'Ungültige Bewertung.',
    'too_many_tags' => 'Bitte höchstens 10 Eigenschaften auswählen.',
    'bad_ref' => 'Ungültiger Platz.',
    'bad_coords' => 'Ungültige Koordinaten.',
    'name_too_long' || 'hint_too_long' => 'Eingabe zu lang.',
    'not_owner_or_missing' => 'Dieser Platz gehört dir nicht (mehr).',
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
  /// [lat]/[lon] optional: die Koordinaten des Platzes werden mitgespeichert,
  /// damit "Meine Bewertungen" spaeter zum Platz zurueckfuehren kann.
  Future<void> submitRating({
    required String placeRef,
    required int stars,
    Set<PlaceTag> tags = const {},
    double? lat,
    double? lon,
  }) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>(
        'submit_rating',
        params: {
          'p_ref': placeRef,
          'p_stars': stars,
          'p_tags': tags.map((t) => t.wire).toList(),
          'p_lat': lat,
          'p_lon': lon,
        },
      );
    } on PostgrestException catch (e) {
      // RPC-raise landet in message/code -> auf bekannte Codes mappen.
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Meldet einen Platz als "nicht (mehr) vorhanden" / geschlossen / falscher
  /// Ort. Anonym moeglich (lazy Sign-In), wie Bewerten. Upsert pro Nutzer.
  Future<void> submitFlag({
    required String placeRef,
    required FlagReason reason,
  }) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>(
        'submit_flag',
        params: {'p_ref': placeRef, 'p_reason': reason.wire},
      );
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Bestaetigt, dass ein Platz DOCH vorhanden ist (macht Soft-Hide reversibel).
  /// Anonym moeglich (lazy Sign-In). Upsert pro Nutzer.
  Future<void> confirmPresent({required String placeRef}) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>('confirm_present', params: {'p_ref': placeRef});
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Rohe Melde-/Bestaetigungs-Zaehler eines Platzes (nur Admin; serverseitig
  /// via is_admin() geprueft). Ohne Adminrecht -> null (RPC wirft admin_required).
  Future<AdminPlaceFeedback?> adminPlaceFeedback(String placeRef) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'admin_place_feedback',
        params: {'p_ref': placeRef},
      );
      if (rows.isEmpty) return AdminPlaceFeedback.empty;
      return AdminPlaceFeedback.fromJson(
        (rows.first as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      // Kein Adminrecht / kein Backend -> Block wird ausgeblendet.
      return null;
    }
  }

  /// Liest die EIGENE Bewertung fuer einen Platz (RLS: nur eigene Zeile).
  /// Null, wenn noch nicht bewertet oder keine Session.
  Future<MyRating?> myRating(String placeRef) async {
    if (_session.currentUserId == null) return null;
    try {
      final rows = await _client
          .from('ratings')
          .select('stars, tags')
          .eq('place_ref', placeRef)
          .eq('user_id', _session.currentUserId!)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final wireTags = (row['tags'] as List?)?.cast<String>() ?? const [];
      return MyRating(
        stars: (row['stars'] as num).toInt(),
        tags: {
          for (final w in wireTags)
            ...PlaceTag.values.where((t) => t.wire == w),
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Liest die EIGENE "nicht vorhanden"-Meldung fuer einen Platz (RLS: nur
  /// eigene Zeile). Gibt den gewaehlten Grund zurueck, null wenn nicht gemeldet.
  Future<FlagReason?> myFlag(String placeRef) async {
    if (_session.currentUserId == null) return null;
    try {
      final rows = await _client
          .from('flags')
          .select('reason')
          .eq('place_ref', placeRef)
          .eq('user_id', _session.currentUserId!)
          .limit(1);
      if (rows.isEmpty) return null;
      final wire = rows.first['reason'] as String?;
      for (final r in FlagReason.values) {
        if (r.wire == wire) return r;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True, wenn der Nutzer diesen Platz bereits als "vorhanden" bestaetigt hat.
  Future<bool> myConfirmation(String placeRef) async {
    if (_session.currentUserId == null) return false;
    try {
      final rows = await _client
          .from('confirmations')
          .select('place_ref')
          .eq('place_ref', placeRef)
          .eq('user_id', _session.currentUserId!)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Laedt ALLE eigenen Bewertungen (RLS: nur eigene Zeilen). Neueste zuerst.
  /// Enthaelt place_ref + Sterne/Tags + (optional) gespeicherte Koordinaten.
  ///
  /// Robust gegen ein Backend OHNE Migration 0017: schlaegt die Abfrage mit
  /// lat/lon fehl (Spalten fehlen), wird ohne Koordinaten erneut geladen — die
  /// Liste funktioniert dann trotzdem, nur ohne Karten-Sprung.
  Future<List<MyRatingEntry>> myRatings() async {
    if (_session.currentUserId == null) return const [];
    try {
      final rows = await _client
          .from('ratings')
          .select('place_ref, stars, tags, lat, lon')
          .order('updated_at', ascending: false);
      return [for (final row in rows) _entryFromRow(row, withCoords: true)];
    } on PostgrestException {
      // Wahrscheinlich fehlen lat/lon (Migration 0017 noch nicht ausgefuehrt)
      // -> ohne Koordinaten erneut versuchen.
      try {
        final rows = await _client
            .from('ratings')
            .select('place_ref, stars, tags')
            .order('updated_at', ascending: false);
        return [for (final row in rows) _entryFromRow(row, withCoords: false)];
      } catch (_) {
        return const [];
      }
    } catch (_) {
      return const [];
    }
  }

  MyRatingEntry _entryFromRow(dynamic row, {required bool withCoords}) {
    return MyRatingEntry(
      placeRef: row['place_ref'] as String,
      rating: MyRating(
        stars: (row['stars'] as num).toInt(),
        tags: {
          for (final w in (row['tags'] as List?)?.cast<String>() ?? const [])
            ...PlaceTag.values.where((t) => t.wire == w),
        },
      ),
      lat: withCoords ? (row['lat'] as num?)?.toDouble() : null,
      lon: withCoords ? (row['lon'] as num?)?.toDouble() : null,
    );
  }

  /// Laedt alle sichtbaren Community-Plaetze (aus community_places_public)
  /// als [ChangingPlace] mit `source = PlaceSource.community`. Lesen ohne Login.
  Future<List<ChangingPlace>> communityPlaces() async {
    final rows = await _client
        .from('community_places_public')
        .select('id, name, location_hint, wheelchair, fee, fee_mode, lat, lon');
    return [
      for (final row in rows)
        ChangingPlace(
          id: row['id'] as String,
          location: LatLng(
            (row['lat'] as num).toDouble(),
            (row['lon'] as num).toDouble(),
          ),
          name: row['name'] as String?,
          wheelchairAccessible: row['wheelchair'] as bool?,
          fee: row['fee'] as bool?,
          feeMode: FeeMode.fromWire(row['fee_mode'] as String?),
          locationHint: row['location_hint'] as String?,
          source: PlaceSource.community,
        ),
    ];
  }

  /// Fuegt einen neuen Community-Platz hinzu. Meldet lazy anonym an.
  /// Gibt die neue place_ref zurueck.
  Future<String> addPlace({
    required double lat,
    required double lon,
    String? name,
    String? locationHint,
    bool? wheelchair,
    bool? fee,
    FeeMode? feeMode,
  }) async {
    await _session.ensureSignedIn();
    try {
      final ref = await _client.rpc<String>(
        'add_community_place',
        params: {
          'p_lat': lat,
          'p_lon': lon,
          'p_name': name,
          'p_hint': locationHint,
          'p_wheelchair': wheelchair,
          'p_fee': fee,
          'p_fee_mode': feeMode?.wire,
        },
      );
      return ref;
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Laedt die eigenen Community-Plaetze (View my_community_places, RLS:
  /// created_by = auth.uid()). Ohne bestehende Session -> leere Liste.
  Future<List<ChangingPlace>> myPlaces() async {
    if (_session.currentUserId == null) return const [];
    final rows = await _client
        .from('my_community_places')
        .select('id, name, location_hint, wheelchair, fee, fee_mode, lat, lon')
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        ChangingPlace(
          id: row['id'] as String,
          location: LatLng(
            (row['lat'] as num).toDouble(),
            (row['lon'] as num).toDouble(),
          ),
          name: row['name'] as String?,
          wheelchairAccessible: row['wheelchair'] as bool?,
          fee: row['fee'] as bool?,
          feeMode: FeeMode.fromWire(row['fee_mode'] as String?),
          locationHint: row['location_hint'] as String?,
          source: PlaceSource.community,
        ),
    ];
  }

  /// Laedt ALLE Community-Plaetze (nur Admin; via admin_list_places mit
  /// Welt-BBox). Enthaelt auch versteckte/fremde Pins. Ohne Adminrecht wirft
  /// der Server 'admin_required' -> hier als leere Liste behandelt.
  Future<List<ChangingPlace>> adminAllPlaces() async {
    if (_session.currentUserId == null) return const [];
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'admin_list_places',
        params: {
          'p_south': -90.0,
          'p_west': -180.0,
          'p_north': 90.0,
          'p_east': 180.0,
        },
      );
      return [
        for (final raw in rows)
          if ((raw as Map).cast<String, dynamic>() case final row)
            ChangingPlace(
              id: row['id'] as String,
              location: LatLng(
                (row['lat'] as num).toDouble(),
                (row['lon'] as num).toDouble(),
              ),
              name: row['name'] as String?,
              wheelchairAccessible: row['wheelchair'] as bool?,
              fee: row['fee'] as bool?,
              feeMode: FeeMode.fromWire(row['fee_mode'] as String?),
              locationHint: row['location_hint'] as String?,
              source: PlaceSource.community,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Aktualisiert einen eigenen Platz. Server prueft Eigentuemerschaft.
  Future<void> updatePlace({
    required String id,
    required double lat,
    required double lon,
    String? name,
    String? locationHint,
    bool? wheelchair,
    bool? fee,
    FeeMode? feeMode,
  }) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>(
        'update_community_place',
        params: {
          'p_id': id,
          'p_lat': lat,
          'p_lon': lon,
          'p_name': name,
          'p_hint': locationHint,
          'p_wheelchair': wheelchair,
          'p_fee': fee,
          'p_fee_mode': feeMode?.wire,
        },
      );
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Loescht einen eigenen Platz (inkl. dessen Bewertungen/Meldungen).
  Future<void> deletePlace(String id) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>('delete_community_place', params: {'p_id': id});
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Zieht den 'raise exception <code>'-Text aus der Postgres-Fehlermeldung.
  static String _extractCode(String message) {
    // Spezifischere Codes zuerst: 'geo_rate_limit' enthaelt 'rate_limit'.
    for (final code in [
      'geo_rate_limit',
      'geo_cluster_cap',
      'rate_limit',
      'self_rating',
      'self_flag',
      'auth_required',
      'bad_stars',
      'too_many_tags',
      'bad_ref',
      'bad_coords',
      'name_too_long',
      'hint_too_long',
      'not_owner_or_missing',
    ]) {
      if (message.contains(code)) return code;
    }
    return 'unknown';
  }
}
