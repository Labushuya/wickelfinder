import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/changing_place.dart';
import 'add_place_screen.dart';
import 'community_providers.dart';

/// Zeigt die vom Nutzer selbst erstellten Wickelplaetze mit der Moeglichkeit,
/// sie zu bearbeiten oder zu loeschen. Bei leerer Liste: freundlicher Hinweis
/// + direkter Weg zum Hinzufuegen.
class MyPlacesScreen extends ConsumerWidget {
  const MyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPlacesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Pins')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const _Empty(message: 'Deine Pins konnten nicht geladen werden.'),
        data: (places) {
          if (places.isEmpty) {
            return const _Empty(
              message: 'Du hast noch keine Wickelplätze gemeldet.',
              showAddHint: true,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myPlacesProvider),
            child: ListView.separated(
              itemCount: places.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _PlaceTile(place: places[i]),
            ),
          );
        },
      ),
    );
  }
}

class _PlaceTile extends ConsumerWidget {
  const _PlaceTile({required this.place});

  final ChangingPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.location_on),
      title: Text(place.name ?? 'Wickelplatz'),
      subtitle: Text(
        place.locationHint ??
            '${place.location.latitude.toStringAsFixed(4)}, '
                '${place.location.longitude.toStringAsFixed(4)}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') {
            _edit(context, ref);
          } else if (v == 'delete') {
            _confirmDelete(context, ref);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          PopupMenuItem(value: 'delete', child: Text('Löschen')),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AddPlaceScreen(initialCenter: place.location, editPlace: place),
      ),
    );
    if (changed ?? false) ref.invalidate(myPlacesProvider);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Platz löschen?'),
        content: Text(
          '„${place.name ?? 'Wickelplatz'}" wird endgültig entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.deletePlace(place.id);
      ref.invalidate(myPlacesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Platz gelöscht.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Löschen fehlgeschlagen.')),
      );
    }
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.message, this.showAddHint = false});

  final String message;
  final bool showAddHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.push_pin_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (showAddHint) ...[
              const SizedBox(height: 8),
              const Text(
                'Tippe auf der Karte auf „Platz melden", um deinen ersten '
                'Wickelplatz hinzuzufügen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Zurück zur Karte'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
