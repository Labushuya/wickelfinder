import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../../map/domain/changing_place.dart';
import '../../map/domain/venue_context.dart';

/// Einfacher persistenter Cache fuer OSM-Pins, damit sie beim Start sofort
/// sichtbar sind (wie die Community-Pins). Wird bei jedem erfolgreichen
/// Overpass-Load ueberschrieben/ergaenzt.
class OsmCache {
  static const _fileName = 'osm_places_cache.json';
  static const _maxPins = 4000; // Deckel wie im Akkumulator

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Laedt gecachte OSM-Pins (leer bei Fehler / erstem Start).
  Future<List<ChangingPlace>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final list = jsonDecode(await f.readAsString()) as List;
      return [
        for (final raw in list)
          if (_fromJson((raw as Map).cast<String, dynamic>())
              case final ChangingPlace p)
            p,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Speichert die gegebenen OSM-Pins (gedeckelt).
  Future<void> save(Iterable<ChangingPlace> places) async {
    try {
      final capped = places.take(_maxPins);
      final f = await _file();
      await f.writeAsString(jsonEncode([for (final p in capped) _toJson(p)]));
    } catch (_) {
      // nicht fatal
    }
  }

  static Map<String, dynamic> _toJson(ChangingPlace p) => {
    'id': p.id,
    'lat': p.location.latitude,
    'lon': p.location.longitude,
    'name': p.name,
    'wheelchair': p.wheelchairAccessible,
    'fee': p.fee,
    'hint': p.locationHint,
    'ctx': p.venueContext.name,
  };

  static ChangingPlace? _fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final lat = j['lat'] as num?;
    final lon = j['lon'] as num?;
    if (id == null || lat == null || lon == null) return null;
    final ctxName = j['ctx'] as String?;
    return ChangingPlace(
      id: id,
      location: LatLng(lat.toDouble(), lon.toDouble()),
      name: j['name'] as String?,
      wheelchairAccessible: j['wheelchair'] as bool?,
      fee: j['fee'] as bool?,
      locationHint: j['hint'] as String?,
      venueContext: VenueContext.values.firstWhere(
        (v) => v.name == ctxName,
        orElse: () => VenueContext.unknown,
      ),
    );
  }
}
