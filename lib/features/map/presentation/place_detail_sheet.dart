import 'package:flutter/material.dart';

import '../domain/changing_place.dart';

/// Bottom-Sheet mit Details zu einem Wickelplatz.
class PlaceDetailSheet extends StatelessWidget {
  const PlaceDetailSheet({super.key, required this.place});

  final ChangingPlace place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            place.name ?? 'Wickelplatz',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (place.locationHint != null)
            _InfoRow(icon: Icons.place_outlined, label: place.locationHint!),
          if (place.wheelchairAccessible != null)
            _InfoRow(
              icon: Icons.accessible,
              label: place.wheelchairAccessible!
                  ? 'Barrierefrei zugänglich'
                  : 'Nicht barrierefrei',
            ),
          if (place.fee != null)
            _InfoRow(
              icon: Icons.euro_outlined,
              label: place.fee! ? 'Kostenpflichtig' : 'Kostenlos',
            ),
          _InfoRow(
            icon: Icons.source_outlined,
            label: place.source == PlaceSource.osm
                ? 'Quelle: OpenStreetMap'
                : 'Quelle: Community',
          ),
        ],
      ),
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
