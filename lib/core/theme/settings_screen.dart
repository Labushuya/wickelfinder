import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/account/presentation/account_login_screen.dart';
import '../../features/admin/data/auth_repository.dart';
import '../../features/admin/presentation/admin_login_screen.dart';
import '../../features/privacy/data/account_repository.dart';
import '../../features/privacy/presentation/privacy_screen.dart';
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
          _AccountSection(),
          const Divider(),
          _AdminSection(),
          const Divider(),
          _MyDataSection(),
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
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Datenschutz'),
            subtitle: const Text('Datenschutzerklärung ansehen'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PrivacyScreen())),
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

/// Konto-Bereich fuer normale Nutzer: Anmelden/Registrieren bzw. angemeldet-
/// als + Abmelden. Ein Konto schaltet Pins-Erstellen/-Verwalten frei.
class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(authRepositoryProvider);
    if (repo == null) return const SizedBox.shrink();
    final email = ref.watch(currentAccountEmailProvider);
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    // Admin wird in der Verwaltungs-Sektion behandelt -> hier nicht doppeln.
    if (isAdmin) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Konto'),
        if (email != null)
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Angemeldet'),
            subtitle: Text(email),
            trailing: TextButton(
              onPressed: () async {
                await repo.signOut();
                ref.invalidate(isAdminProvider);
              },
              child: const Text('Abmelden'),
            ),
          )
        else
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Anmelden / Registrieren'),
            subtitle: const Text('Fürs Hinzufügen und Verwalten eigener Pins.'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountLoginScreen()),
            ),
          ),
      ],
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
        if (isAdmin)
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
          )
        else
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

/// DSGVO-Bereich „Meine Daten": Export (Auskunft/Portabilitaet) + vollstaendige
/// Loeschung (inkl. Auth-Konto). Nur sichtbar, wenn eine Identitaet existiert
/// (ohne Beitrag fallen keine Daten an).
class _MyDataSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MyDataSection> createState() => _MyDataSectionState();
}

class _MyDataSectionState extends ConsumerState<_MyDataSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountRepositoryProvider);
    if (repo == null || !repo.hasIdentity) return const SizedBox.shrink();
    // Admin-Konten koennen sich nicht selbst loeschen (Backend-Guard) ->
    // Loesch-Option ausblenden. Export bleibt fuer alle verfuegbar.
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Meine Daten'),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Meine Daten exportieren'),
          subtitle: const Text(
            'Vollständige Kopie als JSON (Auskunft/Mitnahme).',
          ),
          enabled: !_busy,
          onTap: _busy ? null : () => _export(repo),
        ),
        if (!isAdmin)
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Meine Daten & Konto löschen',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text(
              'Löscht alle deine Daten und dein Konto — unwiderruflich.',
            ),
            enabled: !_busy,
            onTap: _busy ? null : () => _confirmDelete(repo),
          ),
      ],
    );
  }

  Future<void> _export(AccountRepository repo) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await repo.exportMyDataToFile();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Export erstellt — zum Ansehen/Teilen geöffnet.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Export fehlgeschlagen. Bitte später erneut.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(AccountRepository repo) async {
    // Erste Bestaetigung: Klartext, was passiert + Export-Empfehlung.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Alle Daten & Konto löschen?'),
        content: const Text(
          'Es werden unwiderruflich gelöscht:\n'
          '• deine Bewertungen, Meldungen und Bestätigungen\n'
          '• alle von dir angelegten Plätze (inkl. der Bewertungen anderer dazu)\n'
          '• dein Konto (anonyme Kennung)\n\n'
          'Tipp: Exportiere deine Daten vorher.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // Zweite Bestaetigung: Wort "LÖSCHEN" tippen.
    final controller = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Endgültig bestätigen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tippe zur Bestätigung das Wort LÖSCHEN ein:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'LÖSCHEN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim().toUpperCase() == 'LÖSCHEN',
            ),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await repo.deleteMyAccount();
      ref.invalidate(isAdminProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Alle Daten und dein Konto wurden gelöscht.'),
        ),
      );
      navigator.pop(); // zurück zur Karte
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Löschung fehlgeschlagen. Bitte später erneut.'),
        ),
      );
      if (mounted) setState(() => _busy = false);
    }
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
