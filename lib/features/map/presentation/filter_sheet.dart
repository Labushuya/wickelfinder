import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/changing_place.dart';
import '../domain/venue_context.dart';
import 'map_filter_provider.dart';

/// Bottom-Sheet zum Filtern der Kartenpins. Schreibt live in den
/// [mapFilterProvider]; die Karte reagiert sofort. Leerer Filter = alles zeigen.
class FilterSheet extends ConsumerWidget {
  const FilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(mapFilterProvider);
    final ctrl = ref.read(mapFilterProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Filter', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Zurücksetzen'),
                  onPressed: filter.isActive ? ctrl.clear : null,
                ),
              ],
            ),
            const SizedBox(height: 4),

            _label(theme, 'Ausstattung & Zugang'),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Barrierefrei'),
                  selected: filter.onlyBarrierefrei,
                  onSelected: ctrl.setBarrierefrei,
                ),
                FilterChip(
                  label: const Text('Frei zugänglich'),
                  selected: filter.onlyAccessible,
                  onSelected: ctrl.setAccessible,
                ),
                FilterChip(
                  label: const Text('Kostenlos'),
                  selected: filter.onlyFree,
                  onSelected: ctrl.setFree,
                ),
                FilterChip(
                  label: const Text('Eigener Wickelraum'),
                  selected: filter.onlyOwnRoom,
                  onSelected: ctrl.setOwnRoom,
                ),
              ],
            ),
            const SizedBox(height: 12),

            _label(theme, 'Ortstyp'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final v in VenueContext.values)
                  if (v != VenueContext.unknown)
                    FilterChip(
                      label: Text('${v.emoji} ${v.label}'),
                      selected: filter.venues.contains(v),
                      onSelected: (_) => ctrl.toggleVenue(v),
                    ),
              ],
            ),
            const SizedBox(height: 12),

            _label(theme, 'Quelle'),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Community'),
                  selected: filter.sources.contains(PlaceSource.community),
                  onSelected: (_) => ctrl.toggleSource(PlaceSource.community),
                ),
                FilterChip(
                  label: const Text('OpenStreetMap'),
                  selected: filter.sources.contains(PlaceSource.osm),
                  onSelected: (_) => ctrl.toggleSource(PlaceSource.osm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
