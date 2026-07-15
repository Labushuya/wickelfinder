import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/data/auth_repository.dart';
import '../../features/admin/presentation/admin_login_screen.dart';
import '../../features/community/presentation/all_places_screen.dart';
import 'theme_controller.dart';

/// Einstellungen-Screen. Aktuell: Darstellung (hell/dunkel/System).
/// Modern gegliedert in Sektionen mit Ueberschrift.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
        ),
        children: [
          const _SectionHeader('Darstellung'),
          RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (m) {
              if (m != null) ref.read(themeModeProvider.notifier).set(m);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('Hell'),
                  secondary: Icon(Icons.light_mode_outlined),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dunkel'),
                  secondary: Icon(Icons.dark_mode_outlined),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Systemeinstellung folgen'),
                  subtitle: Text('Hell oder dunkel wie dein Gerät'),
                  secondary: Icon(Icons.brightness_auto_outlined),
                  value: ThemeMode.system,
                ),
              ],
            ),
          ),
          const Divider(),
          _AdminSection(),
          const Divider(),
          const _SectionHeader('Über'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Wickelfinder'),
            subtitle: Text(
              'Wickelplätze finden, bewerten und teilen.\n'
              '© OpenStreetMap-Mitwirkende',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Admin-Bereich: Login (E-Mail/Passwort) bzw. Status + Logout.
class _AdminSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(authRepositoryProvider);
    if (repo == null) return const SizedBox.shrink();
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Verwaltung'),
        if (isAdmin) ...[
          ListTile(
            leading: const Icon(Icons.verified_user, color: Colors.green),
            title: const Text('Als Admin angemeldet'),
            subtitle: const Text('Du kannst alle Pins bearbeiten und löschen.'),
            trailing: TextButton(
              onPressed: () async {
                await repo.signOut();
                ref.invalidate(isAdminProvider);
              },
              child: const Text('Abmelden'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('Alle Pins [Admin]'),
            subtitle: const Text(
              'Alle Community-Pins durchsuchen & verwalten.',
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AllPlacesScreen())),
          ),
        ] else
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Admin-Anmeldung'),
            subtitle: const Text('Für Betreiber: alle Pins verwalten.'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AdminLoginScreen())),
          ),
      ],
    );
  }
}

/// Beim ersten Start: fragen, ob die App dem System-Hell/Dunkel folgen soll.
/// Wird nur gezeigt, wenn der Nutzer noch keine Wahl getroffen hat.
Future<void> maybeShowThemeFirstRun(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(themeModeProvider.notifier);
  if (controller.hasChosen) return;

  final follow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Darstellung'),
      content: const Text(
        'Soll Wickelfinder dem Hell-/Dunkel-Modus deines Geräts folgen?\n\n'
        'Du kannst das jederzeit in den Einstellungen ändern.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nein, immer hell'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ja, System folgen'),
        ),
      ],
    ),
  );
  await controller.set(follow ?? false ? ThemeMode.system : ThemeMode.light);
}
