/// Starts Google sign-in without pulling Firebase into the first frame.
library;

import 'package:flutter/material.dart';

import 'google_auth.dart' deferred as google_auth;

import '../networking/api_client.dart';
import '../util/legal_consent.dart';
import 'account_session.dart';

/// Tests replace this so widget tests never load Firebase.
Future<void> Function(ApiClient api)? debugSignInOverride;

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

/// True when this game should use the Google account, false for a guest,
/// null when the player dismissed the choice and play should not start.
///
/// Already-signed-in players skip the popup. A signed-out tap tries Google
/// first; cancel or failure asks them to retry or continue as a guest.
Future<bool?> promptToSaveRecord(BuildContext context) async {
  if (AccountSession.instance.isSignedIn) return true;
  while (context.mounted) {
    try {
      await signInWithGoogle(ApiClient());
      return true;
    } catch (_) {
      if (!context.mounted) return null;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save this game to your record?'),
          content: const Text(
            'Sign in with Google so this game counts on Top players. '
            'You can still play as a guest.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Continue as guest'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign in with Google'),
            ),
          ],
        ),
      );
      if (!context.mounted || retry == null) return null;
      if (!retry) return false;
    }
  }
  return null;
}
