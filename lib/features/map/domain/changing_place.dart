import 'package:latlong2/latlong.dart';

import 'venue_context.dart';

/// Kosten-Modell eines Platzes: kostenlos, bedingt (kostenlos nur fuer
/// Gaeste/Kunden) oder kostenpflichtig. null = unbekannt.
enum FeeMode {
  free('free', 'Kostenlos'),
  conditional('conditional', 'Kostenlos für Gäste/Kunden'),
  paid('paid', 'Kostenpflichtig');

  const FeeMode(this.wire, this.label);
  final String wire;
  final String label;

  static FeeMode? fromWire(String? w) {
    if (w == null) return null;
    for (final m in values) {
      if (m.wire == w) return m;
    }
    return null;
  }

  /// Ableitung aus dem alten boolean-fee (Abwaertskompatibilitaet / OSM).
  static FeeMode? fromFee(bool? fee) => switch (fee) {
    true => FeeMode.paid,
    false => FeeMode.free,
    _ => null,
  };
}

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
    this.feeMode,
    this.locationHint,
    this.openingHours,
    this.source = PlaceSource.osm,
    this.venueContext = VenueContext.unknown,
  });

  /// Eindeutige ID. Für OSM: "<type>/<osmId>", z. B. "node/12345".
  final String id;
  final LatLng location;
  final String? name;

  /// `wheelchair=yes|no` – null wenn unbekannt.
  final bool? wheelchairAccessible;

  /// Kostenpflichtig? Aus `fee=yes|no` – null wenn unbekannt.
  final bool? fee;

  /// Dreiwertiges Kosten-Modell (Community): free/conditional/paid. Fuer
  /// OSM-Pins aus [fee] abgeleitet. null = unbekannt.
  final FeeMode? feeMode;

  /// Effektives Kosten-Modell: bevorzugt [feeMode], faellt sonst auf [fee].
  FeeMode? get effectiveFeeMode => feeMode ?? FeeMode.fromFee(fee);

  /// Freitext-Hinweis zur Lage, z. B. aus `changing_table:location`.
  final String? locationHint;

  /// Roher OSM-`opening_hours`-String (z. B. "Mo-Fr 08:00-18:00", "24/7").
  /// null = keine Angabe. Nur OSM; Community-Plaetze tragen das nicht.
  final String? openingHours;

  final PlaceSource source;

  /// Örtlicher Kontext (Schwimmbad/Restaurant/…), abgeleitet aus OSM-Tags.
  final VenueContext venueContext;

  /// Stabile Referenz fuer Community-Feedback (Rating/Flag).
  /// OSM: "node/123" (== [id]). Community: "community/<uuid>".
  String get placeRef => source == PlaceSource.community ? 'community/$id' : id;

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
    // Tags fuer die Kontext-Ableitung als String-Map (nur String-Werte).
    final stringTags = <String, String>{
      for (final e in tags.entries)
        if (e.value is String) e.key: e.value as String,
    };

    return ChangingPlace(
      id: '$type/$osmId',
      location: LatLng(lat, lon),
      name: tags['name'] as String?,
      wheelchairAccessible: _yesNo(tags['wheelchair'] as String?),
      fee: _yesNo(tags['fee'] as String?),
      locationHint: tags['changing_table:location'] as String?,
      openingHours: tags['opening_hours'] as String?,
      venueContext: VenueContext.fromTags(stringTags),
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
