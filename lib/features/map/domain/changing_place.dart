import 'package:latlong2/latlong.dart';

/// Domänen-Modell für einen Wickelplatz.
///
/// Quelle ist zunächst OpenStreetMap (`changing_table=yes`); die
/// Community-Ebene (Ratings, Verifikation) kommt in einer späteren Iteration
/// über Supabase hinzu und wird über dieselbe Struktur gemappt.
class ChangingPlace {
  const ChangingPlace({
    required this.id,
    required this.location,
    this.name,
    this.wheelchairAccessible,
    this.fee,
    this.locationHint,
    this.source = PlaceSource.osm,
  });

  /// Eindeutige ID. Für OSM: "<type>/<osmId>", z. B. "node/12345".
  final String id;
  final LatLng location;
  final String? name;

  /// `wheelchair=yes|no` – null wenn unbekannt.
  final bool? wheelchairAccessible;

  /// Kostenpflichtig? Aus `fee=yes|no` – null wenn unbekannt.
  final bool? fee;

  /// Freitext-Hinweis zur Lage, z. B. aus `changing_table:location`.
  final String? locationHint;

  final PlaceSource source;

  /// Erzeugt einen [ChangingPlace] aus einem Overpass-JSON-Element.
  ///
  /// Unterstützt `node` (mit `lat`/`lon`) und `way`/`relation`
  /// (mit `center.lat`/`center.lon`). Gibt `null` zurück, wenn keine
  /// Koordinaten ermittelbar sind – so werden unbrauchbare Elemente
  /// sauber ausgefiltert statt eine Exception zu werfen.
  static ChangingPlace? fromOverpassElement(Map<String, dynamic> el) {
    final type = el['type'] as String?;
    final osmId = el['id'];
    if (type == null || osmId == null) return null;

    final (double? lat, double? lon) = _extractCoords(el);
    if (lat == null || lon == null) return null;

    final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};

    return ChangingPlace(
      id: '$type/$osmId',
      location: LatLng(lat, lon),
      name: tags['name'] as String?,
      wheelchairAccessible: _yesNo(tags['wheelchair'] as String?),
      fee: _yesNo(tags['fee'] as String?),
      locationHint: tags['changing_table:location'] as String?,
    );
  }

  static (double?, double?) _extractCoords(Map<String, dynamic> el) {
    final lat = el['lat'];
    final lon = el['lon'];
    if (lat is num && lon is num) return (lat.toDouble(), lon.toDouble());

    final center = el['center'];
    if (center is Map) {
      final clat = center['lat'];
      final clon = center['lon'];
      if (clat is num && clon is num) {
        return (clat.toDouble(), clon.toDouble());
      }
    }
    return (null, null);
  }

  static bool? _yesNo(String? v) => switch (v) {
    'yes' => true,
    'no' => false,
    _ => null,
  };
}

enum PlaceSource { osm, community }
