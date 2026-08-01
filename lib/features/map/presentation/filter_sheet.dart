import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/changing_place.dart';
import '../domain/map_filter.dart';
import '../domain/venue_context.dart';
import 'map_filter_provider.dart';

/// Bottom-Sheet zum Filtern der Kartenpins. Bearbeitet einen LOKALEN Entwurf;
/// die Karte ändert sich erst bei „Übernehmen". Zurück / Abbrechen / Wegwischen
/// verwerfen den Entwurf (der aktive Filter bleibt unverändert).
class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late MapFilter _draft;

  @override
  void initState() {
    super.initState();
    // Einmaliger Snapshot des aktuell aktiven Filters (MapFilter ist immutable).
    _draft = ref.read(mapFilterProvider);
  }

  void _toggleVenue(VenueContext v) {
    final next = <VenueContext>{..._draft.venues};
    next.contains(v) ? next.remove(v) : next.add(v);
    setState(() => _draft = _draft.copyWith(venues: next));
  }

  void _toggleSource(PlaceSource s) {
    final next = <PlaceSource>{..._draft.sources};
    next.contains(s) ? next.remove(s) : next.add(s);
    setState(() => _draft = _draft.copyWith(sources: next));
  }

  void _apply() {
    ref.read(mapFilterProvider.notifier).apply(_draft);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _draft;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                        // Nur den ENTWURF leeren, nicht den aktiven Filter.
                        onPressed: d.isActive
                            ? () => setState(() => _draft = const MapFilter())
                            : null,
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
                        selected: d.onlyBarrierefrei,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(onlyBarrierefrei: v),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Frei zugänglich'),
                        selected: d.onlyAccessible,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(onlyAccessible: v),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Kostenlos'),
                        selected: d.onlyFree,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(onlyFree: v),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Eigener Wickelraum'),
                        selected: d.onlyOwnRoom,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(onlyOwnRoom: v),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Jetzt geöffnet'),
                        selected: d.onlyOpenNow,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(onlyOpenNow: v),
                        ),
                      ),
                    ],
                  ),
                  if (d.onlyOpenNow)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Feiertage werden nicht berücksichtigt. Plätze ohne '
                        'Zeitangabe bleiben sichtbar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                            selected: d.venues.contains(v),
                            onSelected: (_) => _toggleVenue(v),
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
                        selected: d.sources.contains(PlaceSource.community),
                        onSelected: (_) => _toggleSource(PlaceSource.community),
                      ),
                      FilterChip(
                        label: const Text('OpenStreetMap'),
                        selected: d.sources.contains(PlaceSource.osm),
                        onSelected: (_) => _toggleSource(PlaceSource.osm),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Fester Fuss: Änderungen wirken ERST mit „Übernehmen". Abbrechen /
          // Zurück / Wegwischen verwerfen den Entwurf.
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.viewPaddingOf(context).bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text(
                      d.isActive
                          ? 'Übernehmen · ${d.activeCount}'
                          : 'Übernehmen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
