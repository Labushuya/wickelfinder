import 'package:flutter/material.dart';

import 'account_login_screen.dart';

/// Zeigt einen Hinweis + CTA zum Anmelden/Registrieren, wenn eine
/// konto-pflichtige Aktion (Pin melden, Foto hochladen) ohne Konto versucht
/// wird, und oeffnet bei Zustimmung den Login-Screen.
///
/// Zentral, damit map_screen (Pin melden) und das Detail-Sheet (Foto) denselben
/// Flow nutzen. [reason] passt den Hinweistext an die Aktion an.
Future<void> promptLogin(
  BuildContext context, {
  String reason =
      'Zum Melden und Verwalten von Wickelplätzen brauchst du ein '
      'kostenloses Konto. Bewerten geht auch ohne.',
}) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewPaddingOf(ctx).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Konto benötigt', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(reason),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Anmelden / Registrieren'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ),
        ],
      ),
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountLoginScreen()));
  }
}
