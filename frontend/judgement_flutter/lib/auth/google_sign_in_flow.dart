/// Starts account sign-in without pulling Firebase into the first frame.
library;

import 'package:flutter/material.dart';

import 'google_auth.dart' deferred as google_auth;
import 'telegram_auth.dart' deferred as telegram_auth;

import '../networking/api_client.dart';
import '../util/legal_consent.dart';
import '../widgets/sign_in_brands.dart';
import 'account_session.dart';

/// Tests replace this so widget tests never load Firebase.
Future<void> Function(ApiClient api)? debugSignInOverride;

/// Tests replace Telegram sign-in so widget tests never load the widget script.
Future<void> Function(ApiClient api)? debugTelegramSignInOverride;

/// Tests replace email sign-in so widget tests never load Firebase.
Future<void> Function(ApiClient api)? debugEmailSignInOverride;

Future<void> signInWithGoogle(ApiClient api) async {
  final override = debugSignInOverride;
  if (override != null) {
    await override(api);
    return;
  }
  await google_auth.loadLibrary();
  final idToken = await google_auth.fetchGoogleIdToken();
  final session = await api.authFirebase(
    idToken: idToken,
    legalVersion: kLegalAgreementVersion,
  );
  await AccountSession.instance.apply(session);
}

Future<void> signInWithEmail(BuildContext context, ApiClient api) async {
  final override = debugEmailSignInOverride;
  if (override != null) {
    await override(api);
    return;
  }
  final result = await showDialog<_EmailSignInResult>(
    context: context,
    builder: (_) => const _EmailSignInDialog(),
  );
  if (result == null) return;
  await google_auth.loadLibrary();
  final idToken = result.createAccount
      ? await google_auth.createEmailAccount(
          email: result.email,
          password: result.password,
          displayName: result.name,
        )
      : await google_auth.signInEmailAccount(
          email: result.email,
          password: result.password,
        );
  final name = result.name.trim();
  final session = await api.authFirebase(
    idToken: idToken,
    displayName: name.isEmpty ? null : name,
    legalVersion: kLegalAgreementVersion,
  );
  await AccountSession.instance.apply(session);
}

Future<void> signInWithTelegram(ApiClient api) async {
  final override = debugTelegramSignInOverride;
  if (override != null) {
    await override(api);
    return;
  }
  await telegram_auth.loadLibrary();
  final idToken = await telegram_auth.fetchTelegramIdToken();
  final session = await api.authTelegram(
    idToken: idToken,
    legalVersion: kLegalAgreementVersion,
  );
  await AccountSession.instance.apply(session);
}

/// True when this game should use the signed-in account, false for a guest,
/// null when the player dismissed the choice and play should not start.
///
/// Already-signed-in players skip the popup. A closed provider popup returns
/// to this choice and does not start the game.
Future<bool?> promptToSaveRecord(BuildContext context) async {
  if (AccountSession.instance.isSignedIn) return true;
  while (context.mounted) {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save this game to your record?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sign in so this game counts on Top players. '
              'You can still play as a guest.',
            ),
            const SizedBox(height: 16),
            SignInBrandRow(
              onGoogle: () => Navigator.of(dialogContext).pop('google'),
              onEmail: () => Navigator.of(dialogContext).pop('email'),
              onTelegram: () => Navigator.of(dialogContext).pop('telegram'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('guest'),
              child: const Text('Continue as guest'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return null;
    if (choice == 'guest') return false;
    try {
      final api = ApiClient();
      if (choice == 'telegram') {
        await signInWithTelegram(api);
      } else if (choice == 'email') {
        await signInWithEmail(context, api);
      } else {
        await signInWithGoogle(api);
      }
      if (!context.mounted || !AccountSession.instance.isSignedIn) continue;
      return true;
    } catch (_) {
      if (!context.mounted) return null;
    }
  }
  return null;
}

class _EmailSignInResult {
  const _EmailSignInResult({
    required this.email,
    required this.password,
    required this.name,
    required this.createAccount,
  });

  final String email;
  final String password;
  final String name;
  final bool createAccount;
}

class _EmailSignInDialog extends StatefulWidget {
  const _EmailSignInDialog();

  @override
  State<_EmailSignInDialog> createState() => _EmailSignInDialogState();
}

class _EmailSignInDialogState extends State<_EmailSignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _nameFocus = FocusNode();
  String? _message;
  bool _busy = false;
  bool _showPassword = false;

  /// 0 email, 1 password, 2 name for a new account.
  int _step = 0;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() {
      _step = step;
      _message = null;
    });
    final node = switch (step) {
      0 => _emailFocus,
      1 => _passwordFocus,
      _ => _nameFocus,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  bool _emailOk() {
    final email = _email.text.trim();
    if (email.contains('@') && email.contains('.')) return true;
    setState(() => _message = 'Enter a valid email address');
    return false;
  }

  bool _passwordOk() {
    if (_password.text.length >= 6) return true;
    setState(() => _message = 'Use at least 6 characters');
    return false;
  }

  void _continueFromEmail() {
    if (_emailOk()) _go(1);
  }

  void _signIn() {
    if (!_emailOk() || !_passwordOk()) return;
    Navigator.of(context).pop(
      _EmailSignInResult(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
        createAccount: false,
      ),
    );
  }

  void _startCreate() {
    if (!_emailOk() || !_passwordOk()) return;
    if (_name.text.trim().isEmpty) {
      _name.text = _email.text.trim().split('@').first;
    }
    _go(2);
  }

  void _create() {
    if (!_emailOk() || !_passwordOk()) return;
    Navigator.of(context).pop(
      _EmailSignInResult(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
        createAccount: true,
      ),
    );
  }

  Future<void> _reset() async {
    if (!_emailOk()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await google_auth.loadLibrary();
      await google_auth.sendEmailPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() => _message = 'Check your email for a reset link');
    } catch (error) {
      if (!mounted) return;
      final text = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '');
      setState(() => _message = text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final phone = media.size.width < 600;
    final theme = Theme.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: phone ? Alignment.topCenter : Alignment.center,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, phone ? 12 : 24, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: _step == 0
                    ? _emailStep()
                    : _step == 1
                    ? _passwordStep()
                    : _nameStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sign in with email',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          focusNode: _emailFocus,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _continueFromEmail(),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _continueFromEmail,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Password',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => _go(0),
            child: Text(_email.text.trim(), overflow: TextOverflow.ellipsis),
          ),
        ),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          autofocus: true,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
          onSubmitted: (_) => _signIn(),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: const Text('Sign in'),
        ),
        TextButton(
          onPressed: _busy ? null : _startCreate,
          child: const Text('Create account'),
        ),
        TextButton(
          onPressed: _busy ? null : _reset,
          child: const Text('Reset password'),
        ),
      ],
    );
  }

  Widget _nameStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your name',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'This is the name on your game record.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          focusNode: _nameFocus,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _create(),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _create, child: const Text('Create account')),
        TextButton(onPressed: () => _go(1), child: const Text('Back')),
      ],
    );
  }
}
