import 'package:flutter/material.dart';

import '../domain/place_tag.dart';

/// Ergebnis des Bewertungs-Dialogs.
class RatingInput {
  const RatingInput({required this.stars, required this.tags});
  final int stars;
  final Set<PlaceTag> tags;
}

/// Dialog zum Bewerten eines Platzes: 1-5 Sterne (zentriert, gross) +
/// scrollbare Attribut-Tags. Als BottomSheet praesentiert, damit auch bei
/// vielen Tags komfortabel bedienbar.
class RatePlaceDialog extends StatefulWidget {
  const RatePlaceDialog({super.key, this.initialStars, this.initialTags});

  final int? initialStars;
  final Set<PlaceTag>? initialTags;

  /// Zeigt den Dialog als modales BottomSheet und liefert das Ergebnis.
  static Future<RatingInput?> show(
    BuildContext context, {
    int? initialStars,
    Set<PlaceTag>? initialTags,
  }) {
    return showModalBottomSheet<RatingInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          RatePlaceDialog(initialStars: initialStars, initialTags: initialTags),
    );
  }

  @override
  State<RatePlaceDialog> createState() => _RatePlaceDialogState();
}

class _RatePlaceDialogState extends State<RatePlaceDialog> {
  late int _stars = widget.initialStars ?? 0;
  late final Set<PlaceTag> _tags = {...?widget.initialTags};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Hoehe an Tastatur/Inhalt anpassen; max 85% des Screens.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('Platz bewerten', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            // Sterne: zentriert und gross.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    icon: Icon(
                      i <= _stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                    ),
                    color: Colors.amber,
                    tooltip: '$i Sterne',
                    onPressed: () => setState(() => _stars = i),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Eigenschaften (optional)',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Tags: scrollbar, damit auch viele Tags komfortabel passen.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in PlaceTag.values)
                      FilterChip(
                        label: Text(tag.label),
                        selected: _tags.contains(tag),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _tags.add(tag);
                            // Widerspruch aufloesen: Gegen-Tag abwaehlen.
                            final opp = tag.opposite;
                            if (opp != null) _tags.remove(opp);
                          } else {
                            _tags.remove(tag);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _stars == 0
                          ? null
                          : () => Navigator.pop(
                              context,
                              RatingInput(stars: _stars, tags: _tags),
                            ),
                      child: const Text('Absenden'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
