import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/data/auth_repository.dart';

/// Registrierung eines Nutzerkontos. Zwei Wege:
///  - Besteht bereits eine ANONYME Session (der Nutzer hat schon bewertet/
///    gemeldet), wird sie per Identity-Linking zu einem echten Konto
///    aufgewertet -> alle anonymen Beitraege bleiben erhalten (gleiche user_id).
///  - Sonst normale Registrierung (signUp).
/// Beide Wege bestaetigen die E-Mail per Code (OTP, kein Deep-Link).
///
/// [startAtOtp] springt direkt in den Code-Eingabe-Schritt (mit [initialEmail]
/// vorbelegt). Das ist der "Code nachtragen"-Weg vom Login-Screen: wurde die
/// Registrierung unterbrochen (z.B. versehentliches Zurueck-Tippen), ist der
/// per Mail versendete Code so weiterhin einloesbar, ohne neu zu registrieren.
class AccountRegisterScreen extends ConsumerStatefulWidget {
  const AccountRegisterScreen({
    super.key,
    this.initialEmail,
    this.startAtOtp = false,
  });

  /// Vorbelegung des E-Mail-Feldes (z.B. aus dem Login-Screen uebernommen).
  final String? initialEmail;

  /// Wenn true, startet der Screen direkt im OTP-Schritt (Code nachtragen).
  final bool startAtOtp;

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
  // true im "Code nachtragen"-Modus: Registrierung lief schon, nur der Code
  // fehlt noch. Dann ist KEIN Passwort-Setzen noetig (bei signUp bereits gesetzt).
  bool _resumeOtp = false;

  @override
  void initState() {
    super.initState();
    if (widget.startAtOtp) {
      // Direkt in den Code-Schritt springen (Code nachtragen nach Abbruch).
      _email.text = widget.initialEmail?.trim() ?? '';
      _awaitingOtp = true;
      _linking = false;
      _resumeOtp = true;
    } else if (widget.initialEmail != null) {
      _email.text = widget.initialEmail!.trim();
    }
  }

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
    final navigator = Navigator.of(context);
    try {
      if (repo.isAnonymous) {
        // Identity-Linking: E-Mail an anonyme Session haengen (loest OTP-Mail aus).
        _linking = true;
        await repo.addEmailToAnonymous(email);
        setState(() => _awaitingOtp = true);
      } else {
        // Normale Registrierung. Rueckgabe AUSWERTEN, damit ein stiller Erfolg
        // (Confirm-Email deaktiviert / E-Mail bereits vergeben) nicht als
        // "Mail unterwegs" fehlinterpretiert wird.
        _linking = false;
        final res = await repo.signUp(email, _password.text);
        if (res.session != null) {
          // Confirm-Email ist im Backend AUS -> direkt eingeloggt, kein Code.
          ref.invalidate(isAdminProvider);
          if (mounted) navigator.pop(true);
          return;
        }
        final ident = res.user?.identities;
        if (res.user != null && (ident == null || ident.isEmpty)) {
          // Enumeration-Schutz: E-Mail existiert bereits -> keine Mail.
          setState(
            () => _error =
                'Diese E-Mail ist bereits registriert. Bitte melde dich an.',
          );
          return;
        }
        // Echter Confirm-Pfad: Mail mit Code sollte unterwegs sein.
        setState(() => _awaitingOtp = true);
      }
    } on AuthException catch (e) {
      setState(() => _error = germanAuthError(e));
    } catch (e, st) {
      // Nicht verschlucken: echten Fehler loggen + sichtbar melden.
      debugPrint('signUp/link failed: $e\n$st');
      setState(() => _error = 'Registrierung fehlgeschlagen: $e');
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
      setState(() => _error = germanAuthError(e));
    } catch (_) {
      setState(() => _error = 'Bestätigung fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Code erneut anfordern: stoesst fuer die laufende Bestaetigung eine neue
  /// Mail an. Waehlt den passenden Typ (Neu-Registrierung vs. E-Mail-Wechsel
  /// beim Linking). Bei bereits bestaetigtem Konto meldet Supabase das ->
  /// nutzerfreundlich als "bitte anmelden".
  Future<void> _resendCode() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo == null) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Bitte zuerst deine E-Mail eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_linking) {
        await repo.resendEmailChangeOtp(email);
      } else {
        await repo.resendSignupOtp(email);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Neuer Code an $email gesendet.')),
        );
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      setState(() {
        _error = msg.contains('already') || msg.contains('confirmed')
            ? 'Dieses Konto ist bereits bestätigt. Bitte melde dich an.'
            : germanAuthError(e);
      });
    } catch (e, st) {
      debugPrint('resend failed: $e\n$st');
      setState(() => _error = 'Erneutes Senden fehlgeschlagen: $e');
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
          _resumeOtp
              ? 'Gib den Code ein, den wir an ${_email.text.trim()} geschickt '
                    'haben, um deine Registrierung abzuschließen.'
              : 'Wir haben dir einen Code an ${_email.text.trim()} '
                    'geschickt. Gib ihn hier ein, um dein Konto zu bestätigen.',
        ),
        const SizedBox(height: 20),
        // Im Nachtrag-Modus die E-Mail editierbar lassen (evtl. beim Login
        // vertippt) und ein erneutes Senden anbieten.
        if (_resumeOtp) ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'E-Mail',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
        ],
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
        // Immer anbieten: falls die Mail nicht ankam, kann der Code neu
        // angefordert werden (egal ob frische Registrierung oder Nachtrag).
        TextButton(
          onPressed: _busy ? null : _resendCode,
          child: const Text('Keinen Code erhalten? Erneut senden'),
        ),
      ],
    );
  }
}
