import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/data/auth_repository.dart';
import 'account_register_screen.dart';
import 'account_reset_screen.dart';

/// Login-Screen fuer JEDES Konto (E-Mail + Passwort). Admin-Rechte werden
/// serverseitig (is_admin) erkannt -> Admin-Funktionen erscheinen automatisch,
/// es gibt keinen separaten Admin-Login mehr. Fuehrt zu Registrierung + Reset.
class AccountLoginScreen extends ConsumerStatefulWidget {
  const AccountLoginScreen({super.key});

  @override
  ConsumerState<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends ConsumerState<AccountLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _remember = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Zuletzt gespeicherte Zugangsdaten vorbefuellen (schnelles Wiederanmelden).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = ref.read(authRepositoryProvider);
      final creds = await repo?.savedCredentials();
      if (creds != null && mounted) {
        setState(() {
          _email.text = creds.email;
          _password.text = creds.password;
        });
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      // Ein Login fuer alle; "Angemeldet bleiben" speichert fuer Auto-Login.
      await repo.signInRemember(
        _email.text.trim(),
        _password.text,
        remember: _remember,
      );
      ref.invalidate(isAdminProvider);
      if (mounted) navigator.pop(true);
    } on AuthException catch (e) {
      setState(() => _error = germanAuthError(e));
    } catch (_) {
      setState(() => _error = 'Anmeldung fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anmelden')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Mit einem kostenlosen Konto kannst du Wickelplätze hinzufügen '
                'und deine eigenen Pins verwalten.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Angemeldet bleiben'),
                value: _remember,
                onChanged: _busy ? null : (v) => setState(() => _remember = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Anmelden'),
                onPressed: _busy ? null : _login,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final ok = await navigator.push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const AccountRegisterScreen(),
                          ),
                        );
                        // Bei erfolgreicher Registrierung besteht bereits eine
                        // Session -> Login-Screen selbst schliessen, damit man
                        // zum Aufrufer (Einstellungen/Karte) zurueckkehrt.
                        if (ok == true && mounted) navigator.pop(true);
                      },
                child: const Text('Noch kein Konto? Registrieren'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final ok = await navigator.push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const AccountResetScreen(),
                          ),
                        );
                        // Nach erfolgreichem Reset ist man angemeldet ->
                        // Login-Screen mit schliessen.
                        if (ok == true && mounted) navigator.pop(true);
                      },
                child: const Text('Passwort vergessen?'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final ok = await navigator.push<bool>(
                          MaterialPageRoute(
                            builder: (_) => AccountRegisterScreen(
                              initialEmail: _email.text.trim(),
                              startAtOtp: true,
                            ),
                          ),
                        );
                        if (ok == true && mounted) navigator.pop(true);
                      },
                child: const Text('Bestätigungscode aus E-Mail eingeben'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
