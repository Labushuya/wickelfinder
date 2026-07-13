import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../community/data/community_repository.dart';
import '../../admin/data/auth_repository.dart';
import '../../community/domain/place_stats.dart';
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
    final statsAsync = ref.watch(statsProvider(place.placeRef));
    final stats = statsAsync.valueOrNull ?? PlaceStats.empty(place.placeRef);

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

    return Padding(
      // Explizites Bottom-Inset fuer Softkeys/Gesten-Bar (edge-to-edge) +
      // ggf. Tastatur. useSafeArea allein reicht auf Android 15+ nicht.
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 +
            MediaQuery.viewPaddingOf(context).bottom +
            MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place.name ?? 'Wickelplatz', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _RatingSummary(stats: stats),
          const SizedBox(height: 12),
          _AccessibilityBanner(place: place),
          const SizedBox(height: 4),
          if (place.locationHint != null)
            _InfoRow(icon: Icons.place_outlined, label: place.locationHint!),
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
          if (repo != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.star_outline),
                label: const Text('Bewerten'),
                onPressed: () => _rate(context, ref, repo),
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
                      onPressed: () => _edit(context, ref),
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
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    navigator.pop(); // Detail-Sheet schliessen
    final changed = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AddPlaceScreen(initialCenter: place.location, editPlace: place),
      ),
    );
    if (changed ?? false) {
      await refreshCommunityDataFromWidget(ref);
    }
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
  ) async {
    // Messenger VOR dem await erfassen -> kein BuildContext-Zugriff nach async gap.
    final messenger = ScaffoldMessenger.of(context);
    final input = await RatePlaceDialog.show(context);
    if (input == null) return;

    try {
      await repo.submitRating(
        placeRef: place.placeRef,
        stars: input.stars,
        tags: input.tags,
      );
      // Frische Stats laden -> Anzeige aktualisiert sich.
      ref.invalidate(statsProvider(place.placeRef));
      messenger.showSnackBar(
        const SnackBar(content: Text('Danke für deine Bewertung!')),
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
/// + Kosten. Beantwortet "komme ich hier ohne Weiteres rein?".
class _AccessibilityBanner extends StatelessWidget {
  const _AccessibilityBanner({required this.place});
  final ChangingPlace place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctx = place.venueContext;
    final parts = <String>['${ctx.emoji} ${ctx.label}'];

    // Kosten-Aussage, ggf. mit Kontext-Hinweis.
    if (place.fee == true) {
      parts.add(
        ctx.accessRestricted
            ? '💶 kostenpflichtig (Eintritt)'
            : '💶 kostenpflichtig',
      );
    } else if (place.fee == false) {
      parts.add('✅ kostenlos');
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        parts.join('  ·  '),
        style: theme.textTheme.bodyMedium?.copyWith(color: fg),
      ),
    );
  }
}
