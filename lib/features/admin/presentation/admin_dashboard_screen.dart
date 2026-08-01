import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../community/presentation/all_places_screen.dart';
import '../../community/presentation/community_providers.dart';
import '../../community/presentation/photo_review_screen.dart';
import '../../community/presentation/reports_review_screen.dart';
import '../../map/domain/changing_place.dart';

/// Zentrales Admin-Dashboard: Ueberblick (mit Hervorhebung dessen, was
/// Aufmerksamkeit braucht) + Zugang zu allen Verwaltungs-Bereichen. Ersetzt die
/// verstreuten Admin-Menueeintraege. Serverseitig durch is_admin abgesichert
/// (alle Admin-RPCs werfen sonst admin_required).
///
/// Pop-Ergebnis: [ChangingPlace] wenn in „Alle Pins" ein Pin gewaehlt wurde
/// (map_screen fliegt dann dorthin).
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Zaehler je Platz -> Gesamtsummen fuer die Badges auf den Zeilen.
    final counts = ref.watch(adminModerationCountsProvider).valueOrNull;
    final totalPending =
        counts?.values.fold<int>(0, (s, c) => s + c.pendingPhotos) ?? 0;
    final totalReports =
        counts?.values.fold<int>(0, (s, c) => s + c.openReports) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Verwaltung')),
      body: RefreshIndicator(
        onRefresh: () async => refreshModeration(ref),
        child: ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
          ),
          children: [
            // Bereiche — die roten Badges auf den Zeilen tragen die Zahlen
            // (keine separate „Übersicht", die dieselben Werte doppelt zeigt).
            _NavTile(
              icon: Icons.photo_library_outlined,
              title: 'Fotos prüfen',
              subtitle: 'Neue Fotos freigeben oder ablehnen',
              badge: totalPending,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PhotoReviewScreen()),
              ),
            ),
            _NavTile(
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Meldungen',
              subtitle: 'Gemeldete Inhalte prüfen',
              badge: totalReports,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportsReviewScreen()),
              ),
            ),
            _NavTile(
              icon: Icons.list_alt,
              title: 'Alle Pins',
              subtitle: 'Alle Wickelplätze bearbeiten oder löschen',
              onTap: () async {
                final sel = await Navigator.of(context).push<ChangingPlace>(
                  MaterialPageRoute(builder: (_) => const AllPlacesScreen()),
                );
                // Auswahl an map_screen durchreichen -> dort _goTo.
                if (sel != null && context.mounted) {
                  Navigator.of(context).pop(sel);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigations-Zeile mit optionalem Zähler-Badge (hebt Handlungsbedarf hervor).
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
