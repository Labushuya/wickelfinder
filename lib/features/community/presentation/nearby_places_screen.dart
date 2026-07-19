import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/location_service.dart';
import '../../map/domain/changing_place.dart';
import '../../search/presentation/address_search_bar.dart';
import 'accumulated_places.dart';
import 'pin_list.dart';

/// Formatiert eine Distanz in Metern nutzerfreundlich: unter 1 km in Metern
/// (auf 10 m gerundet), sonst in Kilometern mit einer Nachkommastelle.
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return '$rounded m';
  }
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Liste der Pins (OSM + Community) sortiert nach Entfernung zum aktuellen
/// Standort. Quelle sind die bereits geladenen Pins (accumulatedPlaces) —
/// sofort sichtbar; die Liste ergaenzt sich, sobald mehr Pins geladen sind.
class NearbyPlacesScreen extends ConsumerStatefulWidget {
  const NearbyPlacesScreen({super.key});

  @override
  ConsumerState<NearbyPlacesScreen> createState() => _NearbyPlacesScreenState();
}

class _NearbyPlacesScreenState extends ConsumerState<NearbyPlacesScreen> {
  static const _distance = Distance();

  String _query = '';
  LatLng? _origin;
  bool _locating = true;
  // true, sobald der Nutzer per Ort/PLZ-Suche einen Bezugspunkt gewaehlt hat.
  // Verhindert, dass der (async) GPS-Fix die manuelle Wahl ueberschreibt.
  bool _manualOrigin = false;

  @override
  void initState() {
    super.initState();
    _resolveOrigin();
  }

  Future<void> _resolveOrigin() async {
    // Sofort der letzte bekannte Standort (kein Warten), dann praeziser Fix.
    final last = await LocationService.lastKnown();
    if (mounted && last != null && !_manualOrigin) {
      setState(() => _origin = last);
    }
    final current = await LocationService.current();
    if (mounted) {
      setState(() {
        // Manuell gewaehlten Bezugspunkt NICHT ueberschreiben.
        if (current != null && !_manualOrigin) _origin = current;
        _locating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(accumulatedPlacesProvider).all;
    final origin = _origin;

    final filtered = all
        .where((p) => pinMatchesQuery(p, _query))
        .toList(growable: false);

    // Nach Entfernung sortieren, wenn ein Standort vorliegt.
    if (origin != null) {
      filtered.sort(
        (a, b) => _distance(
          origin,
          a.location,
        ).compareTo(_distance(origin, b.location)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pins in der Nähe')),
      body: Column(
        children: [
          // Ort/PLZ/Adresse suchen -> setzt den Bezugspunkt (Nominatim).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AddressSearchBar(
              onSelected: (target) => setState(() {
                _origin = target;
                _manualOrigin = true;
                _locating = false;
              }),
            ),
          ),
          if (_manualOrigin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, size: 15),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Sortiert nach Entfernung zum gesuchten Ort',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _manualOrigin = false;
                        _locating = true;
                      });
                      _resolveOrigin();
                    },
                    child: const Text('Mein Standort'),
                  ),
                ],
              ),
            ),
          if (origin == null && !_locating && !_manualOrigin)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Standort nicht verfügbar – nach einem Ort/einer PLZ suchen '
                'oder Standortfreigabe erlauben, um nach Entfernung zu sortieren.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          PinSearchField(onChanged: (v) => setState(() => _query = v)),
          Expanded(
            child: all.isEmpty
                ? const PinListEmpty(
                    message: 'Noch keine Pins geladen. Öffne zuerst die Karte.',
                  )
                : filtered.isEmpty
                ? const PinListEmpty(message: 'Keine Treffer.')
                : ListView.separated(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final dist = origin == null
                          ? null
                          : formatDistance(_distance(origin, p.location));
                      return ListTile(
                        leading: Icon(
                          p.source == PlaceSource.community
                              ? Icons.push_pin
                              : Icons.location_on,
                        ),
                        title: Text(p.name ?? 'Wickelplatz'),
                        subtitle: Text(
                          p.locationHint ??
                              (p.source == PlaceSource.community
                                  ? 'Community'
                                  : 'OpenStreetMap'),
                        ),
                        trailing: dist == null
                            ? null
                            : Text(
                                dist,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
