import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

/// Login-Screen fuer den Owner/Admin (E-Mail + Passwort). Erreichbar ueber die
/// Einstellungen. Nach erfolgreichem Login kann der Admin alle Pins verwalten.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _remember = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Gespeicherte Zugangsdaten vorbefuellen (falls "Angemeldet bleiben").
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
      await repo.signInAdminRemember(
        _email.text.trim(),
        _password.text,
        remember: _remember,
      );
      ref.invalidate(isAdminProvider);
      final isAdmin = await repo.checkIsAdmin();
      if (!mounted) return;
      if (isAdmin) {
        navigator.pop();
      } else {
        // Login ok, aber kein Admin -> wieder abmelden (Sicherheit).
        await repo.signOut();
        setState(() => _error = 'Dieser Account hat keine Admin-Rechte.');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Anmeldung fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin-Anmeldung')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
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
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Angemeldet bleiben'),
                subtitle: const Text(
                  'Zugangsdaten verschlüsselt auf dem Gerät',
                ),
                value: _remember,
                onChanged: _busy ? null : (v) => setState(() => _remember = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
