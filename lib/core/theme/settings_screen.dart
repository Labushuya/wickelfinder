import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        children: [
          _SectionHeader('Darstellung'),
          RadioListTile<ThemeMode>(
            title: const Text('Hell'),
            secondary: const Icon(Icons.light_mode_outlined),
            value: ThemeMode.light,
            groupValue: mode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Dunkel'),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: ThemeMode.dark,
            groupValue: mode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Systemeinstellung folgen'),
            subtitle: const Text('Hell oder dunkel wie dein Gerät'),
            secondary: const Icon(Icons.brightness_auto_outlined),
            value: ThemeMode.system,
            groupValue: mode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
          ),
          const Divider(),
          _SectionHeader('Über'),
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
