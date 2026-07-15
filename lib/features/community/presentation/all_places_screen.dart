import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_providers.dart';
import 'pin_list.dart';

/// Admin-Ansicht ALLER Community-Pins (auch fremde/versteckte) mit Suche +
/// Bearbeiten/Loeschen. Nur ueber die Einstellungen erreichbar, wenn als Admin
/// angemeldet. Serverseitig durch admin_list_places (is_admin) abgesichert.
class AllPlacesScreen extends ConsumerStatefulWidget {
  const AllPlacesScreen({super.key});

  @override
  ConsumerState<AllPlacesScreen> createState() => _AllPlacesScreenState();
}

class _AllPlacesScreenState extends ConsumerState<AllPlacesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminAllPlacesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alle Pins [Admin]')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const PinListEmpty(message: 'Pins konnten nicht geladen werden.'),
        data: (all) {
          if (all.isEmpty) {
            return const PinListEmpty(
              message: 'Keine Community-Pins vorhanden.',
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
                  onRefresh: () async => ref.invalidate(adminAllPlacesProvider),
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
