import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/changing_place.dart';
import 'add_place_screen.dart';
import 'community_providers.dart';

/// Lokales Suchfeld fuer Pin-Listen (kein Netzwerk): filtert live ueber
/// Name + Lage-Hinweis. Wiederverwendet in "Meine Pins" und "Alle Pins".
class PinSearchField extends StatelessWidget {
  const PinSearchField({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Pins durchsuchen …',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }
}

/// True, wenn der Suchbegriff in Name oder Lage-Hinweis vorkommt (case-insens.).
bool pinMatchesQuery(ChangingPlace p, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final name = (p.name ?? '').toLowerCase();
  final hint = (p.locationHint ?? '').toLowerCase();
  return name.contains(q) || hint.contains(q);
}

/// Listeneintrag fuer einen Community-Pin mit Bearbeiten/Loeschen. Fuer Admin
/// funktionieren beide Aktionen serverseitig auch auf fremden Pins
/// (created_by = uid OR admin).
class PlaceTile extends ConsumerWidget {
  const PlaceTile({super.key, required this.place, this.onTap});

  final ChangingPlace place;

  /// Optional: Tap auf die Zeile (z. B. Liste schliessen + zur Karte fliegen).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: onTap,
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
    if (changed ?? false) await refreshCommunityDataFromWidget(ref);
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
      await refreshCommunityDataFromWidget(ref);
      messenger.showSnackBar(const SnackBar(content: Text('Platz gelöscht.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Löschen fehlgeschlagen.')),
      );
    }
  }
}

/// Leerer Zustand fuer Pin-Listen.
class PinListEmpty extends StatelessWidget {
  const PinListEmpty({
    super.key,
    required this.message,
    this.showAddHint = false,
  });

  final String message;
  final bool showAddHint;

  @override
  Widget build(BuildContext context) {
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
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
