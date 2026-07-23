import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/domain/changing_place.dart';
import '../domain/admin_place_feedback.dart';
import '../domain/moderation_counts.dart';
import '../domain/pending_photo.dart';
import '../domain/place_flag.dart';
import '../domain/place_photo.dart';
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
    'photo_exists' => 'Du hast für diesen Platz bereits ein Foto.',
    'photo_limit' => 'Du hast für diesen Platz bereits 3 Fotos.',
    'photo_rate_limit' => 'Zu viele Fotos in kurzer Zeit. Bitte später erneut.',
    'report_rate_limit' =>
      'Zu viele Meldungen in kurzer Zeit. Bitte später erneut.',
    'photo_missing' => 'Dieses Foto existiert nicht (mehr).',
    'bad_kind' => 'Ungültiger Melde-Grund.',
    'bad_path' => 'Ungültiger Datei-Pfad.',
    'admin_required' => 'Nur für Administratoren.',
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

  // --- Fotos ----------------------------------------------------------------

  static const _bucket = 'place-photos';
  // Signierte URLs 7 Tage gueltig -> Cache-Key bleibt stabil (Egress-schonend).
  static const _signedUrlTtl = 604800;

  /// Laedt ein Foto hoch: EXIF/GPS entfernen + komprimieren -> Storage ->
  /// register_photo. Verlangt ein ECHTES Konto (nicht anonym). Gibt die
  /// neue Foto-ID zurueck.
  Future<String> uploadPhoto({
    required String placeRef,
    required XFile picked,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const CommunityException('auth_required');
    }
    final uid = user.id;

    // Komprimieren + Metadaten entfernen (keepExif:false -> GPS/Geraet/Zeit weg).
    final bytes = await _compressForUpload(picked);

    // Pfad im eigenen Ordner: <uid>/<place_slug>/<zeitstempel>.jpg
    final slug = placeRef.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final path = '$uid/$slug/$stamp.jpg';

    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } catch (e) {
      throw CommunityException('upload_failed', e.toString());
    }

    try {
      final id = await _client.rpc<String>(
        'register_photo',
        params: {'p_ref': placeRef, 'p_path': path},
      );
      return id;
    } on PostgrestException catch (e) {
      // Registrierung fehlgeschlagen -> hochgeladenes Objekt best-effort
      // entfernen, damit kein Orphan zurueckbleibt.
      try {
        await _client.storage.from(_bucket).remove([path]);
      } catch (_) {}
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Komprimiert ein gewaehltes Bild auf ~200 KB / ~1280px, JPEG, OHNE EXIF.
  Future<Uint8List> _compressForUpload(XFile picked) async {
    Future<Uint8List?> attempt(int quality) async {
      final out = await FlutterImageCompress.compressWithFile(
        picked.path,
        minWidth: 1280,
        minHeight: 1280,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false, // GPS/Geraet/Zeit werden entfernt (DSGVO).
      );
      return out;
    }

    // Erst Qualitaet 70; wenn noch > ~230 KB, einmal auf 55 nachverdichten.
    var bytes = await attempt(70);
    if (bytes != null && bytes.length > 230 * 1024) {
      final smaller = await attempt(55);
      if (smaller != null) bytes = smaller;
    }
    if (bytes == null || bytes.isEmpty) {
      throw const CommunityException('upload_failed', 'compress returned null');
    }
    return bytes;
  }

  /// Laedt Fotos zu den place_refs (freigegebene + eigene pending) und signiert
  /// je eine Anzeige-URL. Lesen ohne Login moeglich (nur freigegebene).
  Future<List<PlacePhoto>> photosFor(List<String> refs) async {
    if (refs.isEmpty) return const [];
    final capped = refs.length > 200 ? refs.sublist(0, 200) : refs;
    final rows = await _client.rpc<List<dynamic>>(
      'photos_for',
      params: {'refs': capped},
    );
    final result = <PlacePhoto>[];
    for (final row in rows) {
      final map = (row as Map).cast<String, dynamic>();
      final path = map['storage_path'] as String;
      String signed = '';
      try {
        signed = await _client.storage
            .from(_bucket)
            .createSignedUrl(path, _signedUrlTtl);
      } catch (_) {
        // Signieren scheitert (z. B. keine Leserechte) -> Foto ueberspringen.
        continue;
      }
      result.add(PlacePhoto.fromRow(map, signed));
    }
    return result;
  }

  /// Die EIGENEN Fotos zu einem Platz (bis zu 3), leer wenn keine.
  Future<List<PlacePhoto>> myPhotos(String placeRef) async {
    if (_client.auth.currentUser == null) return const [];
    final photos = await photosFor([placeRef]);
    return [
      for (final p in photos)
        if (p.isMine) p,
    ];
  }

  /// Loescht das eigene Foto: erst das Storage-Objekt, dann die DB-Zeile
  /// (Reihenfolge so, dass kein Orphan-Objekt zurueckbleibt).
  Future<void> deleteMyPhoto(PlacePhoto photo) async {
    try {
      await _client.storage.from(_bucket).remove([photo.storagePath]);
    } catch (_) {
      // Objekt evtl. schon weg -> trotzdem die Zeile entfernen.
    }
    try {
      await _client.rpc<void>(
        'delete_my_photo',
        params: {'p_photo_id': photo.id},
      );
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Meldet einen Inhalt (Foto oder Platz). Kind: pii/abuse/spam/other.
  Future<void> reportContent({
    required String placeRef,
    required String kind,
    String? photoId,
  }) async {
    await _session.ensureSignedIn();
    try {
      await _client.rpc<void>(
        'report_content',
        params: {'p_ref': placeRef, 'p_kind': kind, 'p_photo_id': photoId},
      );
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  // --- Admin-Foto-Moderation ------------------------------------------------

  /// Wartende Fotos (nur Admin) inkl. signierter Vorschau-URL.
  Future<List<PendingPhoto>> adminPendingPhotos() async {
    try {
      final rows = await _client.rpc<List<dynamic>>('admin_pending_photos');
      final result = <PendingPhoto>[];
      for (final row in rows) {
        final map = (row as Map).cast<String, dynamic>();
        final path = map['storage_path'] as String;
        String signed = '';
        try {
          signed = await _client.storage
              .from(_bucket)
              .createSignedUrl(path, _signedUrlTtl);
        } catch (_) {}
        result.add(PendingPhoto.fromRow(map, signed));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Foto freigeben oder ablehnen (nur Admin). Bei Ablehnung optional Notiz.
  Future<void> adminReviewPhoto(
    String photoId, {
    required bool approve,
    String? note,
  }) async {
    try {
      await _client.rpc<void>(
        'admin_review_photo',
        params: {'p_photo_id': photoId, 'p_approve': approve, 'p_note': note},
      );
    } on PostgrestException catch (e) {
      throw CommunityException(_extractCode(e.message), e.message);
    }
  }

  /// Pruefungsbeduerftige Zaehler je place_ref (nur Admin). Leer ohne Recht.
  Future<Map<String, ModerationCounts>> adminModerationCounts() async {
    try {
      final rows = await _client.rpc<List<dynamic>>('admin_moderation_counts');
      final result = <String, ModerationCounts>{};
      for (final row in rows) {
        final map = (row as Map).cast<String, dynamic>();
        result[map['place_ref'] as String] = ModerationCounts.fromRow(map);
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Zieht den 'raise exception <code>'-Text aus der Postgres-Fehlermeldung.
  static String _extractCode(String message) {
    // Spezifischere Codes zuerst: 'geo_rate_limit' enthaelt 'rate_limit'.
    for (final code in [
      'geo_rate_limit',
      'geo_cluster_cap',
      'photo_rate_limit',
      'report_rate_limit',
      'rate_limit',
      'self_rating',
      'self_flag',
      'photo_exists',
      'photo_limit',
      'photo_missing',
      'bad_kind',
      'bad_path',
      'admin_required',
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
