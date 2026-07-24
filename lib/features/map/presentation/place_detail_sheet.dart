import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bottom_toast.dart';
import '../../account/presentation/login_prompt.dart';
import '../../community/data/community_repository.dart';
import '../../admin/data/auth_repository.dart';
import '../../community/domain/place_flag.dart';
import '../../community/domain/place_photo.dart';
import '../../community/domain/place_stats.dart';
import '../../community/domain/place_tag.dart';
import '../../community/presentation/accumulated_places.dart';
import '../../community/presentation/add_place_screen.dart';
import '../../community/presentation/community_providers.dart';
import '../../community/presentation/rate_place_dialog.dart';
import '../domain/changing_place.dart';
import '../domain/opening_hours_format.dart';

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
    // Eigener Melde-/Bestaetigungs-Zustand (fuer stateful Buttons + Toasts).
    final myFlag = ref.watch(myFlagProvider(place.placeRef)).valueOrNull;
    final myConfirmed =
        ref.watch(myConfirmationProvider(place.placeRef)).valueOrNull ?? false;
    final myPhotos =
        ref.watch(myPhotosProvider(place.placeRef)).valueOrNull ?? const [];

    // Bearbeiten/Loeschen anbieten, wenn eigener Community-Pin ODER Admin.
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final isOwner =
        place.source == PlaceSource.community &&
        (ref
                .watch(myPlacesProvider)
                .valueOrNull
                ?.any((p) => p.id == place.id) ??
            false);
    final canManage =
        place.source == PlaceSource.community && (isAdmin || isOwner);

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
                  _PhotoStrip(placeRef: place.placeRef),
                  _RatingSummary(stats: stats),
                  if (myRating != null) ...[
                    const SizedBox(height: 6),
                    _MyRatingRow(rating: myRating),
                  ],
                  const SizedBox(height: 12),
                  _AccessibilityBanner(place: place, stats: stats),
                  if (isOwner)
                    _AuthorHint(
                      place: place,
                      stats: stats,
                      onEdit: () => _edit(context),
                    ),
                  _CommunityConsensus(stats: stats),
                  if (isAdmin) _AdminFeedback(placeRef: place.placeRef),
                  const SizedBox(height: 4),
                  if (place.locationHint != null)
                    _InfoRow(
                      icon: Icons.place_outlined,
                      label: place.locationHint!,
                    ),
                  if (place.openingHours != null)
                    _InfoRow(
                      icon: Icons.schedule,
                      label: formatOpeningHours(place.openingHours!),
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
                  // Existenz-Feedback: fuer JEDEN sichtbar (anonym, kein Konto).
                  // Buttons spiegeln den EIGENEN Zustand (bereits gemeldet /
                  // bestaetigt), damit klar ist, dass eine Stimme pro Person zaehlt.
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(
                            myConfirmed
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                          ),
                          label: Text(
                            myConfirmed ? 'Bestätigt ✓' : 'Doch vorhanden',
                          ),
                          style: myConfirmed
                              ? OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.primary,
                                  backgroundColor: theme
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.3),
                                )
                              : null,
                          onPressed: () => _confirmPresent(
                            context,
                            ref,
                            repo,
                            alreadyConfirmed: myConfirmed,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(
                            myFlag != null
                                ? Icons.report
                                : Icons.report_gmailerrorred_outlined,
                          ),
                          label: Text(
                            myFlag != null ? 'Gemeldet ✓' : 'Nicht vorhanden',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            backgroundColor: myFlag != null
                                ? theme.colorScheme.errorContainer.withValues(
                                    alpha: 0.3,
                                  )
                                : null,
                          ),
                          onPressed: () =>
                              _flag(context, ref, repo, current: myFlag),
                        ),
                      ),
                    ],
                  ),
                  // Foto: hinzufuegen (nur mit Konto), bis zu 3 pro Nutzer.
                  // Loeschen/Melden je Foto laeuft ueber das Vollbild im Strip.
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        myPhotos.length >= 3
                            ? 'Fotos: 3/3'
                            : 'Foto hinzufügen (${myPhotos.length}/3)',
                      ),
                      onPressed: myPhotos.length >= 3
                          ? null
                          : () => _addPhoto(context, ref, repo),
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
      if (context.mounted) showBottomToast(context, 'Platz gelöscht.');
    } catch (_) {
      if (context.mounted) showBottomToast(context, 'Löschen fehlgeschlagen.');
    }
  }

  Future<void> _rate(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo,
    MyRating? existing,
  ) async {
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
        // Koordinaten mitspeichern -> "Meine Bewertungen" kann spaeter
        // zum Platz zurueckfuehren (auch namenlose OSM-Pins).
        lat: place.location.latitude,
        lon: place.location.longitude,
      );
      // Eigene Bewertung + Aggregat + Bewertungsliste neu laden.
      ref.invalidate(myRatingProvider(place.placeRef));
      ref.invalidate(statsProvider(place.placeRef));
      ref.invalidate(myRatingsProvider);
      if (context.mounted) {
        showBottomToast(
          context,
          'Deine ${input.stars}-Sterne-Bewertung wurde gespeichert.',
        );
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) {
        showBottomToast(
          context,
          'Bewertung fehlgeschlagen. Bitte später erneut.',
        );
      }
    }
  }

  /// "Nicht vorhanden melden": erst Grund waehlen, dann Rueckfrage, dann senden.
  /// [current] = bereits abgegebener Grund (null wenn noch nicht gemeldet) ->
  /// steuert Rueckfrage- und Bestaetigungstext.
  Future<void> _flag(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo, {
    FlagReason? current,
  }) async {
    // 1. Grund waehlen (kein 'other' — bewusst weggelassen).
    final reason = await showModalBottomSheet<FlagReason>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Was stimmt mit diesem Platz nicht?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final r in FlagReason.values)
              ListTile(
                title: Text(r.label),
                onTap: () => Navigator.pop(sheetContext, r),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null) return;
    if (!context.mounted) return;

    // 2. Rueckfrage (folgenreiche Aktion).
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(current == null ? 'Meldung absenden?' : 'Meldung ändern?'),
        content: Text(
          current == null
              ? 'Du meldest „${place.name ?? 'diesen Wickelplatz'}" als: '
                    '${reason.label}.'
              : 'Du änderst deine Meldung zu: ${reason.label}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(current == null ? 'Melden' : 'Ändern'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 3. Senden + Refresh (eigener Zustand + Aggregat neu laden).
    try {
      await repo.submitFlag(placeRef: place.placeRef, reason: reason);
      ref.invalidate(statsProvider(place.placeRef));
      ref.invalidate(myFlagProvider(place.placeRef));
      ref.invalidate(myConfirmationProvider(place.placeRef));
      await refreshCommunityDataFromWidget(ref);
      if (context.mounted) {
        showBottomToast(
          context,
          current == null
              ? 'Danke! Als „${reason.label}" gemeldet.'
              : 'Deine Meldung wurde auf „${reason.label}" geändert.',
        );
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) {
        showBottomToast(
          context,
          'Meldung fehlgeschlagen. Bitte später erneut.',
        );
      }
    }
  }

  /// "Doch vorhanden" bestaetigen. [alreadyConfirmed] steuert den Toast.
  Future<void> _confirmPresent(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo, {
    bool alreadyConfirmed = false,
  }) async {
    if (alreadyConfirmed) {
      // Schon bestaetigt -> keine erneute Aktion, nur Hinweis.
      showBottomToast(context, 'Du hast diesen Platz bereits bestätigt.');
      return;
    }
    try {
      await repo.confirmPresent(placeRef: place.placeRef);
      ref.invalidate(statsProvider(place.placeRef));
      ref.invalidate(myConfirmationProvider(place.placeRef));
      ref.invalidate(myFlagProvider(place.placeRef));
      await refreshCommunityDataFromWidget(ref);
      if (context.mounted) {
        showBottomToast(context, 'Danke, als vorhanden bestätigt.');
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) {
        showBottomToast(
          context,
          'Bestätigung fehlgeschlagen. Bitte später erneut.',
        );
      }
    }
  }

  /// Foto hinzufuegen (konto-pflichtig, bis zu 3 pro Platz). Loeschen/Melden
  /// eines EINZELNEN Fotos laeuft ueber das Vollbild (_PhotoViewer).
  Future<void> _addPhoto(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo,
  ) async {
    // Upload braucht ein echtes Konto (nicht anonym).
    if (!ref.read(isLoggedInProvider)) {
      await promptLogin(
        context,
        reason: 'Zum Hinzufügen eines Fotos brauchst du ein kostenloses Konto.',
      );
      return;
    }
    if (context.mounted) await _uploadPhoto(context, ref, repo);
  }

  Future<void> _uploadPhoto(
    BuildContext context,
    WidgetRef ref,
    CommunityRepository repo,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      imageQuality: 90,
    );
    if (picked == null) return;

    if (context.mounted) showBottomToast(context, 'Foto wird hochgeladen …');
    try {
      await repo.uploadPhoto(placeRef: place.placeRef, picked: picked);
      refreshPhotos(ref, place.placeRef);
      if (context.mounted) {
        showBottomToast(
          context,
          'Foto hochgeladen. Es ist nach Freigabe für alle sichtbar.',
        );
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) {
        showBottomToast(context, 'Upload fehlgeschlagen. Bitte später erneut.');
      }
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Dezente Zaehler, worauf der Status beruht (Meldungen / Bestaetigungen).
    final counters = <Widget>[
      if (stats.flagCount > 0) ...[
        const SizedBox(width: 12),
        Icon(Icons.flag_outlined, size: 15, color: theme.colorScheme.error),
        const SizedBox(width: 2),
        Text('${stats.flagCount}', style: muted),
      ],
      if (stats.confirmCount > 0) ...[
        const SizedBox(width: 10),
        Icon(Icons.check, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 2),
        Text('${stats.confirmCount}', style: muted),
      ],
    ];

    // Der Standort-Hinweis ist unabhaengig von vorhandenen Bewertungen.
    final locationHint = stats.locationDisputed
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  Icons.wrong_location_outlined,
                  size: 16,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Standort möglicherweise ungenau',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    if (stats.avgStars == null) {
      // Ohne Bewertungen trotzdem Melde-Zaehler + Standort-Hinweis zeigen.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Noch keine Bewertungen', style: theme.textTheme.bodySmall),
              ...counters,
            ],
          ),
          if (locationHint != null) locationHint,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
              Icon(
                Icons.help_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                'Existenz fraglich',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            ...counters,
          ],
        ),
        if (locationHint != null) locationHint,
      ],
    );
  }
}

/// Admin-only: rohe Melde-/Bestaetigungs-/Bewertungszaehler eines Platzes.
class _AdminFeedback extends ConsumerWidget {
  const _AdminFeedback({required this.placeRef});
  final String placeRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fb = ref.watch(adminPlaceFeedbackProvider(placeRef)).valueOrNull;
    if (fb == null || !fb.hasAny) return const SizedBox.shrink();

    Widget row(IconData icon, Color color, String label, int n) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          Text('$n', style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meldungen (Admin, roh)',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          row(
            Icons.block,
            theme.colorScheme.error,
            'Nicht vorhanden',
            fb.notPresent,
          ),
          row(
            Icons.lock_outline,
            theme.colorScheme.error,
            'Dauerhaft geschlossen',
            fb.closed,
          ),
          row(
            Icons.wrong_location_outlined,
            theme.colorScheme.tertiary,
            'Falscher Ort',
            fb.wrongLocation,
          ),
          if (fb.other > 0)
            row(
              Icons.help_outline,
              theme.colorScheme.onSurfaceVariant,
              'Sonstiges',
              fb.other,
            ),
          row(
            Icons.check_circle_outline,
            theme.colorScheme.primary,
            'Doch vorhanden',
            fb.confirmed,
          ),
          row(Icons.star_outline, Colors.amber, 'Bewertungen', fb.rated),
        ],
      ),
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

    // Kosten-Aussage aus dem dreiwertigen Modell (free/conditional/paid).
    // "Angabe des Eintragenden" macht die Quelle eindeutig (vs. Community).
    final mode = place.effectiveFeeMode;
    switch (mode) {
      case FeeMode.paid:
        parts.add(
          ctx.accessRestricted
              ? '💶 kostenpflichtig (Eintritt)'
              : '💶 kostenpflichtig',
        );
      case FeeMode.free:
        parts.add('✅ kostenlos');
      case FeeMode.conditional:
        parts.add('🎫 kostenlos für Gäste/Kunden');
      case null:
        if (ctx.accessRestricted) parts.add('ℹ️ evtl. Eintritt/Konsum');
    }

    final restricted =
        ctx.accessRestricted ||
        mode == FeeMode.paid ||
        mode == FeeMode.conditional;
    final bg = restricted
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;
    final fg = restricted
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSecondaryContainer;
    final accent = restricted ? AppColors.accent : AppColors.primary;

    // Community-Konsens zu den Kosten gegen die Stammdaten pruefen.
    final free = stats.tagCounts[PlaceTag.freeOfCharge] ?? 0;
    final paid = stats.tagCounts[PlaceTag.paid] ?? 0;
    final verdict = costConsensus(mode, free, paid);

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
                  'Angabe des Eintragenden: ${parts.join('  ·  ')}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (verdict.badge != null) ...[
                const SizedBox(width: 6),
                _TrustBadge(verdict.badge!),
              ],
            ],
          ),
          if (verdict.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Row(
                children: [
                  Icon(verdict.icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      verdict.note!,
                      style: theme.textTheme.bodySmall?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          // Verfuegbarkeits-Hinweis (D): nur wenn der Ort typischerweise
          // Eintritt/Konsum voraussetzt UND keine konkreten OSM-Zeiten vorliegen
          // (echte Zeiten stehen dann bereits als eigene Zeile -> keine Doppelung).
          if (ctx.accessRestricted && place.openingHours == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Meist während der Öffnungszeiten des Lokals zugänglich',
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

  /// Vergleicht die Kosten-Angabe (effectiveFeeMode) mit dem Community-Konsens.
  /// Regel: Stammdaten fuehren; Community relativiert sichtbar (Ampel + Hinweis),
  /// ueberschreibt aber nicht. "bedingt" hat keinen direkten free/paid-Gegenpol
  /// -> nur neutrale Info.
  static _CostConsensus costConsensus(FeeMode? mode, int free, int paid) {
    if (free == 0 && paid == 0) return const _CostConsensus();
    if (mode == FeeMode.paid && free > paid) {
      return _CostConsensus(
        badge: _Trust.disputed,
        note: '⚠ $free× als kostenlos gemeldet',
        icon: Icons.warning_amber,
      );
    }
    if (mode == FeeMode.free && paid > free) {
      return _CostConsensus(
        badge: _Trust.disputed,
        note: '⚠ $paid× als kostenpflichtig gemeldet',
        icon: Icons.warning_amber,
      );
    }
    if (mode == FeeMode.paid && paid > free) {
      return _CostConsensus(
        badge: _Trust.confirmed,
        note: 'von $paid bestätigt',
        icon: Icons.check,
      );
    }
    if (mode == FeeMode.free && free > paid) {
      return _CostConsensus(
        badge: _Trust.confirmed,
        note: 'von $free bestätigt',
        icon: Icons.check,
      );
    }
    return const _CostConsensus();
  }
}

enum _Trust { confirmed, disputed }

/// Ergebnis des Kosten-Konsens-Abgleichs: optionale Ampel + Hinweiszeile.
class _CostConsensus {
  const _CostConsensus({this.badge, this.note, this.icon = Icons.info_outline});
  final _Trust? badge;
  final String? note;
  final IconData icon;

  /// True, wenn die Community der Angabe klar widerspricht (fuer Autor-Hinweis).
  bool get isDisputed => badge == _Trust.disputed;
}

/// Kleines Ampel-Badge: gruen "bestätigt" / gelb "umstritten".
class _TrustBadge extends StatelessWidget {
  const _TrustBadge(this.trust);
  final _Trust trust;

  @override
  Widget build(BuildContext context) {
    final confirmed = trust == _Trust.confirmed;
    final color = confirmed ? Colors.green.shade600 : Colors.amber.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        confirmed ? 'bestätigt' : 'umstritten',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Autor-Hinweis: nur der Ersteller des Pins sieht bei starkem Community-
/// Widerspruch zur Kosten-Angabe einen dezenten "Angabe pruefen?"-Hinweis.
class _AuthorHint extends StatelessWidget {
  const _AuthorHint({
    required this.place,
    required this.stats,
    required this.onEdit,
  });
  final ChangingPlace place;
  final PlaceStats stats;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final free = stats.tagCounts[PlaceTag.freeOfCharge] ?? 0;
    final paid = stats.tagCounts[PlaceTag.paid] ?? 0;
    final verdict = _AccessibilityBanner.costConsensus(
      place.effectiveFeeMode,
      free,
      paid,
    );
    if (!verdict.isDisputed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final other = (free > paid) ? 'kostenlos' : 'kostenpflichtig';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade700.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade700),
        ),
        child: Row(
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 18,
              color: Colors.amber.shade800,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Community meldet oft „$other". Deine Angabe prüfen?',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: onEdit, child: const Text('Bearbeiten')),
          ],
        ),
      ),
    );
  }
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

/// Horizontale Foto-Leiste: freigegebene Fotos + evtl. eigenes (pending mit
/// Badge). Tap -> Vollbild. Leer -> nichts (haelt das Sheet kompakt).
class _PhotoStrip extends ConsumerWidget {
  const _PhotoStrip({required this.placeRef});
  final String placeRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(photosProvider(placeRef)).valueOrNull ?? const [];
    if (photos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final p = photos[i];
            return GestureDetector(
              onTap: () => _openFullscreen(context, p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: p.signedUrl,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 96,
                        height: 96,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 96,
                        height: 96,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    if (p.isPending)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.amber.withValues(alpha: 0.85),
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: const Text(
                            'wartet auf Freigabe',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 9, color: Colors.black),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, PlacePhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewer(photo: photo, placeRef: placeRef),
      ),
    );
  }
}

/// Vollbild-Ansicht eines Fotos mit Zoom + Melden-Aktion.
class _PhotoViewer extends ConsumerWidget {
  const _PhotoViewer({required this.photo, required this.placeRef});
  final PlacePhoto photo;
  final String placeRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (photo.isMine)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Mein Foto entfernen',
              onPressed: () => _delete(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Foto melden',
            onPressed: () => _report(context, ref),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (photo.isPending)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Wartet auf Freigabe – nur für dich sichtbar.',
                  style: TextStyle(color: Colors.amber, fontSize: 13),
                ),
              ),
            Flexible(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: photo.signedUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto entfernen?'),
        content: const Text('Dein Foto wird endgültig gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    try {
      await repo.deleteMyPhoto(photo);
      refreshPhotos(ref, placeRef);
      navigator.pop(); // Vollbild schliessen
      if (context.mounted) showBottomToast(context, 'Foto entfernt.');
    } catch (_) {
      if (context.mounted) {
        showBottomToast(context, 'Entfernen fehlgeschlagen.');
      }
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    const kinds = {
      'pii': 'Zeigt Personen / persönliche Daten',
      'abuse': 'Anstößig / unangemessen',
      'spam': 'Spam / Werbung',
      'other': 'Sonstiges',
    };
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Warum meldest du dieses Foto?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final e in kinds.entries)
              ListTile(
                title: Text(e.value),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null) return;
    try {
      await repo.reportContent(
        placeRef: placeRef,
        kind: kind,
        photoId: photo.id,
      );
      if (context.mounted) {
        showBottomToast(context, 'Danke, zur Prüfung gemeldet.');
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) {
        showBottomToast(context, 'Melden fehlgeschlagen. Bitte später erneut.');
      }
    }
  }
}
