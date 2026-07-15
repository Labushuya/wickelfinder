import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/data/auth_repository.dart';

/// Registrierung eines Nutzerkontos. Zwei Wege:
///  - Besteht bereits eine ANONYME Session (der Nutzer hat schon bewertet/
///    gemeldet), wird sie per Identity-Linking zu einem echten Konto
///    aufgewertet -> alle anonymen Beitraege bleiben erhalten (gleiche user_id).
///  - Sonst normale Registrierung (signUp).
/// Beide Wege bestaetigen die E-Mail per 6-stelligem Code (OTP, kein Deep-Link).
class AccountRegisterScreen extends ConsumerStatefulWidget {
  const AccountRegisterScreen({super.key});

  @override
  ConsumerState<AccountRegisterScreen> createState() =>
      _AccountRegisterScreenState();
}

class _AccountRegisterScreenState extends ConsumerState<AccountRegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();

  bool _busy = false;
  String? _error;
  // false = Eingabe E-Mail/Passwort; true = OTP-Code aus der Mail eingeben.
  bool _awaitingOtp = false;
  // true, wenn eine anonyme Session zu einem Konto aufgewertet wird (Linking).
  bool _linking = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    if (_password.text.length < 6) {
      setState(() => _error = 'Passwort mindestens 6 Zeichen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      if (repo.isAnonymous) {
        // Identity-Linking: E-Mail an anonyme Session haengen (loest OTP-Mail aus).
        _linking = true;
        await repo.addEmailToAnonymous(email);
      } else {
        // Normale Registrierung.
        _linking = false;
        await repo.signUp(email, _password.text);
      }
      setState(() => _awaitingOtp = true);
    } on AuthException catch (e) {
      // Linking-Konflikt (E-Mail vergeben) o. Ae. -> ehrliche Meldung.
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Registrierung fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOtp() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await repo.verifyEmailOtp(
        email: _email.text.trim(),
        token: _otp.text.trim(),
        // Beim Linking ist es ein E-Mail-Wechsel, sonst eine Neu-Anmeldung.
        type: _linking ? OtpType.emailChange : OtpType.signup,
      );
      // Beim Linking muss das Passwort NACH der Verifizierung gesetzt werden.
      if (_linking) {
        await repo.setPassword(_password.text);
      }
      ref.invalidate(isAdminProvider);
      if (mounted) navigator.pop(true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Bestätigung fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrieren')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _awaitingOtp ? _buildOtpStep() : _buildEmailStep(),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Erstelle ein kostenloses Konto, um Wickelplätze hinzuzufügen und zu '
          'verwalten. Bereits abgegebene Bewertungen bleiben erhalten.',
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
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Passwort (mind. 6 Zeichen)',
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
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mark_email_read_outlined),
          label: const Text('Bestätigungscode anfordern'),
          onPressed: _busy ? null : _submitEmail,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Wir haben dir einen 6-stelligen Code an ${_email.text.trim()} '
          'geschickt. Gib ihn hier ein, um dein Konto zu bestätigen.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Bestätigungscode',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Konto bestätigen'),
          onPressed: _busy ? null : _submitOtp,
        ),
      ],
    );
  }
}
