import 'changing_place.dart';
import 'opening_hours_status.dart';
import 'venue_context.dart';

/// Filter-Zustand fuer die Karte. Leerer Filter = alles zeigen.
///
/// Semantik: Ein Pin mit UNBEKANNTEM Merkmal wird EINGESCHLOSSEN (nicht
/// weggefiltert) — sonst verschwaenden zu viele Pins, deren OSM-Tag schlicht
/// fehlt. Nur ein explizit gegenteiliger Wert schliesst aus.
class MapFilter {
  const MapFilter({
    this.venues = const {},
    this.onlyBarrierefrei = false,
    this.onlyFree = false,
    this.onlyAccessible = false,
    this.onlyOwnRoom = false,
    this.onlyOpenNow = false,
    this.sources = const {},
  });

  /// Erlaubte Ortstypen. Leer = alle.
  final Set<VenueContext> venues;

  /// Nur `wheelchair=yes`.
  final bool onlyBarrierefrei;

  /// Nur kostenlos (effectiveFeeMode == free).
  final bool onlyFree;

  /// Nur frei zugaenglich (kein Eintritt/Konsum: !venueContext.accessRestricted).
  final bool onlyAccessible;

  /// Nur eigener Wickelraum (changing_table:location dedicated_room/baby_care_room).
  final bool onlyOwnRoom;

  /// Nur aktuell geöffnet (nach OSM opening_hours). Braucht die aktuelle Zeit
  /// beim Matchen; unbekannte/komplexe Zeiten bleiben eingeschlossen.
  final bool onlyOpenNow;

  /// Erlaubte Quellen. Leer = alle.
  final Set<PlaceSource> sources;

  bool get isActive =>
      venues.isNotEmpty ||
      onlyBarrierefrei ||
      onlyFree ||
      onlyAccessible ||
      onlyOwnRoom ||
      onlyOpenNow ||
      sources.isNotEmpty;

  /// Anzahl aktiver Einzel-Auswahlen (jedes gewählte Element + jeder Schalter).
  /// Beispiel: 3 Ortstypen + „Kostenlos" = 4.
  int get activeCount {
    var n = 0;
    n += venues.length;
    n += sources.length;
    if (onlyBarrierefrei) n++;
    if (onlyFree) n++;
    if (onlyAccessible) n++;
    if (onlyOwnRoom) n++;
    if (onlyOpenNow) n++;
    return n;
  }

  /// [now] wird nur fuer das „jetzt geöffnet"-Kriterium benoetigt. Ohne [now]
  /// bleibt dieses Kriterium wirkungslos (schliesst nichts aus).
  bool matches(ChangingPlace p, {DateTime? now}) {
    if (venues.isNotEmpty && !venues.contains(p.venueContext)) return false;
    if (sources.isNotEmpty && !sources.contains(p.source)) return false;

    // Barrierefrei: nur ausschliessen, wenn explizit == false. null bleibt drin.
    if (onlyBarrierefrei && p.wheelchairAccessible == false) return false;

    // Frei zugaenglich: Kontext ist immer gesetzt (Default unknown ist NICHT
    // accessRestricted) -> harte Bedingung ohne Unbekannt-Fall.
    if (onlyAccessible && p.venueContext.accessRestricted) return false;

    // Kostenlos: nur ausschliessen, wenn ein GEGENTEILIGER Modus bekannt ist.
    // Unbekannt (null) bleibt drin.
    if (onlyFree) {
      final mode = p.effectiveFeeMode;
      if (mode != null && mode != FeeMode.free) return false;
    }

    // Eigener Wickelraum: locationHint kann Multi-Value sein (;/,) -> OR-Match.
    // Unbekannt (null) bleibt drin.
    if (onlyOwnRoom) {
      final hint = p.locationHint;
      if (hint != null && !_hasOwnRoomToken(hint)) return false;
    }

    // Jetzt geöffnet: nur AUSSCHLIESSEN, wenn sicher „geschlossen". Unbekannte/
    // komplexe Zeiten und Pins ohne Zeiten bleiben eingeschlossen.
    if (onlyOpenNow && now != null) {
      final oh = p.openingHours;
      if (oh != null && openStateAt(oh, now) == OpenState.closed) return false;
    }

    return true;
  }

  static bool _hasOwnRoomToken(String hint) {
    for (final t in hint.split(RegExp(r'[;,]'))) {
      final v = t.trim();
      if (v == 'dedicated_room' || v == 'baby_care_room') return true;
    }
    return false;
  }

  MapFilter copyWith({
    Set<VenueContext>? venues,
    bool? onlyBarrierefrei,
    bool? onlyFree,
    bool? onlyAccessible,
    bool? onlyOwnRoom,
    bool? onlyOpenNow,
    Set<PlaceSource>? sources,
  }) => MapFilter(
    venues: venues ?? this.venues,
    onlyBarrierefrei: onlyBarrierefrei ?? this.onlyBarrierefrei,
    onlyFree: onlyFree ?? this.onlyFree,
    onlyAccessible: onlyAccessible ?? this.onlyAccessible,
    onlyOwnRoom: onlyOwnRoom ?? this.onlyOwnRoom,
    onlyOpenNow: onlyOpenNow ?? this.onlyOpenNow,
    sources: sources ?? this.sources,
  );
}
