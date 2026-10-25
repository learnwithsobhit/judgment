/// Loaded only after Sign in is tapped. Do not import this from `main`.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase ID token for `POST /api/v1/auth/firebase`, or throws.
///
/// Web uses Firebase's Google popup so the hosting app
/// `judgment-railway-test` does not need a separate OAuth client id.
Future<String> fetchGoogleIdToken() {
  return _popupToken(GoogleAuthProvider(), 'Google sign-in is not configured');
}

/// Firebase ID token from an existing email/password account.
Future<String> signInEmailAccount({
  required String email,
  required String password,
}) {
  return _emailToken(
    () => FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );
}

/// Creates the Firebase account, then returns a fresh ID token.
Future<String> createEmailAccount({
  required String email,
  required String password,
  required String displayName,
}) {
  return _emailToken(() async {
    final created = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final name = displayName.trim();
    if (name.isNotEmpty) {
      await created.user?.updateDisplayName(name);
    }
    return created;
  });
}

/// Sends Firebase's password reset mail. Does not create a game account.
Future<void> sendEmailPasswordReset(String email) async {
  await _ensureFirebase('Email sign-in is not configured');
  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  } on FirebaseAuthException catch (error) {
    throw StateError(_emailAuthMessage(error));
  }
}

Future<String> _emailToken(Future<UserCredential> Function() signIn) async {
  await _ensureFirebase('Email sign-in is not configured');
  try {
    final signedIn = await signIn();
    final firebaseToken = await signedIn.user?.getIdToken(true);
    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Firebase did not return a token');
    }
    return firebaseToken;
  } on FirebaseAuthException catch (error) {
    throw StateError(_emailAuthMessage(error));
  }
}

String _emailAuthMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'Enter a valid email address';
    case 'user-disabled':
      return 'This email sign-in is disabled';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is wrong';
    case 'email-already-in-use':
      return 'That email already has an account. Sign in instead';
    case 'weak-password':
      return 'Use at least 6 characters';
    case 'too-many-requests':
      return 'Too many attempts. Wait and try again';
    default:
      return 'Email sign-in failed';
  }
}

Future<String> _popupToken(AuthProvider provider, String missing) async {
  await _ensureFirebase(missing);
  final signedIn = await FirebaseAuth.instance.signInWithPopup(provider);
  final firebaseToken = await signedIn.user?.getIdToken();
  if (firebaseToken == null || firebaseToken.isEmpty) {
    throw StateError('Firebase did not return a token');
  }
  return firebaseToken;
}

Future<void> _ensureFirebase(String missing) async {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  if (apiKey.isEmpty || appId.isEmpty || project.isEmpty) {
    throw StateError(missing);
  }
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: sender.isEmpty ? '0' : sender,
        projectId: project,
        authDomain: authDomain.isEmpty
            ? '$project.firebaseapp.com'
            : authDomain,
      ),
    );
  }
}
