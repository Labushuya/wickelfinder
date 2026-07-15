import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../community/data/community_repository.dart';
import '../../admin/data/auth_repository.dart';
import '../../community/domain/place_stats.dart';
import '../../community/domain/place_tag.dart';
import '../../community/presentation/accumulated_places.dart';
import '../../community/presentation/add_place_screen.dart';
import '../../community/presentation/community_providers.dart';
import '../../community/presentation/rate_place_dialog.dart';
import '../domain/changing_place.dart';

/// Bottom-Sheet mit Details zu einem Wickelplatz inkl. Community-Bewertung.
class PlaceDetailSheet extends ConsumerWidget {
  const PlaceDetailSheet({super.key, required this.place});

  final ChangingPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(communityRepositoryProvider);
    // Immer die FRISCHESTE Version des Pins aus dem Akkumulator lesen, damit
    // Admin-/Eigen-Edits sofort sichtbar sind (nicht die beim Oeffnen
    // uebergebene, evtl. veraltete Instanz).
    final place =
        ref.watch(accumulatedPlacesProvider).byRef[this.place.placeRef] ??
        this.place;
    final statsAsync = ref.watch(statsProvider(place.placeRef));
    final stats = statsAsync.valueOrNull ?? PlaceStats.empty(place.placeRef);
    final myRating = ref.watch(myRatingProvider(place.placeRef)).valueOrNull;

    // Bearbeiten/Loeschen anbieten, wenn eigener Community-Pin ODER Admin.
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final canManage =
        place.source == PlaceSource.community &&
        (isAdmin ||
            (ref
                    .watch(myPlacesProvider)
                    .valueOrNull
                    ?.any((p) => p.id == place.id) ??
                false));

    final media = MediaQuery.of(context);
    // Hoehe deckeln (max 85% Screen) und Inhalt scrollen lassen, damit bei
    // vielen Chips/Bannern die Aktions-Buttons NICHT hinter die Softkeys/
    // Gestenleiste rutschen. Buttons bleiben unten fixiert (ausserhalb des
    // Scroll-Bereichs) und immer klickbar.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scrollbarer Info-Bereich.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name ?? 'Wickelplatz',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _RatingSummary(stats: stats),
                  if (myRating != null) ...[
                    const SizedBox(height: 6),
                    _MyRatingRow(rating: myRating),
                  ],
                  const SizedBox(height: 12),
                  _AccessibilityBanner(place: place, stats: stats),
                  _CommunityConsensus(stats: stats),
                  const SizedBox(height: 4),
                  if (place.locationHint != null)
                    _InfoRow(
                      icon: Icons.place_outlined,
                      label: place.locationHint!,
                    ),
                  if (place.wheelchairAccessible != null)
                    _InfoRow(
                      icon: Icons.accessible,
                      label: place.wheelchairAccessible!
                          ? 'Barrierefrei zugänglich'
                          : 'Nicht barrierefrei',
                    ),
                  _InfoRow(
                    icon: Icons.source_outlined,
                    label: place.source == PlaceSource.osm
                        ? 'Quelle: OpenStreetMap'
                        : 'Quelle: Community',
                  ),
                ],
              ),
            ),
          ),
          // Aktions-Buttons unten fixiert, mit Softkey-/Gesten-Inset.
          if (repo != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + media.viewPadding.bottom + media.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.star_outline),
                      label: Text(
                        myRating == null ? 'Bewerten' : 'Bewertung ändern',
                      ),
                      onPressed: () => _rate(context, ref, repo, myRating),
                    ),
                  ),
                  if (canManage) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Bearbeiten'),
                            onPressed: () => _edit(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Löschen'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                            onPressed: () => _delete(context, ref, repo),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    // Detail-Sheet NICHT schliessen: AddPlaceScreen wird darueber gepusht.
    // Nach dem Speichern (pop) liegt das Sheet wieder oben und liest den Pin
    // LIVE aus accumulatedPlacesProvider (vom Refresh in _save aktualisiert)
    // -> man landet auf der Pin-Detailansicht, nicht auf der Karte.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AddPlaceScreen(initialCenter: place.location, editPlace: place),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
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
    try {
      await repo.deletePlace(place.id);
      await refreshCommunityDataFromWidget(ref);
      navigator.pop(); // Detail-Sheet schliessen
      messenger.showSnackBar(const SnackBar(content: Text('Platz gelöscht.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Löschen fehlgeschlagen.')),
      );
    }
  }

  Future<void> _rate(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo,
    MyRating? existing,
  ) async {
    // Messenger VOR dem await erfassen -> kein BuildContext-Zugriff nach async gap.
    final messenger = ScaffoldMessenger.of(context);
    // Vorherige Bewertung vorbefuellen (Aendern statt leer starten).
    final input = await RatePlaceDialog.show(
      context,
      initialStars: existing?.stars,
      initialTags: existing?.tags,
    );
    if (input == null) return;

    try {
      await repo.submitRating(
        placeRef: place.placeRef,
        stars: input.stars,
        tags: input.tags,
      );
      // Eigene Bewertung + Aggregat neu laden -> Anzeige aktualisiert sich.
      ref.invalidate(myRatingProvider(place.placeRef));
      ref.invalidate(statsProvider(place.placeRef));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Deine ${input.stars}-Sterne-Bewertung wurde gespeichert.',
          ),
        ),
      );
    } on CommunityException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bewertung fehlgeschlagen. Bitte später erneut.'),
        ),
      );
    }
  }
}

/// Zeigt Sternschnitt + Anzahl Bewertungen; Hinweis bei "fraglich".
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.stats});
  final PlaceStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stats.avgStars == null) {
      return Text('Noch keine Bewertungen', style: theme.textTheme.bodySmall);
    }
    return Row(
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 20),
        const SizedBox(width: 4),
        Text(
          stats.avgStars!.toStringAsFixed(1),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(width: 6),
        Text('(${stats.ratingCount})', style: theme.textTheme.bodySmall),
        if (stats.isQuestionable) ...[
          const SizedBox(width: 12),
          Icon(Icons.help_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 4),
          Text(
            'Existenz fraglich',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// Zeigt die EIGENE Bewertung (unverfaelscht) + gewaehlte Tags.
class _MyRatingRow extends StatelessWidget {
  const _MyRatingRow({required this.rating});
  final MyRating rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Deine Bewertung: ', style: theme.textTheme.bodySmall),
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= rating.stars
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 18,
                color: Colors.amber,
              ),
          ],
        ),
        if (rating.tags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Deine Einschätzung:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in rating.tags)
                  Chip(
                    label: Text(t.label),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

/// Kombinierte Zugaenglichkeits-Einschaetzung: Kontext (Schwimmbad/Restaurant/…)
/// + Kosten (Stammdaten) + Community-Konsens-Abgleich bei den Kosten.
class _AccessibilityBanner extends StatelessWidget {
  const _AccessibilityBanner({required this.place, required this.stats});
  final ChangingPlace place;
  final PlaceStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctx = place.venueContext;
    final parts = <String>['${ctx.emoji} ${ctx.label}'];

    // Kosten-Aussage (Stammdaten des Ortes), ggf. mit Kontext-Hinweis.
    // Bewusst als "laut Angaben" formuliert -> klar von der subjektiven
    // Community-Bewertung (Chips unten) abgegrenzt, kein Widerspruch.
    if (place.fee == true) {
      parts.add(
        ctx.accessRestricted
            ? '💶 laut Angaben kostenpflichtig (Eintritt)'
            : '💶 laut Angaben kostenpflichtig',
      );
    } else if (place.fee == false) {
      parts.add('✅ laut Angaben kostenlos');
    } else if (ctx.accessRestricted) {
      // fee unbekannt, aber Ort setzt typischerweise Eintritt/Konsum voraus.
      parts.add('ℹ️ evtl. Eintritt/Konsum');
    }

    final restricted = ctx.accessRestricted || place.fee == true;
    final bg = restricted
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;
    final fg = restricted
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSecondaryContainer;
    // Brand-Akzent als markanter Rahmen/Icon — hebt das Banner klar vom
    // Hintergrund ab, ohne die (WCAG-gepruefte) Textfarbe fg zu aendern.
    final accent = restricted ? AppColors.accent : AppColors.primary;

    // Community-Konsens zu den Kosten gegen die Stammdaten pruefen.
    final free = stats.tagCounts[PlaceTag.freeOfCharge] ?? 0;
    final paid = stats.tagCounts[PlaceTag.paid] ?? 0;
    final costNote = _costConsensusNote(place.fee, free, paid);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                restricted ? Icons.info_outline : Icons.check_circle_outline,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  parts.join('  ·  '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (costNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Row(
                children: [
                  Icon(costNote.icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      costNote.text,
                      style: theme.textTheme.bodySmall?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Vergleicht die Kosten-Stammdaten (place.fee) mit dem Community-Konsens.
  /// - Widerspruch (Mehrheit taggt Gegenteil) -> Warnhinweis ("Community
  ///   gewinnt sichtbar").
  /// - Bestaetigung -> dezente "von N bestaetigt"-Zeile.
  /// - Kein/unklares Feedback -> null (keine Zusatzzeile).
  static _CostNote? _costConsensusNote(bool? fee, int free, int paid) {
    if (free == 0 && paid == 0) return null;
    if (fee == true && free > paid) {
      return _CostNote('⚠ $free× als kostenlos gemeldet', Icons.warning_amber);
    }
    if (fee == false && paid > free) {
      return _CostNote(
        '⚠ $paid× als kostenpflichtig gemeldet',
        Icons.warning_amber,
      );
    }
    // Bestaetigung durch die Mehrheit.
    if (fee == true && paid > free) {
      return _CostNote('von $paid bestätigt', Icons.check);
    }
    if (fee == false && free > paid) {
      return _CostNote('von $free bestätigt', Icons.check);
    }
    return null;
  }
}

/// Kleiner Wert-Traeger fuer die Kosten-Konsens-Zeile.
class _CostNote {
  const _CostNote(this.text, this.icon);
  final String text;
  final IconData icon;
}

/// Kompakte Konsens-Zeile: zeigt die haeufigsten Community-Tags mit Zaehler
/// (max 6), ohne Textwueste. Faktische Transparenz fuer alle Tags, fuer die
/// es kein Stammdaten-Pendant gibt (Sauberkeit, Windeleimer, Platz, …).
class _CommunityConsensus extends StatelessWidget {
  const _CommunityConsensus({required this.stats});
  final PlaceStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Kosten-Tags fliessen bereits ins Banner -> hier ausblenden.
    final entries =
        stats.tagCounts.entries
            .where(
              (e) =>
                  e.value > 0 &&
                  e.key != PlaceTag.freeOfCharge &&
                  e.key != PlaceTag.paid,
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    final top = entries.take(6);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Von der Community:',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in top)
                Chip(label: Text('${e.key.label} ·  ${e.value}')),
            ],
          ),
        ],
      ),
    );
  }
}
