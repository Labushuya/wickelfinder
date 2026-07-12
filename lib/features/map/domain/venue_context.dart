/// Örtlicher Kontext eines Wickelplatzes — leitet die faktische
/// Zugaenglichkeit ab (frei zugaenglich vs. Eintritt/Konsum noetig),
/// unabhaengig von Barrierefreiheit.
///
/// Wird automatisch aus OSM-Tags (`amenity`/`leisure`/`shop`/`tourism`) des
/// zugehoerigen Objekts abgeleitet — kein Nutzer-Input noetig.
enum VenueContext {
  swimmingPool('🏊', 'Schwimmbad', accessRestricted: true),
  sportsCentre('🏟', 'Sportzentrum', accessRestricted: true),
  restaurant('🍽', 'Restaurant / Café', accessRestricted: true),
  cinema('🎬', 'Kino', accessRestricted: true),
  mall('🛍', 'Einkaufszentrum'),
  supermarket('🛒', 'Supermarkt'),
  publicToilet('🚻', 'Öffentliche Toilette'),
  services('⛽', 'Raststätte / Tankstelle'),
  hospital('🏥', 'Klinik / Ärztehaus'),
  library('📚', 'Bibliothek'),
  parkingOrPark('🌳', 'Park / Rastplatz'),
  unknown('📍', 'Wickelplatz');

  const VenueContext(this.emoji, this.label, {this.accessRestricted = false});

  final String emoji;
  final String label;

  /// True, wenn der Ort typischerweise Eintritt/Konsum voraussetzt
  /// (Schwimmbad, Restaurant, Kino …) — beeinflusst die Zugaenglichkeit.
  final bool accessRestricted;

  /// Leitet den Kontext aus einer Menge OSM-Tags ab.
  /// Reihenfolge = Prioritaet (spezifischer zuerst).
  static VenueContext fromTags(Map<String, String> tags) {
    final amenity = tags['amenity'];
    final leisure = tags['leisure'];
    final shop = tags['shop'];
    final tourism = tags['tourism'];
    final highway = tags['highway'];

    if (leisure == 'swimming_pool' ||
        leisure == 'water_park' ||
        amenity == 'swimming_pool') {
      return VenueContext.swimmingPool;
    }
    if (leisure == 'sports_centre' || leisure == 'fitness_centre') {
      return VenueContext.sportsCentre;
    }
    if (amenity == 'restaurant' ||
        amenity == 'cafe' ||
        amenity == 'fast_food' ||
        amenity == 'bar' ||
        amenity == 'pub') {
      return VenueContext.restaurant;
    }
    if (amenity == 'cinema' || amenity == 'theatre') {
      return VenueContext.cinema;
    }
    if (shop == 'mall' || shop == 'department_store') {
      return VenueContext.mall;
    }
    if (shop == 'supermarket' || shop == 'convenience') {
      return VenueContext.supermarket;
    }
    if (amenity == 'toilets') return VenueContext.publicToilet;
    if (highway == 'services' || highway == 'rest_area' || amenity == 'fuel') {
      return VenueContext.services;
    }
    if (amenity == 'hospital' || amenity == 'clinic' || amenity == 'doctors') {
      return VenueContext.hospital;
    }
    if (amenity == 'library') return VenueContext.library;
    if (leisure == 'park' || tourism == 'picnic_site') {
      return VenueContext.parkingOrPark;
    }
    return VenueContext.unknown;
  }
}
