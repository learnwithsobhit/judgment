/// Loaded only after Sign in is tapped. Do not import this from `main`.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase ID token for `POST /api/v1/auth/firebase`, or throws.
///
/// Web uses Firebase's Google popup so the hosting app
/// `judgment-railway-test` does not need a separate OAuth client id.
Future<String> fetchGoogleIdToken() async {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  if (apiKey.isEmpty || appId.isEmpty || project.isEmpty) {
    throw StateError('Google sign-in is not configured');
  }
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: sender.isEmpty ? '0' : sender,
        projectId: project,
        authDomain:
            authDomain.isEmpty ? '$project.firebaseapp.com' : authDomain,
      ),
    );
  }
  final signedIn = await FirebaseAuth.instance.signInWithPopup(
    GoogleAuthProvider(),
  );
  final firebaseToken = await signedIn.user?.getIdToken();
  if (firebaseToken == null || firebaseToken.isEmpty) {
    throw StateError('Firebase did not return a token');
  }
  return firebaseToken;
}
