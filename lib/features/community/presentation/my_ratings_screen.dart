import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/bottom_toast.dart';
import '../data/community_repository.dart';
import 'community_providers.dart';
import 'pin_list.dart';
import 'rate_place_dialog.dart';

/// „Meine Bewertungen": alle vom Nutzer bewerteten Plaetze, um sie spaeter
/// wiederzufinden und die eigene Bewertung direkt zu aendern. Tippen auf einen
/// Eintrag oeffnet den Bewertungs-Dialog (Direkt-Edit); ein Karten-Symbol
/// springt zum Platz, sofern Koordinaten vorliegen.
///
/// Pop-Ergebnis: [LatLng] wenn der Nutzer „auf Karte zeigen" gewaehlt hat.
class MyRatingsScreen extends ConsumerStatefulWidget {
  const MyRatingsScreen({super.key});

  @override
  ConsumerState<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends ConsumerState<MyRatingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myRatingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Bewertungen')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const PinListEmpty(
          message: 'Bewertungen konnten nicht geladen werden.',
        ),
        data: (all) {
          if (all.isEmpty) {
            return const PinListEmpty(
              message: 'Du hast noch keine Wickelplätze bewertet.',
            );
          }
          // Lokale Suche ueber den (aufgeloesten) Namen.
          final q = _query.trim().toLowerCase();
          final items = q.isEmpty
              ? all
              : all
                    .where(
                      (r) =>
                          (r.place?.name ?? '').toLowerCase().contains(q) ||
                          (r.place?.locationHint ?? '').toLowerCase().contains(
                            q,
                          ),
                    )
                    .toList(growable: false);

          return Column(
            children: [
              PinSearchField(onChanged: (v) => setState(() => _query = v)),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myRatingsProvider),
                  child: items.isEmpty
                      ? const PinListEmpty(message: 'Keine Treffer.')
                      : ListView.separated(
                          padding: EdgeInsets.only(
                            bottom:
                                MediaQuery.viewPaddingOf(context).bottom + 12,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _RatingTile(
                            rated: items[i],
                            onEdit: () => _edit(items[i]),
                            onShowOnMap: items[i].entry.hasCoords
                                ? () => Navigator.of(context).pop(
                                    LatLng(
                                      items[i].entry.lat!,
                                      items[i].entry.lon!,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(RatedPlace rated) async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    final input = await RatePlaceDialog.show(
      context,
      initialStars: rated.entry.rating.stars,
      initialTags: rated.entry.rating.tags,
    );
    if (input == null) return;
    try {
      await repo.submitRating(
        placeRef: rated.entry.placeRef,
        stars: input.stars,
        tags: input.tags,
        // Vorhandene Koordinaten erneut mitsenden (bleiben so erhalten).
        lat: rated.entry.lat,
        lon: rated.entry.lon,
      );
      ref.invalidate(myRatingsProvider);
      ref.invalidate(myRatingProvider(rated.entry.placeRef));
      ref.invalidate(statsProvider(rated.entry.placeRef));
      if (context.mounted) {
        showBottomToast(context, 'Bewertung aktualisiert.');
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) {
        showBottomToast(context, 'Aktualisieren fehlgeschlagen.');
      }
    }
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({
    required this.rated,
    required this.onEdit,
    this.onShowOnMap,
  });

  final RatedPlace rated;
  final VoidCallback onEdit;
  final VoidCallback? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = rated.place;
    final hasName = place?.name != null && place!.name!.trim().isNotEmpty;
    final title = hasName ? place!.name! : 'Wickelplatz (ohne Namen)';

    // Sterne kompakt darstellen.
    final stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rated.entry.rating.stars
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            size: 16,
            color: Colors.amber,
          ),
      ],
    );

    return ListTile(
      leading: const Icon(Icons.star_rate_rounded),
      title: Row(
        children: [
          Flexible(child: Text(title)),
          if (!hasName) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Ohne Namen'),
                  content: const Text(
                    'Für diesen Platz liegt kein Name vor (z. B. ein '
                    'OpenStreetMap-Eintrag ohne Namensangabe). Der Name wurde '
                    'daher generisch erzeugt. Über das Karten-Symbol findest '
                    'du den Platz trotzdem wieder.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: Icon(
                Icons.info_outline,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      subtitle: stars,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onShowOnMap != null)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Auf Karte zeigen',
              onPressed: onShowOnMap,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Bewertung ändern',
            onPressed: onEdit,
          ),
        ],
      ),
      onTap: onEdit,
    );
  }
}
