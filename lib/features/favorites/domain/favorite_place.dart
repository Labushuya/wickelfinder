/// Ein favorisierter Wickelplatz — als kleiner Snapshot gespeichert, damit die
/// Favoritenliste und der Kartenanflug auch dann funktionieren, wenn der Pin
/// gerade nicht geladen ist (weit entfernt / ausserhalb des OSM-Caps).
class FavoritePlace {
  const FavoritePlace({
    required this.placeRef,
    required this.lat,
    required this.lon,
    this.name,
  });

  /// Stabile Referenz: OSM "node/123" oder "community/<uuid>".
  final String placeRef;
  final double lat;
  final double lon;

  /// Name zum Zeitpunkt des Favorisierens (kann veralten, bis der Pin frisch
  /// geladen wird). null = unbenannt.
  final String? name;

  Map<String, dynamic> toJson() => {
    'ref': placeRef,
    'lat': lat,
    'lon': lon,
    'name': name,
  };

  static FavoritePlace? fromJson(Map<String, dynamic> j) {
    final ref = j['ref'] as String?;
    final lat = j['lat'] as num?;
    final lon = j['lon'] as num?;
    if (ref == null || lat == null || lon == null) return null;
    return FavoritePlace(
      placeRef: ref,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      name: j['name'] as String?,
    );
  }
}
