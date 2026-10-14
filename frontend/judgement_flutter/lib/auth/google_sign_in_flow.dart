/// Starts Google sign-in without pulling Firebase into the first frame.
library;

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
