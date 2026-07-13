import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/domain/changing_place.dart';

/// Persistenter, offline-faehiger Cache der Community-Plaetze mit Delta-Sync.
///
/// - Beim Start werden die gecachten Pins sofort geladen (auch offline).
/// - Im Hintergrund holt [sync] nur die Aenderungen seit dem letzten Stand
///   (Delta): geaenderte/neue Pins werden aktualisiert, geloeschte entfernt.
/// - Der Cache liegt als JSON-Datei im App-Verzeichnis.
class CommunityCache {
  CommunityCache(this._client);

  final SupabaseClient _client;
  static const _fileName = 'community_places_cache.json';

  Map<String, ChangingPlace> _places = {};
  String? _watermark; // ISO-Zeitstempel des letzten bekannten Standes
  bool _loaded = false;
  Completer<void>? _syncing;

  /// Aktuelle Pins aus dem Cache.
  List<ChangingPlace> get places => _places.values.toList(growable: false);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Laedt den Cache von der Platte (einmalig). Schnell, offline-tauglich.
  Future<void> loadFromDisk() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _watermark = json['watermark'] as String?;
      final list = (json['places'] as List?) ?? const [];
      _places = {
        for (final raw in list)
          if (_fromCacheJson((raw as Map).cast<String, dynamic>())
              case final ChangingPlace p)
            p.id: p,
      };
    } catch (_) {
      // Beschaedigter Cache -> verwerfen, Vollsync holt alles neu.
      _places = {};
      _watermark = null;
    }
  }

  /// Delta-Sync gegen das Backend. Serialisiert (kein paralleler Doppel-Sync).
  /// Gibt true zurueck, wenn sich etwas geaendert hat.
  Future<bool> sync() async {
    if (_syncing != null) {
      await _syncing!.future;
      return false;
    }
    _syncing = Completer<void>();
    var changed = false;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'community_places_delta',
        params: {'p_since': _watermark},
      );
      String? maxTs = _watermark;
      for (final raw in rows) {
        final row = (raw as Map).cast<String, dynamic>();
        final id = row['id'] as String;
        final ts = row['updated_at'] as String?;
        if (ts != null && (maxTs == null || ts.compareTo(maxTs) > 0)) {
          maxTs = ts;
        }
        if (row['deleted'] == true) {
          if (_places.remove(id) != null) changed = true;
        } else {
          _places[id] = ChangingPlace(
            id: id,
            location: LatLng(
              (row['lat'] as num).toDouble(),
              (row['lon'] as num).toDouble(),
            ),
            name: row['name'] as String?,
            wheelchairAccessible: row['wheelchair'] as bool?,
            fee: row['fee'] as bool?,
            locationHint: row['location_hint'] as String?,
            source: PlaceSource.community,
          );
          changed = true;
        }
      }
      _watermark = maxTs;
      if (changed) await _persist();
    } catch (_) {
      // Offline / Fehler: gecachte Pins bleiben stehen (kein Leeren).
    } finally {
      _syncing!.complete();
      _syncing = null;
    }
    return changed;
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'watermark': _watermark,
          'places': [for (final p in _places.values) _toCacheJson(p)],
        }),
      );
    } catch (_) {
      // Persistenz-Fehler ist nicht fatal (naechster Sync versucht erneut).
    }
  }

  static Map<String, dynamic> _toCacheJson(ChangingPlace p) => {
    'id': p.id,
    'lat': p.location.latitude,
    'lon': p.location.longitude,
    'name': p.name,
    'wheelchair': p.wheelchairAccessible,
    'fee': p.fee,
    'hint': p.locationHint,
  };

  static ChangingPlace? _fromCacheJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final lat = j['lat'] as num?;
    final lon = j['lon'] as num?;
    if (id == null || lat == null || lon == null) return null;
    return ChangingPlace(
      id: id,
      location: LatLng(lat.toDouble(), lon.toDouble()),
      name: j['name'] as String?,
      wheelchairAccessible: j['wheelchair'] as bool?,
      fee: j['fee'] as bool?,
      locationHint: j['hint'] as String?,
      source: PlaceSource.community,
    );
  }
}
