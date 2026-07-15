import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_providers.dart';
import 'pin_list.dart';

/// Zeigt die vom Nutzer selbst erstellten Wickelplaetze mit Suche + der
/// Moeglichkeit, sie zu bearbeiten oder zu loeschen.
class MyPlacesScreen extends ConsumerStatefulWidget {
  const MyPlacesScreen({super.key});

  @override
  ConsumerState<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends ConsumerState<MyPlacesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myPlacesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Pins')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const PinListEmpty(
          message: 'Deine Pins konnten nicht geladen werden.',
        ),
        data: (all) {
          if (all.isEmpty) {
            return const PinListEmpty(
              message: 'Du hast noch keine Wickelplätze gemeldet.',
              showAddHint: true,
            );
          }
          final places = all
              .where((p) => pinMatchesQuery(p, _query))
              .toList(growable: false);
          return Column(
            children: [
              PinSearchField(onChanged: (v) => setState(() => _query = v)),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myPlacesProvider),
                  child: places.isEmpty
                      ? const PinListEmpty(message: 'Keine Treffer.')
                      : ListView.separated(
                          padding: EdgeInsets.only(
                            bottom:
                                MediaQuery.viewPaddingOf(context).bottom + 12,
                          ),
                          itemCount: places.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => PlaceTile(place: places[i]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
