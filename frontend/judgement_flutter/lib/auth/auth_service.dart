/// Firebase Google / Apple sign-in → Judgement bearer session.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_options.dart';
import '../networking/api_client.dart';
import '../util/legal_consent.dart';
import 'auth_store.dart';

class AuthService {
  AuthService({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;
  PersistedAuth? current;
  bool firebaseReady = false;

  ApiClient get api => _api;

  Future<void> bootstrap() async {
    if (DefaultFirebaseOptions.isConfigured) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseReady = true;
      } catch (e) {
        debugPrint('Firebase init failed: $e');
        firebaseReady = false;
      }
    }

    final saved = await loadPersistedAuth();
    if (saved == null) return;
    _api.token = saved.token;
    try {
      final me = await _api.getMe();
      current = PersistedAuth(
        sessionId: me.session.sessionId,
        nickname: me.session.nickname,
        token: me.session.token,
        avatarId: me.session.avatarId ?? me.user?.avatarId,
        avatarUrl: me.session.avatarUrl ?? me.user?.avatarUrl,
        userId: me.session.userId ?? me.user?.userId,
        provider: me.user?.provider,
        avatarKind: me.user?.avatarKind,
      );
      await savePersistedAuth(current!);
    } catch (_) {
      await clearPersistedAuth();
      _api.token = null;
      current = null;
    }
  }

  Future<PersistedAuth> signInWithGoogle() async {
    _ensureFirebase();
    final google = GoogleSignIn.instance;
    await google.initialize();
    final account = await google.authenticate();
    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    final userCred =
        await FirebaseAuth.instance.signInWithCredential(credential);
    return _exchangeFirebase(userCred.user);
  }

  Future<PersistedAuth> signInWithApple() async {
    _ensureFirebase();
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final oauth = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      accessToken: apple.authorizationCode,
    );
    final userCred = await FirebaseAuth.instance.signInWithCredential(oauth);
    final composedName = [
      apple.givenName,
      apple.familyName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return _exchangeFirebase(
      userCred.user,
      displayNameOverride: composedName.isEmpty ? null : composedName,
    );
  }

  Future<PersistedAuth> _exchangeFirebase(
    User? user, {
    String? displayNameOverride,
  }) async {
    if (user == null) {
      throw StateError('Firebase user missing after sign-in');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Firebase ID token missing');
    }
    final displayName = displayNameOverride ??
        user.displayName ??
        user.email?.split('@').first ??
        'Player';
    final auth = await _api.authFirebase(
      idToken: idToken,
      displayName: displayName,
      legalVersion: kLegalAgreementVersion,
    );
    acceptCurrentLegalAgreement();
    current = PersistedAuth(
      sessionId: auth.session.sessionId,
      nickname: auth.session.nickname,
      token: auth.session.token,
      avatarId: auth.session.avatarId ?? auth.user.avatarId,
      avatarUrl: auth.session.avatarUrl ?? auth.user.avatarUrl,
      userId: auth.user.userId,
      provider: auth.user.provider,
      avatarKind: auth.user.avatarKind,
    );
    await savePersistedAuth(current!);
    return current!;
  }

  Future<void> logout({bool inActiveGame = false}) async {
    if (inActiveGame) {
      throw StateError('leave or finish the game before logging out');
    }
    try {
      await _api.logoutMe();
    } catch (_) {}
    try {
      if (firebaseReady) await FirebaseAuth.instance.signOut();
    } catch (_) {}
    await clearPersistedAuth();
    _api.token = null;
    current = null;
  }

  Future<void> deleteAccount({bool inActiveGame = false}) async {
    if (inActiveGame) {
      throw StateError('leave or finish the game before deleting your account');
    }
    await _api.deleteMe();
    try {
      if (firebaseReady) {
        await FirebaseAuth.instance.currentUser?.delete();
      }
    } catch (_) {}
    await clearPersistedAuth();
    _api.token = null;
    current = null;
  }

  void _ensureFirebase() {
    if (!firebaseReady) {
      throw StateError(
        'Firebase is not configured. Run flutterfire configure '
        'or pass FIREBASE_API_KEY / FIREBASE_APP_ID dart-defines.',
      );
    }
  }
}
