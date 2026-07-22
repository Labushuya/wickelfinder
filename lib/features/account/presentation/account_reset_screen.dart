import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/data/auth_repository.dart';

/// Passwort-Reset: E-Mail anfordern -> Code aus der Mail eingeben
/// -> neues Passwort setzen. Kein Deep-Link noetig (OTP-Weg, type=recovery).
class AccountResetScreen extends ConsumerStatefulWidget {
  const AccountResetScreen({super.key});

  @override
  ConsumerState<AccountResetScreen> createState() => _AccountResetScreenState();
}

class _AccountResetScreenState extends ConsumerState<AccountResetScreen> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _awaitingOtp = false;
  // true, sobald der OTP-Code EINMAL verifiziert wurde (Recovery-Session steht).
  // Verhindert, dass ein fehlgeschlagenes setPassword den bereits verbrauchten
  // Token erneut verifizieren will ("Token has expired").
  bool _otpVerified = false;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.resetPassword(_email.text.trim());
      setState(() => _awaitingOtp = true);
    } on AuthException catch (e) {
      setState(() => _error = germanAuthError(e));
    } catch (_) {
      setState(() => _error = 'Anforderung fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    if (_newPassword.text.length < 6) {
      setState(() => _error = 'Passwort mindestens 6 Zeichen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // OTP nur EINMAL einloesen — danach steht die Recovery-Session, und ein
      // erneuter setPassword-Versuch (z. B. nach "gleiches Passwort") braucht
      // den Token nicht mehr.
      if (!_otpVerified) {
        await repo.verifyEmailOtp(
          email: _email.text.trim(),
          token: _otp.text.trim(),
          type: OtpType.recovery,
        );
        _otpVerified = true;
      }
      await repo.setPassword(_newPassword.text);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Passwort geändert. Du bist angemeldet.')),
      );
      navigator.pop(true);
    } on AuthException catch (e) {
      setState(() => _error = germanAuthError(e));
    } catch (_) {
      setState(() => _error = 'Zurücksetzen fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passwort zurücksetzen')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _awaitingOtp ? _buildOtpStep() : _buildRequestStep(),
        ),
      ),
    );
  }

  Widget _buildRequestStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Gib deine E-Mail ein. Wir senden dir einen Code zum Zurücksetzen.',
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
              : const Icon(Icons.mail_outline),
          label: const Text('Code anfordern'),
          onPressed: _busy ? null : _requestReset,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _otpVerified
              ? 'Code bestätigt. Wähle jetzt dein neues Passwort.'
              : 'Code aus der Mail an ${_email.text.trim()} eingeben und neues Passwort setzen.',
        ),
        const SizedBox(height: 20),
        // Nach erfolgreicher Verifizierung ist der Code nicht mehr nötig.
        if (!_otpVerified) ...[
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Code',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _newPassword,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Neues Passwort (mind. 6 Zeichen)',
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
              : const Icon(Icons.check),
          label: const Text('Passwort setzen'),
          onPressed: _busy ? null : _confirmReset,
        ),
      ],
    );
  }
}
