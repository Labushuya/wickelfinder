import 'package:flutter/material.dart';

import '../domain/place_tag.dart';

/// Ergebnis des Bewertungs-Dialogs.
class RatingInput {
  const RatingInput({required this.stars, required this.tags});
  final int stars;
  final Set<PlaceTag> tags;
}

/// Dialog zum Bewerten eines Platzes: 1-5 Sterne + optionale Attribut-Tags.
/// Gibt beim Absenden ein [RatingInput] zurueck, sonst null (Abbruch).
class RatePlaceDialog extends StatefulWidget {
  const RatePlaceDialog({super.key, this.initialStars, this.initialTags});

  final int? initialStars;
  final Set<PlaceTag>? initialTags;

  static Future<RatingInput?> show(
    BuildContext context, {
    int? initialStars,
    Set<PlaceTag>? initialTags,
  }) {
    return showDialog<RatingInput>(
      context: context,
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
    return AlertDialog(
      title: const Text('Platz bewerten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sterne-Auswahl
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  icon: Icon(
                    i <= _stars ? Icons.star : Icons.star_border,
                    size: 36,
                  ),
                  color: Colors.amber,
                  tooltip: '$i Sterne',
                  onPressed: () => setState(() => _stars = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Eigenschaften (optional)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in PlaceTag.values)
                FilterChip(
                  label: Text(tag.label),
                  selected: _tags.contains(tag),
                  onSelected: (sel) =>
                      setState(() => sel ? _tags.add(tag) : _tags.remove(tag)),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _stars == 0
              ? null
              : () => Navigator.pop(
                  context,
                  RatingInput(stars: _stars, tags: _tags),
                ),
          child: const Text('Absenden'),
        ),
      ],
    );
  }
}
