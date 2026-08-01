import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../community/presentation/accumulated_places.dart';
import '../../community/presentation/pin_list.dart';
import '../data/favorites_controller.dart';

/// Zeigt die lokal favorisierten Wickelplaetze. Tap -> Karte fliegt hin.
///
/// Pop-Ergebnis: [LatLng] des gewaehlten Favoriten (map_screen ruft _goTo).
/// Jeder Favorit traegt einen Koordinaten-Snapshot, daher ist der Anflug auch
/// dann moeglich, wenn der Pin gerade nicht geladen ist.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final favs = ref.watch(favoritesProvider);
    // Frische Namen/Lage aus geladenen Pins, falls verfuegbar.
    final byRef = ref.watch(accumulatedPlacesProvider).byRef;

    if (favs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favoriten')),
        body: const PinListEmpty(
          message: 'Noch keine Favoriten.\nTippe auf ♥ in einem Wickelplatz.',
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    final shown = favs
        .where((f) {
          if (q.isEmpty) return true;
          final name = (byRef[f.placeRef]?.name ?? f.name ?? '').toLowerCase();
          return name.contains(q);
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Favoriten')),
      body: Column(
        children: [
          PinSearchField(onChanged: (v) => setState(() => _query = v)),
          Expanded(
            child: shown.isEmpty
                ? const PinListEmpty(message: 'Keine Treffer.')
                : ListView.separated(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
                    ),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final fav = shown[i];
                      final place = byRef[fav.placeRef];
                      final title = place?.name ?? fav.name ?? 'Wickelplatz';
                      final subtitle =
                          place?.displayLocationHint ??
                          '${fav.lat.toStringAsFixed(4)}, '
                              '${fav.lon.toStringAsFixed(4)}';
                      return ListTile(
                        leading: const Icon(Icons.favorite, size: 20),
                        title: Text(title),
                        subtitle: Text(subtitle),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Aus Favoriten entfernen',
                          onPressed: () =>
                              ref.read(favoritesProvider.notifier).toggle(fav),
                        ),
                        onTap: () =>
                            Navigator.of(context).pop(LatLng(fav.lat, fav.lon)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
